import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 第 91 条②仪表定因（gen4 流式叠字，0.50.50 真机复现）：
/// 真实装配（真实 ChatListCarrier＋真实 StreamingBlock-
/// Text/StreamingText 路＋生产同形气泡与布局参数）注入
/// 固定流式序列，逐拍捕获——TokenFlow 排版输出（fit/
/// place 两相，经 DEBUG 探针 StreamOverlapProbe）、文
/// 本拍分词、承载换根/量实回填事件、行帧与 content-
/// Offset、托管子树叶节点帧。判读口径：已落定词元（前
/// 拍已存在且已可见、文本未变）原点跨拍纵向位移
/// >0.5pt ＝签名复现。本套件是诊断仪表：断言只守装
/// 配与数据完整性，判读结论打 OVP| 前缀日志供报告引
/// 用（不在此判红绿，避免把未定因的现象写成假回归）。
@MainActor
final class StreamOverlapInstrumentTests: XCTestCase {
    nonisolated(unsafe) static var profileDebugPrinted = false

    // MARK: 装配

    private var window: UIWindow!
    private var root: UIViewController!
    private var controller: ChatListCarrierViewController!
    private var handle: ChatListCarrierHandle!

    private let streamKey = "stream-under-test"
    private let settledCount = 12
    private let settledHeight: CGFloat = 72

    // setUp/tearDown 内联装配（与 ChatListCarrierBottom-
    // GapTests 同形态：只做属性赋值与 UIKit 直调——从
    // 非隔离的生命周期方法调 @MainActor 实例方法会触
    // 发 Swift 6 sending-self 编译红，实测两轮）
    override func setUp() {
        super.setUp()
        StreamOverlapProbe.reset()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        controller = ChatListCarrierViewController()
        handle = ChatListCarrierHandle()
        controller.handle = handle
        controller.callbacks = ChatListCarrierCallbacks(
            onScrollGeometry: {},
            onTopVisibleEntry: { _ in },
            onBlankTap: {}
        )
        handle.controller = controller
        root.addChild(controller)
        root.view.addSubview(controller.view)
        controller.view.frame = root.view.bounds
        controller.didMove(toParent: root)
        root.view.layoutIfNeeded()
    }

    override func tearDown() {
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        root = nil
        controller = nil
        handle = nil
        super.tearDown()
    }

    /// 重装（固定行高回放的第二相用；测试方法本身在
    /// MainActor 上下文内，可直调隔离方法）
    private func installAssembly() {
        StreamOverlapProbe.reset()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        controller = ChatListCarrierViewController()
        handle = ChatListCarrierHandle()
        controller.handle = handle
        controller.callbacks = ChatListCarrierCallbacks(
            onScrollGeometry: {},
            onTopVisibleEntry: { _ in },
            onBlankTap: {}
        )
        handle.controller = controller
        root.addChild(controller)
        root.view.addSubview(controller.view)
        controller.view.frame = root.view.bounds
        controller.didMove(toParent: root)
        root.view.layoutIfNeeded()
    }

    private func uninstallAssembly() {
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        root = nil
        controller = nil
        handle = nil
    }

    // MARK: 行构造（生产同形）

    private var testLayout: ChatCarrierLayout {
        ChatCarrierLayout(
            horizontalPadding: OneDayMetrics.pageGutter,
            topPadding: OneDayMetrics.spacingM,
            bottomPadding: OneDayMetrics.spacingS,
            rowSpacing: OneDayMetrics.spacingL,
            arrowTrailing: OneDayMetrics.spacingM,
            arrowGapAboveComposer: 8,
            arrowSize: OneDayMetrics.minTapTarget
        )
    }

    /// 生产气泡同形（ChatView.assistantBubble 逐项同值）：
    /// HStack{ 内容＋内边距＋气泡底; Spacer(44) }
    private func bubbleView(
        text: String, killAnimations: Bool
    ) -> AnyView {
        let core = HStack(alignment: .top) {
            StreamingBlockText(text: text)
                .padding(.horizontal, OneDayMetrics.bubblePaddingH)
                .padding(.vertical, OneDayMetrics.bubblePaddingV)
                .background(
                    Palette.bubbleFill,
                    in: RoundedRectangle(
                        cornerRadius: OneDayMetrics.assistantBubbleCorner
                    )
                )
            Spacer(minLength: OneDayMetrics.bubbleSideInset)
        }
        if killAnimations {
            // 动画对照：事务级抑制本子树全部动画（等价
            // 于把 streamIn 动画置 nil 且更强），stagger
            // 延时显隐通道原样保留——两候选由此分开。
            // 注：\.accessibilityReduceMotion 环境覆盖在
            // iOS 26 SDK 下键路径为存在类型、无可用
            // .environment 重载（实测编译红），故不用
            return AnyView(
                core.transaction { $0.animation = nil }
            )
        }
        return AnyView(core)
    }

    /// 生产版本公式（ChatView.streamRowVersion，gen4 开）
    private func streamVersion(text: String) -> Int {
        text.count &* 31
            &+ StreamingBlockSegmenter.blocks(for: text).count
    }

    /// 生产暂定估算（carrierStreamRowEstimate 的产物未
    /// 齐回落支：字符粗估行数×callout 行高＋气泡纵边距）
    private func provisionalEstimate(text: String) -> CGFloat {
        let lineFloor = UIFont.preferredFont(
            forTextStyle: .callout
        ).lineHeight
        let chars = max(text.count, 1)
        let lines = min(40, max(1, Int(ceil(Double(chars) / 18.0))))
        return CGFloat(lines) * lineFloor
            + OneDayMetrics.bubblePaddingV * 2
    }

    private func makeRows(
        text: String, killAnimations: Bool,
        estimateOverride: CGFloat?
    ) -> [ChatCarrierRow] {
        var rows: [ChatCarrierRow] = (0..<settledCount).map { i in
            ChatCarrierRow(
                key: "settled-\(i)",
                entryID: UUID(),
                version: 1,
                estimatedHeight: settledHeight,
                makeView: {
                    AnyView(
                        Color.clear.frame(height: self.settledHeight)
                    )
                }
            )
        }
        rows.append(
            ChatCarrierRow(
                key: streamKey,
                entryID: nil,
                version: streamVersion(text: text),
                estimatedHeight: estimateOverride
                    ?? provisionalEstimate(text: text),
                makeView: {
                    self.bubbleView(
                        text: text, killAnimations: killAnimations
                    )
                }
            )
        )
        return rows
    }

    private func applyBeat(
        _ beat: Int, text: String, killAnimations: Bool = false,
        estimateOverride: CGFloat? = nil
    ) {
        StreamOverlapProbe.beginBeat(beat)
        controller.apply(
            rows: makeRows(
                text: text, killAnimations: killAnimations,
                estimateOverride: estimateOverride
            ),
            layout: testLayout,
            topInset: 122,
            composerTopInWindow: 874 - 137,
            fallbackBottomSpace: 137,
            bottomMargin: OneDayMetrics.spacingM,
            keyboardAnimationDuration: 0,
            keyboardAnimationCurveRaw: 0,
            arrowView: AnyView(Color.clear)
        )
    }

    private func drain(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    // MARK: 托管子树叶帧采样

    /// 流式行托管视图：contentView 子视图中帧 minY 最大者
    private func streamHostView() -> UIView? {
        guard let content = controller.scrollView.subviews.first
        else { return nil }
        return content.subviews.max {
            $0.frame.minY < $1.frame.minY
        }
    }

    private struct LeafFrame {
        var frame: CGRect
        var presFrame: CGRect?
        var cls: String
    }

    /// 叶节点帧（托管视图自身坐标系；pres＝presentation
    /// 层帧，与模型帧不一致即有动画在途）
    private func leafFrames(of host: UIView) -> [LeafFrame] {
        var leaves: [LeafFrame] = []
        func walk(_ view: UIView, depth: Int) {
            if depth > 14 { return }
            if view.subviews.isEmpty {
                let frame = view.convert(view.bounds, to: host)
                var pres: CGRect?
                if let p = view.layer.presentation() {
                    let pf = p.frame
                    if abs(pf.origin.x - view.frame.origin.x) > 0.5
                        || abs(pf.origin.y - view.frame.origin.y) > 0.5
                        || abs(pf.size.width - view.frame.size.width) > 0.5
                        || abs(pf.size.height - view.frame.size.height) > 0.5 {
                        pres = view.superview?
                            .convert(pf, to: host) ?? pf
                    }
                }
                leaves.append(
                    LeafFrame(
                        frame: frame, presFrame: pres,
                        cls: String(describing: type(of: view))
                    )
                )
                return
            }
            for sub in view.subviews { walk(sub, depth: depth + 1) }
        }
        walk(host, depth: 0)
        return leaves
    }

    private func fmt(_ v: CGFloat) -> String {
        String(format: "%.1f", Double(v))
    }

    private func dumpLeaves(
        tag: String, beat: Int, host: UIView
    ) {
        let leaves = leafFrames(of: host)
        print("OVP|LEAVES \(tag) beat=\(beat) count=\(leaves.count)")
        for (i, leaf) in leaves.enumerated() {
            var line = "OVP|LEAF \(tag) beat=\(beat) i=\(i) "
                + "f=\(fmt(leaf.frame.minX)),\(fmt(leaf.frame.minY)),"
                + "\(fmt(leaf.frame.width))x\(fmt(leaf.frame.height)) "
                + "cls=\(leaf.cls)"
            if let pres = leaf.presFrame {
                line += " pres=\(fmt(pres.minX)),\(fmt(pres.minY)),"
                    + "\(fmt(pres.width))x\(fmt(pres.height))"
            }
            print(line)
        }
    }

    // MARK: 逐拍判读

    private struct BeatFrame {
        var beat: Int
        var text: String
        /// 本拍 StreamingText 的尾块文本与词元（onChange 记录）
        var tailText: String
        var tokens: [String]
        /// 本拍末 place 相排版（最终落位口径）
        var placeOrigins: [CGPoint]
        var placeSizes: [CGSize]
        var placeCount: Int
        var fitCount: Int
        var visibleEnd: Int
        var hostFrame: CGRect
        var offsetY: CGFloat
        var contentHeight: CGFloat
    }

    private func snapshotBeat(_ beat: Int, fullText: String) -> BeatFrame {
        let beats = StreamOverlapProbe.textBeats.filter {
            $0.beat == beat
        }
        let lastBeat = beats.last
        let places = StreamOverlapProbe.arrangements.filter {
            $0.beat == beat && $0.phase == "place"
        }
        let fits = StreamOverlapProbe.arrangements.filter {
            $0.beat == beat && $0.phase == "fit"
        }
        let vis = StreamOverlapProbe.visibilities.filter {
            $0.beat == beat
        }
        let host = streamHostView()
        return BeatFrame(
            beat: beat,
            text: fullText,
            tailText: lastBeat?.text ?? "",
            tokens: lastBeat?.tokens ?? [],
            placeOrigins: places.last?.origins ?? [],
            placeSizes: places.last?.sizes ?? [],
            placeCount: places.count,
            fitCount: fits.count,
            visibleEnd: vis.last?.visibleCount ?? 0,
            hostFrame: host?.frame ?? .zero,
            offsetY: controller.scrollView.contentOffset.y,
            contentHeight: controller.scrollView.contentSize.height
        )
    }

    /// 跨拍判读：已落定词元（前拍存在＋已可见＋文本同）
    /// 原点纵向位移统计；尾块重置（闭合换层）单独标记
    private func compareBeats(
        _ prev: BeatFrame, _ cur: BeatFrame, tag: String
    ) {
        let prefixOK = cur.tailText.hasPrefix(prev.tailText)
            && !prev.tailText.isEmpty
        guard prefixOK else {
            print(
                "OVP|CMP \(tag) beat=\(cur.beat) tailReset "
                    + "prevTail=\(prev.tailText.count)字 "
                    + "curTail=\(cur.tailText.count)字"
            )
            return
        }
        let common = min(
            prev.tokens.count, cur.tokens.count,
            prev.placeOrigins.count, cur.placeOrigins.count
        )
        var settled = 0
        var moved: [(Int, CGFloat, CGFloat)] = []
        var maxDy: CGFloat = 0
        for i in 0..<common {
            guard prev.tokens[i] == cur.tokens[i] else { continue }
            guard i < prev.visibleEnd else { continue }
            settled += 1
            let dy = cur.placeOrigins[i].y - prev.placeOrigins[i].y
            let dx = cur.placeOrigins[i].x - prev.placeOrigins[i].x
            if abs(dy) > 0.5 {
                moved.append((i, dx, dy))
                maxDy = max(maxDy, abs(dy))
            }
        }
        var line = "OVP|CMP \(tag) beat=\(cur.beat) settled=\(settled) "
            + "movedY=\(moved.count) maxDy=\(fmt(maxDy))"
        for (i, dx, dy) in moved.prefix(24) {
            line += " [\(i):dx\(fmt(dx)),dy\(fmt(dy))]"
        }
        print(line)
        // 本拍内多相收敛：place 相里已落定词元的原点种数
        let places = StreamOverlapProbe.arrangements.filter {
            $0.beat == cur.beat && $0.phase == "place"
        }
        var maxVariants = 0
        var variantIdx = -1
        for i in 0..<common {
            guard prev.tokens[i] == cur.tokens[i] else { continue }
            var seen = Set<String>()
            for p in places where i < p.origins.count {
                seen.insert(
                    "\(fmt(p.origins[i].x)),\(fmt(p.origins[i].y))"
                )
            }
            if seen.count > maxVariants {
                maxVariants = seen.count
                variantIdx = i
            }
        }
        print(
            "OVP|CONV \(tag) beat=\(cur.beat) placePasses=\(places.count) "
                + "maxOriginVariants=\(maxVariants) atIdx=\(variantIdx)"
        )
    }

    private func dumpBeat(_ frame: BeatFrame, tag: String) {
        print(
            "OVP|BEAT \(tag) beat=\(frame.beat) full=\(frame.text.count)字 "
                + "tail=\(frame.tailText.count)字 tokens=\(frame.tokens.count) "
                + "place=\(frame.placeCount) fit=\(frame.fitCount) "
                + "visibleEnd=\(frame.visibleEnd) "
                + "hostH=\(fmt(frame.hostFrame.height)) "
                + "offsetY=\(fmt(frame.offsetY)) "
                + "contentH=\(fmt(frame.contentHeight))"
        )
        let events = StreamOverlapProbe.carrierEvents.filter {
            $0.beat == frame.beat
        }
        for e in events {
            print(
                "OVP|CARR \(tag) beat=\(frame.beat) \(e.kind) "
                    + "key=\(e.key) \(e.detail)"
            )
        }
    }

    // MARK: 序列驱动

    /// 把全文字节拍喂入：每拍 apply→中段采样（+45ms 叶
    /// 帧）→落定（0.5s）→拍末快照＋跨拍判读
    private func runSequence(
        tag: String, chunks: [String], killAnimations: Bool = false,
        estimates: [CGFloat]? = nil, sampleLeaves: Bool = true
    ) -> [BeatFrame] {
        var frames: [BeatFrame] = []
        var text = ""
        for (index, chunk) in chunks.enumerated() {
            let beat = index + 1
            text += chunk
            applyBeat(
                beat, text: text, killAnimations: killAnimations,
                estimateOverride: estimates?[index]
            )
            drain(0.045)
            if sampleLeaves, let host = streamHostView() {
                dumpLeaves(
                    tag: tag + "-mid", beat: beat, host: host
                )
            }
            drain(0.5)
            if sampleLeaves, let host = streamHostView() {
                dumpLeaves(
                    tag: tag + "-end", beat: beat, host: host
                )
            }
            let frame = snapshotBeat(beat, fullText: text)
            dumpBeat(frame, tag: tag)
            if let prev = frames.last {
                compareBeats(prev, frame, tag: tag)
            }
            frames.append(frame)
        }
        return frames
    }

    // MARK: 序列文本

    /// 纯追加（单段、无块闭合）：CJK＋拉丁增长、多处
    /// 换行边界（全长约 150 字、11 拍）
    private var appendOnlyChunks: [String] {
        [
            "这次更新把消息列表",
            "换成了新的承载方式，",
            "流式回复按块出现，",
            "已经落定的段落保持",
            "静止，不再重排。",
            "streaming pipeline ",
            "的 token origin ",
            "必须稳定，wrap ",
            "boundary 处的字符",
            "最容易出问题，需要",
            "逐帧核对才算数。",
        ]
    }

    /// 块闭合：第一段约 90 字后空行，第二段成新尾块继
    /// 续增长（全长约 200 字、13 拍；闭合拍＝第 9 拍）
    private var closureChunks: [String] {
        [
            "先说结论：这次的改动",
            "只动呈现层，不动数据。",
            "流式文本先按块切分，",
            "闭合块走静态渲染，",
            "只有尾块逐词渐显。",
            "这样落定前后同构，",
            "不会整树换装。",
            "以上是第一段。",
            "\n\n第二段从这里开始，",
            "它成为新的尾块，",
            "继续逐批增长，",
            "直到整段结束。",
            "收尾这一句用来确认闭合后仍然稳定。",
        ]
    }

    // MARK: 用例

    func testInstrumentAppendOnly() {
        let frames = runSequence(
            tag: "APPEND", chunks: appendOnlyChunks
        )
        XCTAssertEqual(frames.count, appendOnlyChunks.count)
        XCTAssertFalse(
            frames.last?.tokens.isEmpty ?? true,
            "装配应产出词元排版数据"
        )
    }

    func testInstrumentBlockClosure() {
        let frames = runSequence(
            tag: "CLOSE", chunks: closureChunks
        )
        XCTAssertEqual(frames.count, closureChunks.count)
        XCTAssertFalse(
            frames.last?.tokens.isEmpty ?? true,
            "装配应产出词元排版数据"
        )
    }

    /// 对照：动画全关（事务级抑制，stagger 保留）——
    /// 同闭合序列，判读动画是否为位移的必要条件
    func testInstrumentBlockClosureNoAnim() {
        let frames = runSequence(
            tag: "CLOSE-NA", chunks: closureChunks,
            killAnimations: true
        )
        XCTAssertEqual(frames.count, closureChunks.count)
    }

    /// 对照：固定行高回放——先以暂定估算跑一遍闭合序
    /// 列、逐拍记流式行量实高；重装后同序列以量实高作
    /// 估算回放（估算＝量实，承载无回填收敛），判读高
    /// 度收敛是否为原点位移的必要条件
    func testInstrumentFixedHeightReplay() {
        let first = runSequence(
            tag: "CLOSE-FH1", chunks: closureChunks,
            sampleLeaves: false
        )
        let heights = first.map { $0.hostFrame.height }
        print("OVP|FH heights=\(heights.map { fmt($0) }.joined(separator: ","))")
        uninstallAssembly()
        installAssembly()
        let second = runSequence(
            tag: "CLOSE-FH2", chunks: closureChunks,
            estimates: heights, sampleLeaves: false
        )
        XCTAssertEqual(second.count, first.count)
    }

    // MARK: 第二轮：快拍＋像素行剖面＋可见性孔洞

    /// 渲染托管视图为灰度行剖面：逐行统计暗像素数，
    /// 归并为文本行带（中心 y 列表）。display-list 渲
    /// 染没有逐词元平台视图可读，像素剖面是呈现层唯
    /// 一可观测口——同一文本行在剖面里出现双带/离格
    /// 带即叠印的帧级签名
    private func lineProfile(of host: UIView) -> [CGFloat] {
        let bounds = host.bounds
        guard bounds.width > 10, bounds.height > 10 else {
            return []
        }
        host.setNeedsDisplay()
        host.layoutIfNeeded()
        CATransaction.flush()
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        let image = renderer.image { _ in
            host.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        guard let cg = image.cgImage else { return [] }
        let width = cg.width
        let height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        let space = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: space,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return [] }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        let scale = image.scale
        if !Self.profileDebugPrinted {
            Self.profileDebugPrinted = true
            var totalDark = 0
            for value in pixels where value < 110 { totalDark += 1 }
            print(
                "OVP|PXDBG imagePx=\(width)x\(height) scale=\(scale) "
                    + "darkTotal=\(totalDark)"
            )
        }
        var centers: [CGFloat] = []
        var runStart: Int?
        for row in 0..<height {
            var dark = 0
            let base = row * width
            for col in 0..<width where pixels[base + col] < 110 {
                dark += 1
            }
            let isText = dark >= 4
            if isText, runStart == nil {
                runStart = row
            } else if !isText, let start = runStart {
                if row - start >= 3 {
                    centers.append(
                        CGFloat(start + row - 1) / 2 / scale
                    )
                }
                runStart = nil
            }
        }
        return centers
    }

    private func dumpProfile(
        tag: String, beat: Int, sampleMs: Int, host: UIView
    ) {
        let centers = lineProfile(of: host)
        print(
            "OVP|PX \(tag) beat=\(beat) t=\(sampleMs)ms lines=\(centers.count) "
                + "centers=\(centers.map { fmt($0) }.joined(separator: ","))"
        )
    }

    /// 快拍（120ms/拍，贴近真机批间隔）：每拍 apply
    /// 后 0/33/66/99ms 渲染采样行剖面，拍末不排空、
    /// 直接下一拍；全程结束后排空再采落定剖面
    func testInstrumentFastBeatsPixelProbe() {
        var text = ""
        for (index, chunk) in closureChunks.enumerated() {
            let beat = index + 1
            text += chunk
            applyBeat(beat, text: text)
            for ms in [0, 33, 66, 99] {
                if ms > 0 { drain(0.033) }
                if let host = streamHostView() {
                    dumpProfile(
                        tag: "FAST", beat: beat,
                        sampleMs: ms, host: host
                    )
                }
            }
            drain(0.02)
            let frame = snapshotBeat(beat, fullText: text)
            dumpBeat(frame, tag: "FAST")
        }
        drain(0.8)
        if let host = streamHostView() {
            dumpProfile(
                tag: "FAST", beat: closureChunks.count,
                sampleMs: 999, host: host
            )
        }
        let last = snapshotBeat(
            closureChunks.count, fullText: text
        )
        print(
            "OVP|FASTEND tokens=\(last.tokens.count) "
                + "visibleEnd=\(last.visibleEnd)"
        )
    }

    /// 候选②逆情形：首段 16 词元、stagger 未跑完时第
    /// 二段（11 词元）到达——batch<0 早退、新尾块不排
    /// 自己的 stagger；其词元靠首段遗留的延时任务按旧
    /// 下标逐个点亮（张冠李戴的入场调度）。可见性时间
    /// 线里出现「tokenCount 已是新尾块、visibleCount
    /// 长期小于它」即瞬时孔洞实证
    func testInstrumentTailResetVisibilityHoles() {
        // 首段 16 个词元（CJK 逐字成元）
        let para1 = "这是一个比较长的开头段落用来占位"
        // 第二段 11 个词元
        let para2 = "第二段只有这么长而已啦"
        var text = para1
        StreamOverlapProbe.beginBeat(1)
        applyBeat(1, text: text)
        drain(0.08) // stagger（16 元、压缩步进）远未跑完
        text += "\n\n" + para2
        applyBeat(2, text: text)
        drain(0.08)
        // 后续小批增长：insert 只覆盖 oldCount 起的下标
        for (i, extra) in ["继续", "往后", "生长"].enumerated() {
            text += extra
            applyBeat(3 + i, text: text)
            drain(0.3)
        }
        drain(0.8)
        let beats = StreamOverlapProbe.textBeats
        let vis = StreamOverlapProbe.visibilities
        print(
            "OVP|HOLE textBeats=\(beats.map { "\($0.beat):tok\($0.tokens.count),old\($0.oldCount),batch\($0.batch)" }.joined(separator: " "))"
        )
        print(
            "OVP|HOLE visTimeline=\(vis.map { "\($0.beat):tc\($0.tokenCount)/vc\($0.visibleCount)" }.joined(separator: " "))"
        )
        print(
            "OVP|HOLE finalTokens=\(beats.last?.tokens.count ?? -1) "
                + "finalVisible=\(vis.last?.visibleCount ?? -1)"
        )
        XCTAssertFalse(beats.isEmpty)
    }
}

