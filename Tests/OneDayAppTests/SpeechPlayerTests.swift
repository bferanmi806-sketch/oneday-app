import XCTest
import OneDayCore
@testable import OneDayApp

/// 朗读播放器装配钉测（H2-a，台账 159）：服务口与
/// 引擎口全注入脚本/假件，只验编排——点按起播、切
/// 换先拆后发、失败分型落态、可用性精修（配置暂定
/// 可用不许翻实调证伪）、自动朗读不抢播。DTO/判定/
/// 状态机的纯逻辑在 OneDayCoreTests.VoiceSpeech-
/// Tests 钉。
@MainActor
final class SpeechPlayerTests: XCTestCase {

    final class FakeEngine {
        @MainActor var onNaturalFinish: (@MainActor () -> Void)?
        @MainActor var onPlaybackFailure: (@MainActor (String) -> Void)?
        private(set) var started = false
        private(set) var stopped = false
        private(set) var paused = false
        private(set) var resumed = false
        func start() { started = true }
        func stop() { stopped = true }
        func pause() { paused = true }
        func resume() { resumed = true }
    }

    /// 脚本台：服务回执/失败可换，调用留痕
    final class Stub {
        var speakCalls: [String] = []
        var configCalls = 0
        var engines: [FakeEngine] = []
        var speakHandler: (String) async throws -> SpeakResponse = {
            _ in Stub.successResponse
        }
        var configHandler: () async throws -> VoiceConfigResponse = {
            Stub.enabledConfig
        }

        static var successResponse: SpeakResponse {
            SpeakResponse(
                ok: true,
                dataURL: "data:audio/mpeg;base64,"
                    + Data("fake-audio".utf8).base64EncodedString(),
                mimeType: "audio/mpeg", provider: "edge"
            )
        }

        /// 开通后的真实配置形态（reason 非空恒定）
        static var enabledConfig: VoiceConfigResponse {
            VoiceConfigResponse(
                ok: true,
                stt: .init(
                    mode: "relay",
                    reason: "command/plugin provider",
                    streaming: false
                ),
                tts: .init(
                    mode: "relay",
                    reason: "provider 'edge' has no client wire",
                    streaming: nil
                )
            )
        }
    }

    private func makePlayer(stub: Stub) -> SpeechPlayer {
        SpeechPlayer(
            speakService: { _, text in
                stub.speakCalls.append(text)
                return try await stub.speakHandler(text)
            },
            voiceConfigService: { _ in
                stub.configCalls += 1
                return try await stub.configHandler()
            },
            engineFactory: { _ in
                let engine = FakeEngine()
                stub.engines.append(engine)
                return engine
            }
        )
    }

    private func makeAppState() -> AppState {
        AppState(client: DemoHermesClient(), demoMode: .connected)
    }

    /// 等状态机落到期望态（播放器请求走 MainActor
    /// 任务，轮询让行）
    private func waitForState(
        _ player: SpeechPlayer,
        _ expected: SpeechPlaybackMachine.State,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        for _ in 0..<200 {
            if player.machine.state == expected { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail(
            "状态未落到 \(expected)，现态 \(player.machine.state)",
            file: file, line: line
        )
    }

    private let entryA = UUID()
    private let entryB = UUID()

    func testTogglePlaysAndRefinesAvailability() async {
        let stub = Stub()
        let player = makePlayer(stub: stub)
        player.toggle(
            entryID: entryA, content: "你好，这是**回复**。",
            appState: makeAppState()
        )
        await waitForState(player, .playing(entryID: entryA))
        // 文本先剥 Markdown 再出门
        XCTAssertEqual(stub.speakCalls, ["你好，这是回复。"])
        XCTAssertEqual(stub.engines.count, 1)
        XCTAssertTrue(stub.engines[0].started)
        // 实调成功精修可用性、provider 留痕（音色展示源）
        XCTAssertEqual(player.availability, .available)
        XCTAssertEqual(player.lastProvider, "edge")
    }

    func testToggleSameStopsAndOtherSwitches() async {
        let stub = Stub()
        let player = makePlayer(stub: stub)
        let appState = makeAppState()
        player.toggle(entryID: entryA, content: "甲", appState: appState)
        await waitForState(player, .playing(entryID: entryA))

        // 异条切换：旧引擎先停、新请求再发
        player.toggle(entryID: entryB, content: "乙", appState: appState)
        await waitForState(player, .playing(entryID: entryB))
        XCTAssertTrue(stub.engines[0].stopped)
        XCTAssertEqual(stub.engines.count, 2)
        XCTAssertTrue(stub.engines[1].started)

        // 同条再点：停
        player.toggle(entryID: entryB, content: "乙", appState: appState)
        XCTAssertEqual(player.machine.state, .idle)
        XCTAssertTrue(stub.engines[1].stopped)
    }

    func testNaturalFinishReturnsToIdle() async {
        let stub = Stub()
        let player = makePlayer(stub: stub)
        player.toggle(
            entryID: entryA, content: "甲",
            appState: makeAppState()
        )
        await waitForState(player, .playing(entryID: entryA))
        stub.engines[0].onNaturalFinish?()
        XCTAssertEqual(player.machine.state, .idle)
    }

    func testProviderUnavailableRefinesAndReports() async {
        let stub = Stub()
        stub.speakHandler = { _ in
            throw HermesError.speechProviderUnavailable
        }
        let player = makePlayer(stub: stub)
        player.toggle(
            entryID: entryA, content: "甲",
            appState: makeAppState()
        )
        await waitForState(
            player,
            .failed(
                entryID: entryA, message: "这台服务器还没开通朗读。"
            )
        )
        XCTAssertEqual(player.availability, .unavailable)
        XCTAssertTrue(stub.engines.isEmpty)
    }

    func testGenericFailureReportsPlainly() async {
        let stub = Stub()
        stub.speakHandler = { _ in
            throw HermesError.unexpectedStatus(
                endpoint: "朗读", status: 500
            )
        }
        let player = makePlayer(stub: stub)
        player.toggle(
            entryID: entryA, content: "甲",
            appState: makeAppState()
        )
        await waitForState(
            player,
            .failed(entryID: entryA, message: "这次朗读没成功。")
        )
        // 一般失败不携带可用性信息：暂定可用不被冲掉
        XCTAssertEqual(player.availability, .available)
    }

    func testConfigRefutationSkipsSpeak() async {
        let stub = Stub()
        stub.configHandler = {
            VoiceConfigResponse(ok: false, stt: nil, tts: nil)
        }
        let player = makePlayer(stub: stub)
        player.toggle(
            entryID: entryA, content: "甲",
            appState: makeAppState()
        )
        await waitForState(
            player,
            .failed(
                entryID: entryA, message: "这台服务器还没开通朗读。"
            )
        )
        // 配置已证伪：speak 一次都不许发
        XCTAssertTrue(stub.speakCalls.isEmpty)
        XCTAssertEqual(player.availability, .unavailable)
    }

    func testConfigAssessmentNeverResurrectsRefuted() async {
        let stub = Stub()
        stub.speakHandler = { _ in
            throw HermesError.speechProviderUnavailable
        }
        let player = makePlayer(stub: stub)
        let appState = makeAppState()
        player.toggle(entryID: entryA, content: "甲", appState: appState)
        await waitForState(
            player,
            .failed(
                entryID: entryA, message: "这台服务器还没开通朗读。"
            )
        )
        XCTAssertEqual(player.availability, .unavailable)
        // 配置仍是暂定可用形态，强刷也不许翻回
        await player.refreshAvailability(
            appState: appState, force: true
        )
        XCTAssertEqual(player.availability, .unavailable)
    }

    func testEmptyContentFailsWithoutRequest() async {
        let stub = Stub()
        let player = makePlayer(stub: stub)
        player.toggle(
            entryID: entryA, content: "![](x.png)",
            appState: makeAppState()
        )
        await waitForState(
            player,
            .failed(
                entryID: entryA,
                message: "这条回复没有可朗读的文字。"
            )
        )
        XCTAssertTrue(stub.speakCalls.isEmpty)
    }

    func testAutoReadDoesNotInterruptOrForce() async {
        let stub = Stub()
        let player = makePlayer(stub: stub)
        let appState = makeAppState()
        player.toggle(entryID: entryA, content: "甲", appState: appState)
        await waitForState(player, .playing(entryID: entryA))
        // 正在听别条：自动朗读不抢
        player.autoRead(entryID: entryB, content: "乙", appState: appState)
        XCTAssertEqual(player.machine.state, .playing(entryID: entryA))
        XCTAssertEqual(stub.speakCalls.count, 1)

        // 未开通：自动朗读静默不发
        let stub2 = Stub()
        stub2.configHandler = {
            VoiceConfigResponse(ok: false, stt: nil, tts: nil)
        }
        let player2 = makePlayer(stub: stub2)
        await player2.refreshAvailability(
            appState: appState, force: true
        )
        XCTAssertEqual(player2.availability, .unavailable)
        player2.autoRead(
            entryID: entryB, content: "乙", appState: appState
        )
        XCTAssertEqual(player2.machine.state, .idle)
        XCTAssertTrue(stub2.speakCalls.isEmpty)
    }

    func testStopTearsDownRequest() async {
        let stub = Stub()
        let player = makePlayer(stub: stub)
        let appState = makeAppState()
        player.toggle(entryID: entryA, content: "甲", appState: appState)
        await waitForState(player, .playing(entryID: entryA))
        player.stop()
        XCTAssertEqual(player.machine.state, .idle)
        XCTAssertTrue(stub.engines[0].stopped)
    }

    /// 暂停/继续（D1）：转发当前引擎、不 tearDown
    /// ——引擎仍是同一台、speak 不重发（断点续播）；
    /// 暂停后 stop 仍全拆
    func testPauseResumeForwardsWithoutTeardown() async {
        let stub = Stub()
        let player = makePlayer(stub: stub)
        let appState = makeAppState()
        player.toggle(
            entryID: entryA, content: "甲", appState: appState
        )
        await waitForState(player, .playing(entryID: entryA))

        player.pause()
        XCTAssertEqual(
            player.machine.state, .paused(entryID: entryA)
        )
        XCTAssertTrue(stub.engines[0].paused)
        XCTAssertFalse(stub.engines[0].stopped)

        player.resume()
        XCTAssertEqual(
            player.machine.state, .playing(entryID: entryA)
        )
        XCTAssertTrue(stub.engines[0].resumed)
        XCTAssertEqual(stub.engines.count, 1)
        XCTAssertEqual(stub.speakCalls.count, 1)

        // 暂停中 stop：全拆
        player.pause()
        player.stop()
        XCTAssertEqual(player.machine.state, .idle)
        XCTAssertTrue(stub.engines[0].stopped)
    }

    /// 暂停中自动朗读不抢（D1）：用户主动暂停后，
    /// 新回复的自动朗读不许打断、不许发新请求
    func testAutoReadDoesNotInterruptPaused() async {
        let stub = Stub()
        let player = makePlayer(stub: stub)
        let appState = makeAppState()
        player.toggle(
            entryID: entryA, content: "甲", appState: appState
        )
        await waitForState(player, .playing(entryID: entryA))
        player.pause()
        XCTAssertEqual(
            player.machine.state, .paused(entryID: entryA)
        )
        player.autoRead(
            entryID: entryB, content: "乙", appState: appState
        )
        XCTAssertEqual(
            player.machine.state, .paused(entryID: entryA)
        )
        XCTAssertEqual(stub.speakCalls.count, 1)
    }
}

/// 假引擎的一致性同样隔离在主 actor（与生产引擎同口径）
extension SpeechPlayerTests.FakeEngine: @MainActor SpeechAudioEngine {}
