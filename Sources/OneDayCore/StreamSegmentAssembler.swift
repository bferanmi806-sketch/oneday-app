import Foundation

/// 流式分段装配器（0.50.53，第 93 条）：在发布闸之上
/// 补「段」这一维——一轮 run 的正文不是一条文本，
/// 而是被工具调用切开的若干助理段（服务端落库即
/// 一段一条消息：段 A 正文→工具→段 B 正文）。段的
/// 身份以服务端事件序为准：tool.started 是段边界
/// 信号，边界到达即封存当前段、下一段增量进新缓冲。
///
/// 病根（第 93 条定案）：旧装配只有一只整轮单缓冲
/// 的 StreamPublishGate，followRunEvents 的工具事
/// 件分支从不封段——跨工具边界后，新段增量继续拼
/// 进上一段的缓冲，直播呈现里上一段全文被带进下
/// 一段（半截落盘后再重挂 events 时更与已落盘条目
/// 同屏双份呈现）。修法不是呈现层去重，而是装配
/// 层按段分开：每段一只独立发布闸（发布节流口径
/// 与 §32 逐字不变，段内拼接行为零变更），封段后
/// 旧段只读、新段从空缓冲起步。
///
/// 纯逻辑：时刻由调用方以单调时钟（秒）注入，与
/// StreamPublishGate 同制，单测可钉死回放。
public struct StreamSegmentAssembler: Equatable {
    /// 已封存段的全文（按事件序，只读）：封段时经
    /// flush 取精确全文，非空才入列——空段不存在
    public private(set) var sealedSegments: [String] = []
    /// 当前打开段的发布闸（本段增量在此累积/发布）
    public private(set) var currentGate = StreamPublishGate()

    public init() {}

    /// 当前段已发布的快照（视图呈现当前段用）
    public var currentPublished: String {
        currentGate.publishedText
    }

    /// 当前段精确全文（已发布＋待发布）：收尾判定
    /// 与落盘走它，不经发布快照、节流永不丢字
    public var currentFullText: String {
        currentGate.fullText
    }

    /// 当前段是否已有任何内容
    public var hasCurrentContent: Bool {
        currentGate.hasContent
    }

    /// 全部段的精确全文（事件序）：封存段＋当前段
    /// （有内容才计入）——半截落盘按段成条的源头
    public var fullSegments: [String] {
        var all = sealedSegments
        if currentGate.hasContent {
            all.append(currentGate.fullText)
        }
        return all
    }

    /// 落定合并口径的全文：各段以空行连接——与
    /// RunTranscriptSettle 对 transcript 各段正文的
    /// 拼接（"\n\n"）逐字同制，直播期的兜底落定与
    /// transcript 落定自此同文
    public var mergedFullText: String {
        fullSegments.joined(separator: "\n\n")
    }

    /// 喂入当前段一个增量。发布条件与 StreamPublish-
    /// Gate 逐字相同（首增量立即发布/80ms 窗/64 字
    /// 阈值）；发布时返回当前段的新快照，否则 nil
    @discardableResult
    public mutating func offer(
        _ delta: String, at now: TimeInterval
    ) -> String? {
        currentGate.offer(delta, at: now)
    }

    /// 定时巡查（视图侧 ticker）：只作用于当前段——
    /// 封存段早已 flush 定稿，不存在待发布残余
    public mutating func collectDue(
        at now: TimeInterval
    ) -> String? {
        currentGate.collectDue(at: now)
    }

    /// 强制发布当前段残余（半截落盘前的收尾）：有
    /// 残余返回当前段新快照，否则 nil
    @discardableResult
    public mutating func flushCurrent(
        at now: TimeInterval
    ) -> String? {
        currentGate.flush(at: now)
    }

    /// 段边界（工具调用开始）：封存当前段——先
    /// flush 取精确全文，非空才入封存列，随后当前
    /// 闸归零，下一段增量从空缓冲起步、首增量恢复
    /// 立即发布。当前段为空时无段可封（并行工具连
    /// 发多次边界、工具先行轮次都走此支），返回
    /// nil 且不产空段。返回封存的段全文（未封成
    /// 时 nil）
    @discardableResult
    public mutating func sealCurrentSegment(
        at now: TimeInterval
    ) -> String? {
        _ = currentGate.flush(at: now)
        let text = currentGate.fullText
        guard !text.isEmpty else { return nil }
        sealedSegments.append(text)
        currentGate.reset()
        return text
    }

    /// 新一轮流开始时整器归零（封存列与当前闸同清）
    public mutating func reset() {
        self = StreamSegmentAssembler()
    }

    /// 恢复回填（半截落盘后重进本轮）：封存段与打
    /// 开段按落盘原序装回——打开段经一只新闸喂入
    /// （首喂立即发布，回填即刻见全段），其后续增
    /// 量只许拼进打开段、永不回流封存段
    public mutating func restore(
        sealed: [String], current: String,
        at now: TimeInterval
    ) {
        reset()
        sealedSegments = sealed.filter { !$0.isEmpty }
        if !current.isEmpty {
            _ = currentGate.offer(current, at: now)
        }
    }
}
