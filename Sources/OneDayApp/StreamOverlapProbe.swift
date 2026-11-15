#if DEBUG
import CoreGraphics
import Foundation

/// 第 91 条②仪表探针（gen4 流式叠字定因，DEBUG-only）：
/// 只记录、不干预——流式呈现逐拍的排版输出（TokenFlow
/// 的 fit/place 两相）、文本拍（StreamingText.onChange
/// 的分词与批量）、承载事件（ChatListCarrier 的托管
/// 换根/量实回填）汇到一处，供 StreamOverlapInstrument-
/// Tests 在真实装配里逐拍判读「已落定词元原点是否跨拍
/// 纵向位移」。Release 构建整文件编译为空，不进生产
/// 路径；生产文件中的挂钩全部包在 #if DEBUG 内。
enum StreamOverlapProbe {

    struct Arrangement {
        var beat: Int
        /// "fit"＝sizeThatFits 相；"place"＝placeSubviews 相
        var phase: String
        /// 本相实际消费的行宽（fit＝proposal 宽、place＝bounds 宽）
        var width: CGFloat
        var sizes: [CGSize]
        var origins: [CGPoint]
        var total: CGSize
    }

    struct TextBeat {
        var beat: Int
        var text: String
        var tokens: [String]
        var oldCount: Int
        var batch: Int
    }

    struct Visibility {
        var beat: Int
        var tokenCount: Int
        var visibleCount: Int
    }

    struct CarrierEvent {
        var beat: Int
        /// "hostCreate" | "rootSwap" | "measure"
        var kind: String
        var key: String
        var detail: String
    }

    private static let lock = NSLock()
    private(set) nonisolated(unsafe) static var currentBeat = 0
    private(set) nonisolated(unsafe) static var arrangements: [Arrangement] = []
    private(set) nonisolated(unsafe) static var textBeats: [TextBeat] = []
    private(set) nonisolated(unsafe) static var visibilities: [Visibility] = []
    private(set) nonisolated(unsafe) static var carrierEvents: [CarrierEvent] = []

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        currentBeat = 0
        arrangements = []
        textBeats = []
        visibilities = []
        carrierEvents = []
    }

    static func beginBeat(_ beat: Int) {
        lock.lock()
        defer { lock.unlock() }
        currentBeat = beat
    }

    static func recordArrangement(
        phase: String, width: CGFloat,
        sizes: [CGSize], origins: [CGPoint], total: CGSize
    ) {
        lock.lock()
        defer { lock.unlock() }
        arrangements.append(
            Arrangement(
                beat: currentBeat, phase: phase, width: width,
                sizes: sizes, origins: origins, total: total
            )
        )
    }

    static func recordTextBeat(
        text: String, tokens: [String], oldCount: Int, batch: Int
    ) {
        lock.lock()
        defer { lock.unlock() }
        textBeats.append(
            TextBeat(
                beat: currentBeat, text: text, tokens: tokens,
                oldCount: oldCount, batch: batch
            )
        )
    }

    static func recordVisibility(tokenCount: Int, visibleCount: Int) {
        lock.lock()
        defer { lock.unlock() }
        // body 求值频繁，只记变化点，避免日志淹没
        if let last = visibilities.last,
           last.beat == currentBeat,
           last.tokenCount == tokenCount,
           last.visibleCount == visibleCount {
            return
        }
        visibilities.append(
            Visibility(
                beat: currentBeat, tokenCount: tokenCount,
                visibleCount: visibleCount
            )
        )
    }

    static func recordCarrier(
        kind: String, key: String, detail: String
    ) {
        lock.lock()
        defer { lock.unlock() }
        carrierEvents.append(
            CarrierEvent(
                beat: currentBeat, kind: kind, key: key,
                detail: detail
            )
        )
    }
}
#endif
