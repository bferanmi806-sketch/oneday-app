import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 第 83 条命中域收口钉测（2026-11-15，全局标准审计
/// A 线 3-硬1–3-硬9）：九组漏网面按定版做法「视觉
/// 盘不变＋命中域外扩 44＋负内边距抵消布局」收口。
/// 两层判据：
/// ① 源码钉测（照 HapticsMatrixTests 式）：逐面断
///    言视觉帧原值还在、外扩链（minTapTarget 帧＋
///    Rectangle 命中形＋按视觉值算的负内边距抵消）
///    在位、旧小命中形（30 圆／36 胶囊）已撤。
/// ② 命中路由 rig（照 TopBarHitIntermittentTests
///    式）：生产同构的两种外扩构造（标签内链＝输
///    入舱式、钮外层链＝枢纽玻璃钮式）挂进真窗口，
///    在「盘外、命中域内、且已溢出布局槽」的点上
///    做 hitTest——命中不得落到下层陷阱（落下层＝
///    外扩只是写了帧、路由没通）；无外扩的对照钮
///    在同一点必须落陷阱，证明 rig 分辨得出来。
@MainActor
final class HitArea44Tests: XCTestCase {

    // MARK: - 源码钉测基建（HapticsMatrixTests 同式）

    private func sourcesRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: sources.path, isDirectory: &isDir
        ), isDir.boolValue else {
            throw XCTSkip("源码树在测试环境不可达，钉测跳过")
        }
        return sources
    }

    private func fileText(_ relative: String) throws -> String {
        let url = try sourcesRoot().appendingPathComponent(relative)
        guard let text = try? String(contentsOf: url, encoding: .utf8)
        else { throw XCTSkip("\(relative) 不可达，钉测跳过") }
        return text
    }

    /// 锚点间切片（锚点缺失＝钉测对象被改动，直接判红）
    private func segment(
        _ text: String, from start: String, to end: String,
        file: StaticString = #filePath, line: UInt = #line
    ) -> String {
        guard let s = text.range(of: start) else {
            XCTFail("起始锚点缺失：\(start)", file: file, line: line)
            return ""
        }
        guard let e = text.range(
            of: end, range: s.upperBound..<text.endIndex
        ) else {
            XCTFail("结束锚点缺失：\(end)", file: file, line: line)
            return ""
        }
        return String(text[s.lowerBound..<e.upperBound])
    }

    private func assertChain(
        _ seg: String, visual: String, compensation: String,
        _ name: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(
            seg.contains(visual),
            "\(name)：视觉帧原值应保留（\(visual)）",
            file: file, line: line
        )
        XCTAssertTrue(
            seg.contains("OneDayMetrics.minTapTarget"),
            "\(name)：外扩帧（minTapTarget）缺失",
            file: file, line: line
        )
        XCTAssertTrue(
            seg.contains(".contentShape(Rectangle())"),
            "\(name)：外层命中形（Rectangle）缺失",
            file: file, line: line
        )
        XCTAssertTrue(
            seg.contains(compensation),
            "\(name)：负内边距抵消缺失（\(compensation)）",
            file: file, line: line
        )
    }

    // MARK: - ① 逐面钉测

    /// 视觉基准钉死：根令牌与分段胶囊高不许借本包改动
    func testVisualBaselinesUntouched() throws {
        let layout = try fileText("OneDayCore/ComposerLayout.swift")
        XCTAssertTrue(
            layout.contains("buttonHeight: CGFloat = 30"),
            "输入舱视觉盘基准（buttonHeight 30）被改动"
        )
        let palette = try fileText("OneDayDesign/Palette.swift")
        XCTAssertTrue(
            palette.contains("hubSegCapsuleHeight: CGFloat = 36"),
            "枢纽分段胶囊视觉高（36）被改动"
        )
        XCTAssertTrue(
            palette.contains("minTapTarget: CGFloat = 44"),
            "命中域令牌（minTapTarget 44）被改动"
        )
    }

    /// 3-硬1 输入舱三钮（发送/停止变形键、麦克风、附件＋）
    func testComposerButtonsExpanded() throws {
        let chat = try fileText("OneDayApp/ChatView.swift")
        let compensation =
            "ComposerLayout.buttonHeight) / 2"
        let send = segment(
            chat, from: "private var sendStopButton",
            to: "停止生成\" : \"发送\")"
        )
        assertChain(
            send, visual: "Palette.primaryPale, in: Circle())",
            compensation: compensation, "发送/停止键"
        )
        let mic = segment(
            chat, from: "private var micButton",
            to: ".accessibilityLabel(\"语音输入\")"
        )
        assertChain(
            mic, visual: "ComposerLayout.buttonHeight",
            compensation: compensation, "麦克风键"
        )
        XCTAssertFalse(
            mic.contains(".contentShape(Circle())"),
            "麦克风键：旧 30 圆命中形应被外层矩形取代"
        )
        let attach = segment(
            chat, from: "private var attachButton",
            to: ".accessibilityLabel(\"添加附件\")"
        )
        assertChain(
            attach, visual: "ComposerLayout.buttonHeight",
            compensation: compensation, "附件＋键"
        )
        XCTAssertFalse(
            attach.contains(".contentShape(Circle())"),
            "附件＋键：旧 30 圆命中形应被外层矩形取代"
        )
    }

    /// 3-硬2 听写条三键
    func testDictationBarButtonsExpanded() throws {
        let text = try fileText("OneDayApp/DictationViews.swift")
        let compensation =
            "ComposerLayout.buttonHeight) / 2"
        XCTAssertEqual(
            text.components(separatedBy: compensation).count - 1, 3,
            "听写条三键应各有一处外扩抵消"
        )
        let parts: [(String, String, String)] = [
            ("private var discardButton", "private var stopButton", "丢弃键"),
            ("private var stopButton", "private var sendButton", "停止键"),
            ("private var sendButton", "private var centerCluster", "发送键"),
        ]
        for (start, end, name) in parts {
            let seg = segment(text, from: start, to: end)
            assertChain(
                seg, visual: "ComposerLayout.buttonHeight",
                compensation: compensation, "听写条\(name)"
            )
            XCTAssertFalse(
                seg.contains(".contentShape(Circle())"),
                "听写条\(name)：旧 30 圆命中形应被外层矩形取代"
            )
        }
    }

    /// 3-硬6 听写失败条关闭钮
    func testDictationFailureCloseExpanded() throws {
        let chat = try fileText("OneDayApp/ChatView.swift")
        let seg = segment(
            chat, from: "dictation.clearFailure()",
            to: ".accessibilityLabel(\"关闭提示\")"
        )
        assertChain(
            seg, visual: ".frame(width: 24, height: 24)",
            compensation: "OneDayMetrics.minTapTarget - 24) / 2",
            "听写失败条关闭钮"
        )
    }

    /// 3-硬3 文件页头两钮
    func testFilesHeaderButtonsExpanded() throws {
        let files = try fileText("OneDayApp/FilesView.swift")
        let compensation = "OneDayMetrics.minTapTarget - 32) / 2"
        let newFolder = segment(
            files, from: "\"folder.badge.plus\"",
            to: ".accessibilityLabel(\"新建文件夹\")"
        )
        assertChain(
            newFolder, visual: ".frame(width: 32, height: 32)",
            compensation: compensation, "新建文件夹钮"
        )
        let sort = segment(
            files, from: "sortAscending.toggle()",
            to: "当前升序，点按切换为降序"
        )
        assertChain(
            sort, visual: ".frame(width: 32, height: 32)",
            compensation: compensation, "排序切换钮"
        )
    }

    /// 3-硬4 枢纽页头玻璃钮（分享两支＋关闭；编辑笔钮
    /// 基线已有外扩、不在本包范围）
    func testHubHeaderGlassButtonsExpanded() throws {
        let hub = try fileText("OneDayApp/AgentHubView.swift")
        let compensation = "OneDayMetrics.minTapTarget - 36) / 2"
        let share = segment(
            hub, from: "private func shareButton",
            to: "private func header"
        )
        XCTAssertEqual(
            share.components(separatedBy: compensation).count - 1, 2,
            "分享钮两支（名片图/文本回落）应各有一处外扩抵消"
        )
        XCTAssertTrue(
            share.contains(".frame(width: 36, height: 36)"),
            "分享钮：玻璃盘视觉帧（36）应保留"
        )
        let close = segment(
            hub, from: "Image(systemName: \"xmark\")",
            to: ".accessibilityLabel(\"关闭\")"
        )
        assertChain(
            close, visual: ".frame(width: 36, height: 36)",
            compensation: compensation, "枢纽关闭钮"
        )
    }

    /// 3-硬5 枢纽分段条段钮（只扩高、视觉胶囊 36 不变）
    func testHubSegmentHitHeightExpanded() throws {
        let hub = try fileText("OneDayApp/AgentHubView.swift")
        let seg = segment(
            hub, from: "private var segmentPicker",
            to: "OneDayMetrics.hubSegBarHeight"
        )
        XCTAssertTrue(
            seg.contains(".frame(height: OneDayMetrics.minTapTarget)"),
            "分段条：段钮命中高外扩（minTapTarget）缺失"
        )
        XCTAssertTrue(
            seg.contains("OneDayMetrics.hubSegCapsuleHeight) / 2"),
            "分段条：纵向负内边距抵消缺失"
        )
        XCTAssertFalse(
            seg.contains(".contentShape(Capsule())"),
            "分段条：旧 36 胶囊命中形应被外层矩形取代"
        )
    }

    /// 3-硬7 动态帖「来源」钮
    func testFeedSourceButtonExpanded() throws {
        let feed = try fileText("OneDayApp/FeedView.swift")
        let seg = segment(
            feed, from: "sourcesPost = post",
            to: ".accessibilityLabel(\"来源\")"
        )
        assertChain(
            seg, visual: "\"info.circle\"",
            compensation: "OneDayMetrics.minTapTarget - 15) / 2",
            "动态帖来源钮"
        )
    }

    /// 3-硬8 浏览器/电脑状态刷新钮（两面同款）
    func testStatusRefreshButtonsExpanded() throws {
        for file in [
            "OneDayApp/BrowserView.swift",
            "OneDayApp/ComputerView.swift",
        ] {
            let text = try fileText(file)
            let seg = segment(
                text, from: "\"arrow.clockwise\"",
                to: ".accessibilityLabel(\"刷新状态\")"
            )
            assertChain(
                seg, visual: "\"arrow.clockwise\"",
                compensation: "OneDayMetrics.minTapTarget - 14) / 2",
                "\(file) 刷新钮"
            )
        }
    }

    /// 3-硬9 交付物文档行 ⋮ 菜单
    func testDeliverableDocMenuExpanded() throws {
        let text = try fileText("OneDayApp/DeliverablesView.swift")
        let seg = segment(
            text, from: ".frame(width: 40, height: 40)",
            to: ".accessibilityLabel(\"更多操作\")"
        )
        assertChain(
            seg, visual: ".frame(width: 40, height: 40)",
            compensation: "OneDayMetrics.minTapTarget - 40) / 2",
            "交付物文档行 ⋮ 菜单"
        )
    }

    // MARK: - ② 命中路由 rig

    /// 量具登记纪律（TopBar rig 先例）：注册只认
    /// didMoveToWindow——makeUIView 会被 SwiftUI 的量
    /// 测 pass 造出未挂窗替身，按它取位会量到原点
    private final class RegisteredView: UIView {
        var onWindow: (() -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { onWindow?() }
        }
    }

    /// 陷阱层登记盒（文件作用域，同 TopBar rig 的量具式）
    private final class TrapBox: @unchecked Sendable {
        var trap: UIView?
        var centers: [String: UIView] = [:]
    }

    private struct TrapView: UIViewRepresentable {
        let box: TrapBox
        func makeUIView(context: Context) -> RegisteredView {
            let view = RegisteredView()
            view.backgroundColor = .clear
            view.onWindow = { [weak view] in
                guard let view else { return }
                box.trap = view
            }
            return view
        }
        func updateUIView(_ view: RegisteredView, context: Context) {}
    }

    /// 视觉盘中心登记（挂在视觉帧的 background 上，
    /// 活量 convert 取中心，与生产帧同位）
    private struct CenterMarker: UIViewRepresentable {
        let name: String
        let box: TrapBox
        func makeUIView(context: Context) -> RegisteredView {
            let view = RegisteredView()
            view.isUserInteractionEnabled = false
            view.onWindow = { [weak view] in
                guard let view else { return }
                box.centers[name] = view
            }
            return view
        }
        func updateUIView(_ view: RegisteredView, context: Context) {}
    }

    /// rig 装配：陷阱垫底、三钮纵排居中——
    /// A＝标签内链复刻（输入舱式：30 盘＋44 帧＋矩形
    /// 命中形＋−7 抵消）；B＝钮外层链复刻（枢纽玻璃
    /// 钮式：36 玻璃盘、链挂钮外）；C＝对照（36 普通
    /// 钮、无外扩、无玻璃——玻璃钮的平台交互层自带
    /// 60×50 命中面、超 44，盘外点分不出外扩归因，
    /// 见 testRigExteriorChainRoutes 注）
    private struct RigView: View {
        let box: TrapBox
        var body: some View {
            ZStack {
                TrapView(box: box)
                VStack(spacing: 80) {
                    // A：标签内链（ChatView 输入舱三钮同构）
                    Button {} label: {
                        Circle()
                            .fill(Color.gray)
                            .frame(
                                width: ComposerLayout.buttonHeight,
                                height: ComposerLayout.buttonHeight
                            )
                            .background(
                                CenterMarker(name: "a", box: box)
                            )
                            .frame(
                                width: OneDayMetrics.minTapTarget,
                                height: OneDayMetrics.minTapTarget
                            )
                            .contentShape(Rectangle())
                            .padding(
                                -(OneDayMetrics.minTapTarget
                                    - ComposerLayout.buttonHeight) / 2
                            )
                    }
                    .buttonStyle(.odPressable)
                    // B：钮外层链（AgentHubView 页头玻璃钮同构）
                    Button {} label: {
                        Image(systemName: "xmark")
                            .frame(width: 36, height: 36)
                            .background(
                                CenterMarker(name: "b", box: box)
                            )
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .frame(
                        width: OneDayMetrics.minTapTarget,
                        height: OneDayMetrics.minTapTarget
                    )
                    .contentShape(Rectangle())
                    .padding(-(OneDayMetrics.minTapTarget - 36) / 2)
                    // C：对照（普通钮、无玻璃、无外扩）
                    Button {} label: {
                        Image(systemName: "xmark")
                            .frame(width: 36, height: 36)
                            .background(
                                CenterMarker(name: "c", box: box)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// 等待泵（ComposerGuideHostTests 同式）：SwiftUI
    /// 的挂载/布局链要靠主 runloop 泵过才落位，裸
    /// layoutIfNeeded 量到的是未挂窗帧
    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
    }

    private func makeRig() -> (UIWindow, TrapBox) {
        let box = TrapBox()
        let window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 390, height: 844)
        )
        let host = UIHostingController(rootView: RigView(box: box))
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        host.view.layoutIfNeeded()
        spinRunLoop(seconds: 0.6)
        window.layoutIfNeeded()
        host.view.layoutIfNeeded()
        return (window, box)
    }

    private func liveCenter(
        _ name: String, in window: UIWindow, box: TrapBox
    ) -> CGPoint? {
        guard let marker = box.centers[name],
              marker.window === window else { return nil }
        let frame = marker.convert(marker.bounds, to: window)
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    /// 命中裁决：命中不得落到陷阱（落陷阱＝该点没被
    /// 钮的命中域认领）；expectTrap 时反之
    private func assertRouting(
        _ name: String, dx: CGFloat, expectTrap: Bool, _ label: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let (window, box) = makeRig()
        guard let center = liveCenter(name, in: window, box: box),
              let trap = box.trap else {
            XCTFail("\(label)：量具未登记", file: file, line: line)
            return
        }
        let point = CGPoint(x: center.x + dx, y: center.y)
        let hit = window.hitTest(point, with: nil)
        if expectTrap {
            XCTAssertTrue(
                hit === trap,
                "\(label)：对照钮在盘外点应落陷阱（命中=\(String(describing: hit))）",
                file: file, line: line
            )
        } else {
            XCTAssertNotNil(hit, "\(label)：命中为空", file: file, line: line)
            XCTAssertFalse(
                hit === trap,
                "\(label)：命中落到下层陷阱——外扩未通路由（命中=\(String(describing: hit))）",
                file: file, line: line
            )
        }
    }

    /// A（标签内链）：盘心命中＋盘外 19pt（30 盘半径
    /// 15 之外、44 命中域半径 22 之内、且已溢出 30 布
    /// 局槽）必须由钮认领
    func testRigInLabelChainRoutes() {
        assertRouting("a", dx: 0, expectTrap: false, "A 盘心")
        assertRouting("a", dx: 19, expectTrap: false, "A 盘外命中域内")
    }

    /// B（钮外层链·玻璃钮）：盘心与盘外 20pt 均须通
    /// 路由（不落陷阱）。归因注记：.glass 钮的平台玻
    /// 璃交互层自带 60×50 命中面（首轮 rig 实测、超
    /// 44），盘外点即便没有外层链也会被平台层认领，
    /// 故 B 只判路由通断、不作外扩归因；外扩归因由
    /// 对照 C 承担——普通 36 钮无外扩时盘外 20pt 必
    /// 须落陷阱、有外扩的 A 同构点必须被认领，两相对
    /// 照证明「帧＋命中形＋负抵消」链本身通路由
    func testRigExteriorChainRoutes() {
        assertRouting("b", dx: 0, expectTrap: false, "B 盘心")
        assertRouting("b", dx: 20, expectTrap: false, "B 盘外命中域内")
        assertRouting("c", dx: 0, expectTrap: false, "C 盘心（对照）")
        assertRouting("c", dx: 20, expectTrap: true, "C 盘外（对照）")
    }
}
