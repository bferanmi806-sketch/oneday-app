import Photos
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §299（A-08 定高收口）真实装配断言：附件面板经
/// 生产呈现口径（attachmentPanelPresentation＝系
/// 统 fitted 尺寸＋拖拽指示）在真窗口里真呈现——
/// ①面板在场：presented 控制器存在、面板内容在
/// 其视图树内；
/// ②sheet 高贴内容：与独立托管 sizeThatFits 的内
/// 容理想高对账（容差吸收安全区口径差），且显著
/// 小于 .medium 档（不回落默认档）、显著大于塌
/// 陷带（不重演 §154 量测自噬）；
/// ③动态跟随：同口径下内容增行时 sheet 高跟随
/// 变高——真面板的确认行由照片授权态＋条内选集
/// 驱动、装配环境不可达，故以同构 VStack（真实
/// 文本行、非固定高占位）经同一生产修饰器验增
/// 行跟随；真面板本体走 ①②。
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
        window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: windowW, height: windowH)
        )
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

        // 在场：presented 视图树内有面板内容（动
        // 作行无障碍标签可达）
        let labels = collectAccessibilityLabels(in: presented.view)
        XCTAssertTrue(
            labels.contains("添加文件"),
            "面板动作行不在场，标签集：\(labels)"
        )
        XCTAssertTrue(labels.contains("添加视频"))

        // 内容理想高（独立托管、同宽 sizeThatFits）
        let probe = UIHostingController(rootView: makePanel())
        let ideal = probe.sizeThatFits(
            in: CGSize(
                width: windowW, height: .greatestFiniteMagnitude
            )
        ).height

        let access = PHPhotoLibrary.authorizationStatus(
            for: .readWrite
        ).rawValue
        print(
            "ATTACH-FIT sheet=\(sheetHeight) ideal=\(ideal) "
                + "photoAccess=\(access)"
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
