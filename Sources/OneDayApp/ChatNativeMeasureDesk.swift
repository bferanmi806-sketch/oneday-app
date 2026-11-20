import Foundation
import Observation
import UIKit

/// 量测工单（§331）：主线程组装（facet＋条目快
/// 照＋环境，全部值），后台队列执行 measure 得
/// 行高、按 memoKey 回填整行备忘缓存。@unchecked
/// Sendable 的依据：载荷是组装后不可变的值快照
/// （与 §251 LayoutAttributedBox 同口径），
/// measure 只读快照、只写线程安全缓存（NSCache/
/// ParseMemoBox 家族）与 §251 量测池的每线栈
struct ChatNativeRowMeasureJob: @unchecked Sendable {
    let memoKey: String
    let rowKey: String
    let measure: () -> CGFloat
}

/// 后台量测台（§331，0.50.70 热修题 3 根治）
///
/// 大厂聊天列表量测的全件形态在本仓的落点（微
/// 信预排版/Signal 静态量测管线同构）：行高不
/// 在主线程 body 求值里现算——ChatView 构建行
/// 时先查整行备忘缓存（§330 缓存层、命中直用
/// 确定高）；未命中则组装工单投本台，后台串行
/// 队列以 facet 快照整行量测（文本量测走 §251
/// 量测池的每线 TextKit 栈），结果回填缓存并
/// 发发布信号，ChatView 随之以新高重喂列表
/// （控制器高度-only 落写、不重配 cell、不扰
/// 手势）。打开会话即全表投单＝预排版：用户滚
/// 到某行前，该行高多半已就绪。
///
/// 纪律：
/// - 同一 memoKey 同时只许一单在飞（resolve 的
///   needsJob 判定＋collect 双重去重）；修订一
///   变 memoKey 即变、新单另投，旧单结果只回填
///   自己键的缓存格，不会串到新行；
/// - 未就绪行的当趟高＝该行上次用高（lastKnown，
///   跨修订沿用）或合成器兜底高——估计→确定的
///   修正恒走高度-only 路径，与题 1 在途保护正
///   交（重配才伤手势、改高不伤）；
/// - 发布信号合并（40ms 窗）：冷开长会话几百
///   单陆续完成不逐单触发重渲；
/// - 队列串行：量测次序＝投单次序的逆序（趟末
///   flushCollected 按行序逆序投递——最新行靠
///   底、用户视线所在，先量先就绪）
/// - 台账 190（上滑根治）：投单次序改方向感知
///   ——resolve 调用序即行序（ChatView 每趟按行
///   序逐行 resolve），本台据此自建行序账；顶可
///   见行锚（noteTopVisible）向上移＝上滑趋势
///   时，flush 改按「锚上方最近行优先」投单，
///   不再让上滑方向排在队尾。另设 measureNow
///   就地量测口：将入视口而未就绪的行在布局提
///   供者问高时同步量出确定高（学 Telegram 无
///   估算高——120 兜底只留给永不入视口的行）；
///   积压计数入静态账盒供诊断面回读
@MainActor
@Observable
final class ChatNativeRowMeasureDesk {
    /// 发布代次：任一工单完成且其行高与当趟用高
    /// 不同即合并 bump 一次——ChatView 读此值入
    /// body 依赖、bump 即重喂行高
    private(set) var publishedRevision = 0

    @ObservationIgnored
    private let queue = DispatchQueue(
        label: "site.didichou.oneday.rowmeasure",
        qos: .userInitiated
    )
    @ObservationIgnored
    private var inFlight: Set<String> = []
    @ObservationIgnored
    private var collected: [ChatNativeRowMeasureJob] = []
    @ObservationIgnored
    private var collectedKeys: Set<String> = []
    @ObservationIgnored
    private var lastKnownByRow: [String: CGFloat] = [:]
    @ObservationIgnored
    private var publishTask: Task<Void, Never>?

    /// 同步读口（body 求值内）：缓存命中回确定
    /// 高并记 lastKnown；未命中回 lastKnown/兜底
    /// 高，needsJob 报是否该为本行组装工单（在
    /// 飞/已收集的不重复组装——组装要快照 facet、
    /// 不许白费）
    func resolve(
        memoKey: String, rowKey: String,
        fallback: CGFloat
    ) -> (
        height: CGFloat, needsJob: Bool, isExact: Bool
    ) {
        noteResolveOrder(rowKey)
        if let hit = ChatNativeRowHeightComposer
            .cachedRowHeight(forKey: memoKey) {
            lastKnownByRow[rowKey] = hit
            // 命中即该行工单使命完成：清就地量测
            // 留账（measureNow 再被问到时回缓存值
            // 的路随之关闭——喂入链已以确定高重
            // 喂、本行不再临界）
            jobsByRowKey[rowKey] = nil
            memoKeyByRowKey[rowKey] = nil
            return (hit, false, true)
        }
        let needsJob = !inFlight.contains(memoKey)
            && !collectedKeys.contains(memoKey)
        return (
            lastKnownByRow[rowKey] ?? fallback, needsJob,
            false
        )
    }

    /// 收集本趟工单（趟末 flushCollected 统一投
    /// 递；同键重复收集只留一单）
    func collect(_ job: ChatNativeRowMeasureJob) {
        guard !inFlight.contains(job.memoKey),
              !collectedKeys.contains(job.memoKey)
        else { return }
        collected.append(job)
        collectedKeys.insert(job.memoKey)
        jobsByRowKey[job.rowKey] = job
        memoKeyByRowKey[job.rowKey] = job.memoKey
        noteBacklog()
    }

    /// 趟末投递：默认逆序投单（最新行先量）；上
    /// 滑趋势在场时按锚距投单（锚上方最近行先
    /// 量、锚下方次之），清空收集箱。投递前先以
    /// 本趟 resolve 序重建行序账
    func flushCollected() {
        rebuildRowIndex()
        let jobs = orderedForDispatch(collected)
        collected = []
        collectedKeys = []
        for job in jobs {
            guard !inFlight.contains(job.memoKey)
            else { continue }
            inFlight.insert(job.memoKey)
            queue.async { [weak self] in
                let height = job.measure()
                ChatNativeRowHeightComposer
                    .storeRowHeight(
                        height, forKey: job.memoKey
                    )
                let memoKey = job.memoKey
                let rowKey = job.rowKey
                Task { @MainActor [weak self] in
                    self?.finish(
                        memoKey: memoKey, rowKey: rowKey,
                        height: height
                    )
                }
            }
        }
    }

    private func finish(
        memoKey: String, rowKey: String,
        height: CGFloat
    ) {
        inFlight.remove(memoKey)
        ChatMeasureDeskBacklog.noteFinished()
        noteBacklog()
        guard lastKnownByRow[rowKey] != height
        else { return }
        lastKnownByRow[rowKey] = height
        schedulePublish()
    }

    // MARK: - 台账 190：方向感知／就地量测／积压账

    /// 就地量测留账：已收集/在飞工单按行键留存，
    /// measureNow 据此同步执行；resolve 命中或
    /// 工单完成后清
    @ObservationIgnored
    private var jobsByRowKey:
        [String: ChatNativeRowMeasureJob] = [:]
    @ObservationIgnored
    private var memoKeyByRowKey: [String: String] = [:]
    /// 行序账：resolve 调用序（＝喂入行序）逐趟
    /// 累积、flush 时折成行键→序映射
    @ObservationIgnored
    private var resolveOrderSeen: [String] = []
    @ObservationIgnored
    private var resolveOrderSet: Set<String> = []
    @ObservationIgnored
    private var rowIndexByKey: [String: Int] = [:]
    /// 顶可见锚与上滑趋势（noteTopVisible 维护）
    @ObservationIgnored
    private var anchorRowKey: String?
    @ObservationIgnored
    private var lastAnchorIndex: Int?
    @ObservationIgnored
    private var trendUp = false

    private func noteResolveOrder(_ rowKey: String) {
        guard !resolveOrderSet.contains(rowKey)
        else { return }
        resolveOrderSet.insert(rowKey)
        resolveOrderSeen.append(rowKey)
    }

    private func rebuildRowIndex() {
        guard !resolveOrderSeen.isEmpty else { return }
        for (index, key) in resolveOrderSeen
            .enumerated() {
            rowIndexByKey[key] = index
        }
        resolveOrderSeen = []
        resolveOrderSet = []
    }

    /// 顶可见行上报（ChatView 原生面回调）：锚序
    /// 下移（顶可见行变旧）＝上滑趋势；上滑期间
    /// flush 按锚距投单。锚行不在行序账内（直播
    /// 行等不经 resolve 的行）时不更新趋势
    func noteTopVisible(rowKey: String) {
        anchorRowKey = rowKey
        guard let index = rowIndexByKey[rowKey]
        else { return }
        if let last = lastAnchorIndex, index != last {
            trendUp = index < last
        }
        lastAnchorIndex = index
    }

    /// 投单次序：无上滑趋势＝逆序（最新先量，现
    /// 行口径）；上滑趋势＋锚在账＝锚上方行按距
    /// 锚近者先、锚下方行按序次之、无序行垫底
    private func orderedForDispatch(
        _ jobs: [ChatNativeRowMeasureJob]
    ) -> [ChatNativeRowMeasureJob] {
        guard trendUp,
              let anchor = anchorRowKey,
              let anchorIndex = rowIndexByKey[anchor]
        else { return Array(jobs.reversed()) }
        func index(of job: ChatNativeRowMeasureJob)
            -> Int? {
            rowIndexByKey[job.rowKey]
        }
        let above = jobs
            .filter { (index(of: $0) ?? .max) <= anchorIndex }
            .sorted {
                (index(of: $0) ?? .max)
                    > (index(of: $1) ?? .max)
            }
        let below = jobs
            .filter { (index(of: $0) ?? .max) > anchorIndex }
            .sorted {
                (index(of: $0) ?? .max)
                    < (index(of: $1) ?? .max)
            }
        return above + below
    }

    /// 就地量测（台账 190②）：行将入视口而当趟
    /// 高仍非确定值时，布局侧经 ChatView 闭包调
    /// 本口同步执行该行工单——单行量测毫秒级、
    /// 入屏前付清，不让估算高在屏上跳。工单已
    /// 在后台在飞时同闭包会并发执行一次（载荷
    /// 是不可变快照、量测只写线程安全缓存、同
    /// 输入同输出，后到 finish 以同值对账无害）；
    /// 工单已完成则回缓存确定值；无工单无缓存
    /// 回 nil（布局侧保留当趟喂入高）
    func measureNow(rowKey: String) -> CGFloat? {
        guard let job = jobsByRowKey[rowKey] else {
            guard let memoKey = memoKeyByRowKey[rowKey]
            else { return nil }
            return ChatNativeRowHeightComposer
                .cachedRowHeight(forKey: memoKey)
        }
        // 工单已在后台完成（缓存已落、留账未清）
        // 时直回缓存值，不重跑量测
        if let cached = ChatNativeRowHeightComposer
            .cachedRowHeight(forKey: job.memoKey) {
            jobsByRowKey[rowKey] = nil
            return cached
        }
        let height = job.measure()
        ChatNativeRowHeightComposer.storeRowHeight(
            height, forKey: job.memoKey
        )
        if let position = collected.firstIndex(
            where: { $0.memoKey == job.memoKey }
        ) {
            collected.remove(at: position)
            collectedKeys.remove(job.memoKey)
        }
        jobsByRowKey[rowKey] = nil
        ChatMeasureDeskBacklog.noteSyncMeasured()
        noteBacklog()
        if lastKnownByRow[rowKey] != height {
            lastKnownByRow[rowKey] = height
            schedulePublish()
        }
        return height
    }

    /// 积压账回写（静态账盒：诊断面无实例可读，
    /// 与 ChatLagProbe 计数盒同式）
    private func noteBacklog() {
        ChatMeasureDeskBacklog.notePending(
            collected: collected.count,
            inFlight: inFlight.count
        )
    }

    /// 诊断面读口（台账 190⑤）：量测台积压一行
    static func backlogLine() -> String {
        ChatMeasureDeskBacklog.line()
    }

    /// 发布合并：40ms 窗内多次完成只 bump 一次
    private func schedulePublish() {
        guard publishTask == nil else { return }
        publishTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: 40_000_000
            )
            guard let self else { return }
            self.publishTask = nil
            self.publishedRevision += 1
        }
    }
}

/// 量测台积压账盒（台账 190⑤）：静态计数——收
/// 集/在飞积压（最近一台量测台的回写，多台并存
/// 时后写者为准）、完成总数、就地量测次数。诊
/// 断面（ChatDiagnosticsView）经量测台的静态读
/// 口回读，生产路径只记账、无行为影响（与
/// ChatLagProbe 计数盒同式）
enum ChatMeasureDeskBacklog {
    private static let box = BacklogBox()

    static func notePending(
        collected: Int, inFlight: Int
    ) {
        box.notePending(
            collected: collected, inFlight: inFlight
        )
    }

    static func noteFinished() { box.noteFinished() }
    static func noteSyncMeasured() {
        box.noteSyncMeasured()
    }

    static func line() -> String { box.line() }

    /// 测试读口：清账
    static func reset() { box.reset() }
}

private final class BacklogBox: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingCollected = 0
    private var pendingInFlight = 0
    private var finishedTotal = 0
    private var syncMeasuredTotal = 0

    func notePending(collected: Int, inFlight: Int) {
        lock.lock()
        pendingCollected = collected
        pendingInFlight = inFlight
        lock.unlock()
    }

    func noteFinished() {
        lock.lock()
        finishedTotal += 1
        lock.unlock()
    }

    func noteSyncMeasured() {
        lock.lock()
        syncMeasuredTotal += 1
        lock.unlock()
    }

    func line() -> String {
        lock.lock()
        defer { lock.unlock() }
        return "积压 \(pendingCollected + pendingInFlight)"
            + "（排队 \(pendingCollected)／在飞 \(pendingInFlight)）"
            + "·已量 \(finishedTotal)·就地量测 \(syncMeasuredTotal)"
    }

    func reset() {
        lock.lock()
        pendingCollected = 0
        pendingInFlight = 0
        finishedTotal = 0
        syncMeasuredTotal = 0
        lock.unlock()
    }
}
