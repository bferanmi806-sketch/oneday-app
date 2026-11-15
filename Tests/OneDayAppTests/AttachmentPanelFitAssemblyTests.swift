import Photos
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §299（A-08 定高收口）真实装配断言：附件面板经
/// 生产呈现口径（宿主 attachmentPanelPresenta-
/// tion 拖拽指示＋面板内 AttachmentSheetDetent-
/// Bridge 的 UIKit custom detent 定高）在真窗口
/// 里真呈现——
/// ①面板在场：presented 控制器存在、其托管视图
/// sizeThatFits 与独立托管理想高逐值对账（空
/// sheet 测不出此高）；
/// ②sheet 高贴内容：帧高与内容理想高对账（容差
/// 吸收安全区口径差），且显著小于 .medium 档
/// （不回默认档）、显著大于塌陷带（不重演 §154
/// 量测自噬）；
/// ③动态跟随：同桥同指纹口径下内容增行时 sheet
/// 高跟随变高——真面板的确认行由照片授权态＋条
/// 内选集驱动、装配环境不可达，故以同构 VStack
/// （真实文本行、非固定高占位）挂同一生产定高
/// 桥验增行跟随；真面板本体走 ①②。
/// 注：首轮（run 43763594395）曾以 .presenta-
/// tionSizing(.fitted) 为定高路实测 sheet=874
/// 全高、理想高 136.67 被无视——fitted 在
/// iPhone 底部 sheet 不改高，定高已改本桥；同
/// 轮实测 App 测试窗口内无障碍标签集为空集，
/// 在场断言因此不用 AX 标签面、改走托管视图
/// sizeThatFits 对账（标签集只打印留档）。
@MainActor
final class AttachmentPanelFitAssemblyTests: XCTestCase {

    private let windowW: CGFloat = 402
    private let windowH: CGFloat = 874

    private var window: UIWindow!

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    // MARK: - 真壳

    /// 呈现宿主：根层 onAppear 置位呈现，sheet 内
    /// 容统一经生产呈现口径（与 ChatView 呈现点同
    /// 一修饰器，不另抄配方）
    private struct SheetHost<Content: View>: View {
        @State private var presented = false
        let content: Content

        var body: some View {
            Color.clear
                .onAppear { presented = true }
                .sheet(isPresented: $presented) {
                    content.attachmentPanelPresentation()
                }
        }
    }

    private func assemble<Content: View>(
        content: Content
    ) -> UIViewController {
        // 呈现类断言须场景窗口（iOS 26 起 init
        // (frame:) 已弃用、且无场景窗口的 sheet 呈
        // 现口径不完整）：有场景挂场景并钉帧，无场
        // 景回落旧式帧窗
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
            window.frame = CGRect(
                x: 0, y: 0, width: windowW, height: windowH
            )
        } else {
            window = UIWindow(
                frame: CGRect(
                    x: 0, y: 0, width: windowW, height: windowH
                )
            )
        }
        let root = UIHostingController(
            rootView: SheetHost(content: content)
        )
        window.rootViewController = root
        window.makeKeyAndVisible()
        return root
    }

    /// 等呈现完成并落定：presented 出现且其视图帧
    /// 高连续三读不变（呈现动画走完）后返回帧高。
    /// afterChangeFrom 非 nil 时先等帧高离开该值
    /// （内容变更的动画起步前旧高会短暂稳定，不许
    /// 把旧高当落定值读走）
    private func settledSheetHeight(
        of root: UIViewController,
        timeout: TimeInterval = 10,
        afterChangeFrom reference: CGFloat? = nil
    ) -> CGFloat? {
        let deadline = Date().addingTimeInterval(timeout)
        var changed = reference == nil
        var last: CGFloat = -1
        var stableReads = 0
        while Date() < deadline {
            RunLoop.main.run(
                until: Date().addingTimeInterval(0.1)
            )
            guard let presented = root.presentedViewController
            else { continue }
            let height = presented.view.frame.height
            if !changed, let reference {
                if abs(height - reference) >= 0.5 {
                    changed = true
                } else {
                    continue
                }
            }
            if abs(height - last) < 0.5 {
                stableReads += 1
                if stableReads >= 3 { return height }
            } else {
                stableReads = 0
                last = height
            }
        }
        return nil
    }

    private func makePanel() -> AttachmentPanelView {
        AttachmentPanelView(
            onCamera: {},
            onConfirmPhotos: { _ in },
            onViewAll: {},
            onAddFile: {},
            onAddVideo: {}
        )
    }

    // MARK: - ①② 真面板在场＋高贴内容

    func testAttachPanelPresentsAtFittedContentHeight() throws {
        let root = assemble(content: makePanel())

        let sheetHeight = try XCTUnwrap(
            settledSheetHeight(of: root),
            "附件面板 sheet 未在时限内呈现落定"
        )
        let presented = try XCTUnwrap(root.presentedViewController)

        // 内容理想高（独立托管、同宽 sizeThatFits）
        let probe = UIHostingController(rootView: makePanel())
        let ideal = probe.sizeThatFits(
            in: CGSize(
                width: windowW, height: .greatestFiniteMagnitude
            )
        ).height

        // 在场：presented 本体即面板的托管控制器
        // ——其视图 sizeThatFits 须与独立托管理想
        // 高逐值对账（呈现的若是空 sheet 或错内容，
        // 测不出此高）。无障碍标签集只留档不作断
        // 言（首轮实测本环境 AX 树不填充、为空集）
        let presentedIdeal = presented.view.sizeThatFits(
            CGSize(
                width: windowW, height: .greatestFiniteMagnitude
            )
        ).height
        XCTAssertEqual(
            presentedIdeal, ideal, accuracy: 4,
            "presented 内容理想高 \(presentedIdeal) "
                + "≠ 面板理想高 \(ideal)，面板不在场"
        )
        let labels = collectAccessibilityLabels(in: presented.view)

        let access = PHPhotoLibrary.authorizationStatus(
            for: .readWrite
        ).rawValue
        print(
            "ATTACH-FIT sheet=\(sheetHeight) ideal=\(ideal) "
                + "presentedIdeal=\(presentedIdeal) "
                + "photoAccess=\(access) labels=\(labels)"
        )

        // 不塌陷（§154 失败形态：高塌到近零）
        XCTAssertGreaterThan(
            sheetHeight, 100,
            "sheet 高 \(sheetHeight) 进塌陷带"
        )
        // 不回默认档：显著小于 .medium（≈半窗高）
        XCTAssertLessThan(
            sheetHeight, windowH * 0.5,
            "sheet 高 \(sheetHeight) 回到 .medium 档量级"
        )
        // 贴内容：与理想高对账（容差吸收 sheet 安
        // 全区/呈现层口径差）
        XCTAssertEqual(
            sheetHeight, ideal, accuracy: 48,
            "sheet 高 \(sheetHeight) 与内容理想高 \(ideal) 脱钩"
        )
    }

    // MARK: - ③ 内容增行跟随

    private final class GrowthModel: ObservableObject {
        @Published var expanded = false
    }

    private struct GrowthProbe: View {
        @ObservedObject var model: GrowthModel

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("第一行").font(.body)
                if model.expanded {
                    Text("新增行")
                        .font(.body)
                        .frame(minHeight: 52)
                }
                Text("末行").font(.body)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 与真面板同构：定高桥挂内容本体、指
            // 纹＝增行有无（面板侧为资源库/确认行
            // 两位指纹，机制同一）
            .background(
                AttachmentSheetDetentBridge(
                    fingerprint: model.expanded ? 1 : 0
                )
            )
        }
    }

    func testFittedSheetGrowsWhenContentGrows() throws {
        let model = GrowthModel()
        let root = assemble(content: GrowthProbe(model: model))

        let collapsed = try XCTUnwrap(
            settledSheetHeight(of: root),
            "探针 sheet 未在时限内呈现落定"
        )
        model.expanded = true
        let expanded = try XCTUnwrap(
            settledSheetHeight(of: root, afterChangeFrom: collapsed),
            "增行后 sheet 未在时限内落定"
        )
        print(
            "ATTACH-FIT-GROWTH collapsed=\(collapsed) "
                + "expanded=\(expanded)"
        )
        XCTAssertGreaterThan(
            expanded - collapsed, 40,
            "内容增行（52＋间距）后 sheet 高未跟随："
                + "\(collapsed)→\(expanded)"
        )
    }

    // MARK: - 工具

    private func collectAccessibilityLabels(
        in view: UIView
    ) -> [String] {
        var out: [String] = []
        if let label = view.accessibilityLabel {
            out.append(label)
        }
        // SwiftUI 托管内容的无障碍元素多挂在元素的
        // accessibilityElements 而非子视图本体，两面
        // 都收（重复无妨、本函数只作 contains 判定）
        if let elements = view.accessibilityElements {
            for element in elements {
                if let elementView = element as? UIView {
                    out.append(
                        contentsOf: collectAccessibilityLabels(
                            in: elementView
                        )
                    )
                } else if let object = element as? NSObject,
                          let label = object.accessibilityLabel {
                    out.append(label)
                }
            }
        }
        for sub in view.subviews {
            out.append(contentsOf: collectAccessibilityLabels(in: sub))
        }
        return out
    }
}
