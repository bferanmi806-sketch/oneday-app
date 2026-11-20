import AVFoundation
import Foundation
import OneDayCore

/// 语音偏好键（设置「语音」段与聊天页自动朗读共读
/// 同一键，不许两处各写一份字面量）
enum VoiceSpeechPreferences {
    static let autoReadKey = "voice.autoReadReplies.v1"
}

/// 朗读音频引擎口（注入点）：生产实现包 AVAudio-
/// Player，测试注入假引擎——播放编排与状态机测试
/// 不碰真音频、不断言系统行为
protocol SpeechAudioEngine: AnyObject {
    /// 自然播完（成功放完）
    var onNaturalFinish: (@MainActor () -> Void)? { get set }
    /// 播放中失败（解码错误/未放完中断），带人话
    var onPlaybackFailure: (@MainActor (String) -> Void)? { get set }
    func start()
    func stop()
}

/// AVAudioPlayer 引擎：音频会话在本层收口——播前
/// 切 .playback 并激活、停/完后释放（与听写的录音
/// 会话共用同一个 AVAudioSession 的分工：听写开始
/// 前 ChatView 先停朗读，后到者重设类别，互不抢）
final class AVSpeechAudioEngine: NSObject, SpeechAudioEngine,
    AVAudioPlayerDelegate, @unchecked Sendable {
    private let player: AVAudioPlayer
    var onNaturalFinish: (@MainActor () -> Void)?
    var onPlaybackFailure: (@MainActor (String) -> Void)?

    init(data: Data) throws {
        player = try AVAudioPlayer(data: data)
        super.init()
        player.delegate = self
        player.prepareToPlay()
    }

    func start() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        player.play()
    }

    func stop() {
        player.stop()
        releaseSession()
    }

    private func releaseSession() {
        try? AVAudioSession.sharedInstance().setActive(
            false, options: [.notifyOthersOnDeactivation]
        )
    }

    // AVAudioPlayerDelegate：回调隔离口径（2026-
    // 11-10 铁律）——本回调不碰任何 actor 隔离状态，
    // 只读本引擎的闭包并显式跳回主隔离执行
    func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer, successfully flag: Bool
    ) {
        releaseSession()
        let finish = onNaturalFinish
        let failure = onPlaybackFailure
        Task { @MainActor in
            if flag {
                finish?()
            } else {
                failure?("这次朗读没成功。")
            }
        }
    }

    func audioPlayerDecodeErrorDidOccur(
        _ player: AVAudioPlayer, error: Error?
    ) {
        releaseSession()
        let failure = onPlaybackFailure
        Task { @MainActor in
            failure?("这次朗读没成功。")
        }
    }
}

/// 朗读播放器（H2-a，台账 159）：状态机在 Core
/// （SpeechPlaybackMachine），本层只做效果执行——
/// 发 speak 请求、喂引擎、管可用性精修与会话打断。
/// 全 App 单例：一处出声，点另一条即切换（状态机
/// 语义），设置页与聊天页共读同一份可用性。
@MainActor
@Observable
final class SpeechPlayer {
    static let shared = SpeechPlayer()

    /// speak 执行口（注入点在「带 appState 跑一次合
    /// 成」这一层）：生产走 performAdmin＋client，
    /// 测试注入脚本
    typealias SpeakService =
        @MainActor (AppState, String) async throws -> SpeakResponse
    /// voice-config 执行口（注入点同上）
    typealias VoiceConfigService =
        @MainActor (AppState) async throws -> VoiceConfigResponse
    /// 引擎工厂（注入点）：数据坏在此抛错、归播放失败
    typealias EngineFactory =
        @MainActor (Data) throws -> SpeechAudioEngine

    private(set) var machine = SpeechPlaybackMachine()
    private(set) var availability: VoiceAvailability = .unknown
    /// 最近一次 speak 回执的 provider（音色展示的数
    /// 据源——voice-config 不给音色、elevenlabs 与
    /// 实际合成不是同一家，探活 §2.4）
    private(set) var lastProvider: String?

    private let speakService: SpeakService
    private let voiceConfigService: VoiceConfigService
    private let engineFactory: EngineFactory
    private var engine: SpeechAudioEngine?
    private var requestTask: Task<Void, Never>?
    private var lastConfigFetchAt: Date?
    private var configFetchInFlight = false
    /// 只在 init 写一次、deinit 读一次移除——deinit 是
    /// 非隔离上下文，故标 nonisolated(unsafe)（写入发生
    /// 在对象发布之前、无并发读者）
    private nonisolated(unsafe) var interruptionObserver:
        NSObjectProtocol?

    init(
        speakService: @escaping SpeakService = SpeechPlayer.liveSpeakService,
        voiceConfigService: @escaping VoiceConfigService =
            SpeechPlayer.liveVoiceConfigService,
        engineFactory: @escaping EngineFactory =
            SpeechPlayer.liveEngineFactory
    ) {
        self.speakService = speakService
        self.voiceConfigService = voiceConfigService
        self.engineFactory = engineFactory
        // 音频打断（来电等）：开始即停播——系统回调
        // 不继承隔离，闭包内只跳回主隔离调 stop
        interruptionObserver = NotificationCenter.default
            .addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] notification in
                let raw = notification.userInfo?[
                    AVAudioSessionInterruptionTypeKey
                ] as? UInt
                guard raw == AVAudioSession.InterruptionType
                    .began.rawValue else { return }
                Task { @MainActor [weak self] in
                    self?.stop()
                }
            }
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(
                interruptionObserver
            )
        }
    }

    // MARK: - 生产执行口

    static func liveSpeakService(
        appState: AppState, text: String
    ) async throws -> SpeakResponse {
        try await appState.performAdmin { client, config in
            try await client.speak(config: config, text: text)
        }
    }

    static func liveVoiceConfigService(
        appState: AppState
    ) async throws -> VoiceConfigResponse {
        try await appState.performAdmin { client, config in
            try await client.voiceConfig(config: config)
        }
    }

    static func liveEngineFactory(
        data: Data
    ) throws -> SpeechAudioEngine {
        try AVSpeechAudioEngine(data: data)
    }

    // MARK: - 可用性

    /// 读 voice-config 刷新可用性（节流 300 秒，进对
    /// 话页/设置页时调）：合并口径在 Core——配置证
    /// 伪可定未开通、暂定可用不许翻 speak 已证伪的
    /// 态；拉失败不改现态（未知保持未知，不造假）
    func refreshAvailability(
        appState: AppState, force: Bool = false
    ) async {
        if !force, let last = lastConfigFetchAt,
           Date().timeIntervalSince(last) < 300 {
            return
        }
        guard !configFetchInFlight else { return }
        configFetchInFlight = true
        lastConfigFetchAt = Date()
        defer { configFetchInFlight = false }
        do {
            let config = try await voiceConfigService(appState)
            availability = VoiceAvailability
                .mergingConfigAssessment(
                    current: availability,
                    assessed: VoiceAvailability.assess(
                        config: config
                    )
                )
        } catch {
            // 拉不到不改现态
        }
    }

    /// 进页触发口（同步面只许起任务，不许 await）
    func refreshAvailabilityOnAppear(appState: AppState) {
        Task { await refreshAvailability(appState: appState) }
    }

    // MARK: - 播放控制

    /// 长按菜单「朗读/停止朗读」：状态机 tap 语义
    /// （同条停、异条切换、失败重试）
    func toggle(
        entryID: UUID, content: String, appState: AppState
    ) {
        let effects = machine.tap(entryID: entryID)
        run(effects, entryID: entryID, content: content,
            appState: appState)
    }

    /// 自动朗读新回复（设置开关开时由落定点调用）：
    /// 只在静默/失败态起播——用户正在听别条时不抢，
    /// 可用性已证伪（未开通）时不出声、不报错
    func autoRead(
        entryID: UUID, content: String, appState: AppState
    ) {
        guard availability != .unavailable else { return }
        switch machine.state {
        case .idle, .failed:
            break
        case .requesting, .playing:
            return
        }
        let effects = machine.tap(entryID: entryID)
        run(effects, entryID: entryID, content: content,
            appState: appState)
    }

    /// 停播（离开页面/发送新消息/开始听写/音频打断
    /// 共用）：活动态拆请求与引擎，静默态空转
    func stop() {
        for effect in machine.stop() where effect == .tearDown {
            tearDown()
        }
    }

    private func run(
        _ effects: [SpeechPlaybackMachine.Effect],
        entryID: UUID, content: String, appState: AppState
    ) {
        for effect in effects {
            switch effect {
            case .tearDown:
                tearDown()
            case .startRequest(let id):
                startRequest(
                    entryID: id, content: content,
                    appState: appState
                )
            case .beginPlayback:
                // tap 不产此效果（由请求成功点直产）
                break
            }
        }
    }

    private func tearDown() {
        requestTask?.cancel()
        requestTask = nil
        engine?.stop()
        engine = nil
    }

    private func startRequest(
        entryID: UUID, content: String, appState: AppState
    ) {
        requestTask?.cancel()
        requestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // 文本预处理：剥完为空（纯图片/纯标记回
            // 复）不发请求，如实落失败态
            guard let text = SpeechText.make(
                fromMarkdown: content
            ) else {
                _ = machine.requestFailed(
                    entryID: entryID,
                    message: "这条回复没有可朗读的文字。"
                )
                return
            }
            // 首次点朗读且可用性未知：先读配置——配
            // 置证伪未开通就不发 speak（施工图口径）
            if availability == .unknown {
                await refreshAvailability(
                    appState: appState, force: true
                )
                if availability == .unavailable {
                    _ = machine.requestFailed(
                        entryID: entryID,
                        message: "这台服务器还没开通朗读。"
                    )
                    return
                }
            }
            do {
                let response = try await speakService(
                    appState, text
                )
                guard !Task.isCancelled else { return }
                availability = VoiceAvailability.refined(
                    current: availability, by: .succeeded
                )
                if let provider = response.provider {
                    lastProvider = provider
                }
                let effects = machine.requestSucceeded(
                    entryID: entryID
                )
                // 态已被切走（用户停了/切了条）：回执
                // 丢弃，不许把上一条的音频播出来
                guard effects.contains(
                    .beginPlayback(entryID: entryID)
                ) else { return }
                guard let data = response.audioData else {
                    _ = machine.playbackFailed(
                        entryID: entryID,
                        message: "这次朗读没成功。"
                    )
                    return
                }
                beginPlayback(entryID: entryID, data: data)
            } catch let error as HermesError {
                guard !Task.isCancelled else { return }
                if error.isSpeechProviderUnavailable {
                    availability = VoiceAvailability.refined(
                        current: availability,
                        by: .providerUnavailable
                    )
                    _ = machine.requestFailed(
                        entryID: entryID,
                        message: "这台服务器还没开通朗读。"
                    )
                } else if case .demoLimitReached = error {
                    _ = machine.requestFailed(
                        entryID: entryID,
                        message: error.userMessage
                    )
                } else {
                    _ = machine.requestFailed(
                        entryID: entryID,
                        message: "这次朗读没成功。"
                    )
                }
            } catch {
                guard !Task.isCancelled else { return }
                _ = machine.requestFailed(
                    entryID: entryID,
                    message: "这次朗读没成功。"
                )
            }
        }
    }

    private func beginPlayback(entryID: UUID, data: Data) {
        do {
            let newEngine = try engineFactory(data)
            newEngine.onNaturalFinish = { [weak self] in
                guard let self else { return }
                _ = machine.playbackFinished(entryID: entryID)
                // 只清自己这台：迟到回调不许把已切换
                // 的新引擎引用抹掉（状态机已按条目
                // id 对账，这里只管引用卫生）
                if engine === newEngine { engine = nil }
            }
            newEngine.onPlaybackFailure = { [weak self] message in
                guard let self else { return }
                _ = machine.playbackFailed(
                    entryID: entryID, message: message
                )
                if engine === newEngine { engine = nil }
            }
            engine = newEngine
            newEngine.start()
        } catch {
            _ = machine.playbackFailed(
                entryID: entryID, message: "这次朗读没成功。"
            )
        }
    }
}
