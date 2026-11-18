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
    ) -> (height: CGFloat, needsJob: Bool) {
        if let hit = ChatNativeRowHeightComposer
            .cachedRowHeight(forKey: memoKey) {
            lastKnownByRow[rowKey] = hit
            return (hit, false)
        }
        let needsJob = !inFlight.contains(memoKey)
            && !collectedKeys.contains(memoKey)
        return (
            lastKnownByRow[rowKey] ?? fallback, needsJob
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
    }

    /// 趟末投递：逆序投单（最新行先量），清空收
    /// 集箱
    func flushCollected() {
        let jobs = collected.reversed()
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
        guard lastKnownByRow[rowKey] != height
        else { return }
        lastKnownByRow[rowKey] = height
        schedulePublish()
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
