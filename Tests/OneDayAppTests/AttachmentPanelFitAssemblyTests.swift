import Photos
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §326（小修批①，承 §303）真实装配断言：附件面
/// 板经生产呈现口径（attachmentPanelPresentat-
/// ion：系统 detent 档位 [.medium, .large]＋拖拽
/// 指示）在真窗口里真呈现——
/// ①面板在场：presented 控制器存在、其托管视图
/// sizeThatFits 与独立托管理想高逐值对账（空
/// sheet 测不出此高）；
/// ②定高归系统档位：presented 的 sheetPresen-
/// tationController detents 恰为 [.medium,
/// .large] 标识集、选中档为 .medium、帧高落半
/// 窗带（与内容理想高脱钩——§303 的精确贴合断
/// 言就此作废，脱钩本身即本批的验收点）；
/// ③增行不改高：同构 VStack（真实文本行、非固
/// 定高占位）经同一生产呈现口径，内容增行后
/// sheet 高逐值不变（放弃精确贴合的结构证据）；
/// 真面板本体走 ①②。
/// 沿革注：§303 时代本文件断言「高贴内容＋增行
/// 跟随」，桥（AttachmentSheetDetentBridge，
/// custom detent＋安全区反向补偿＋指纹重解）已
/// 随 §326 整套删除——桥类型不复存在即编译期
/// 证据，本文件不再按名查找。首轮（§303 run
/// 43763594395）实测 App 测试窗口内无障碍标签
/// 集为空集，在场断言因此不用 AX 标签面、改走
/// 托管视图 sizeThatFits 对账（标签集只打印留
/// 档），本批沿用。
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

    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + seconds
        ) { exp.fulfill() }
        wait(for: [exp], timeout: seconds + 5)
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

    // MARK: - ①② 真面板在场＋系统档位定高

    func testAttachPanelPresentsAtSystemMediumDetent() throws {
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
        // 高对账（呈现的若是空 sheet 或错内容，测
        // 不出此高）。无障碍标签集只留档不作断言
        // （首轮实测本环境 AX 树不填充、为空集）。
        // §326 口径差：桥退役后 presented 视图的底
        // 部安全区不再被反向补偿归零（.66 时代
        // safeBottom＝0、presentedIdeal＝ideal），
        // 其 sizeThatFits 含自身底部安全区一层——
        // 对账式改 ideal＋safeBottom（首轮实测差
        // 恰 34.0＝安全区全量，结构吻合）
        let presentedIdeal = presented.view.sizeThatFits(
            CGSize(
                width: windowW, height: .greatestFiniteMagnitude
            )
        ).height
        let safeBottom = presented.view.safeAreaInsets.bottom
        XCTAssertEqual(
            presentedIdeal, ideal + safeBottom, accuracy: 4,
            "presented 内容理想高 \(presentedIdeal) "
                + "≠ 面板理想高 \(ideal)＋底部安全区 "
                + "\(safeBottom)，面板不在场"
        )
        let labels = collectAccessibilityLabels(in: presented.view)

        let access = PHPhotoLibrary.authorizationStatus(
            for: .readWrite
        ).rawValue
        print(
            "ATTACH-FIT sheet=\(sheetHeight) ideal=\(ideal) "
                + "presentedIdeal=\(presentedIdeal) "
                + "safeBottom="
                + "\(presented.view.safeAreaInsets.bottom) "
                + "photoAccess=\(access) labels=\(labels)"
        )

        // 定高归系统档位（§326 本体）：detents 恰
        // 为 [.medium, .large] 系统标识集、无自造
        // custom detent 混入；开在 .medium
        let sheetPC = try XCTUnwrap(
            presented.sheetPresentationController,
            "presented 无 sheetPresentationController"
        )
        XCTAssertEqual(
            sheetPC.detents.map(\.identifier),
            [.medium, .large],
            "detents 须恰为系统 [.medium, .large]，"
                + "实得 \(sheetPC.detents.map(\.identifier))"
        )
        // 初始档：SwiftUI 管理下 selectedDetent-
        // Identifier 恒 nil（首轮实测），开档由
        // 「集合首元＝.medium＋帧高落 .medium 带」
        // 两面互证，不按 UIKit 编程式选档断言
        XCTAssertEqual(
            sheetPC.detents.first?.identifier, .medium,
            "detents 首元须为 .medium（SwiftUI 开档"
                + "认集合首元），实得 "
                + "\(String(describing: sheetPC.detents.first?.identifier))"
        )
        // 帧高落 .medium 半窗带：detent 解析值＝帧
        // 高−底部安全区（帧含安全区一层，§303 时
        // 代 sheet＝fit＋34 同式；首轮实测解析值
        // 435.67 对半窗 437）。与内容理想高脱钩是
        // 本批的既定代价、不是缺陷——§303 的「贴
        // 内容」断言在此作废
        XCTAssertEqual(
            sheetHeight - safeBottom, windowH * 0.5,
            accuracy: 30,
            "sheet detent 解析值 \(sheetHeight - safeBottom) "
                + "不在 .medium 半窗带（理想高 \(ideal) 仅留档）"
        )
        XCTAssertGreaterThan(
            sheetHeight, 100,
            "sheet 高 \(sheetHeight) 进塌陷带"
        )
    }

    // MARK: - ③ 内容增行不改高（系统档位口径）

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
            // §326：无桥——内容本体不挂任何定高装
            // 置，呈现口径（系统 detent）由 Sheet-
            // Host 的 attachmentPanelPresentation
            // 统一施加（与真面板同一修饰器）
        }
    }

    func testSheetHeightIgnoresContentGrowth() throws {
        let model = GrowthModel()
        let root = assemble(content: GrowthProbe(model: model))

        let collapsed = try XCTUnwrap(
            settledSheetHeight(of: root),
            "探针 sheet 未在时限内呈现落定"
        )
        model.expanded = true
        // 等内容重排落定（增行本身不再触发任何高
        // 度变更通路，落定读数应与增行前逐值同）
        spinRunLoop(seconds: 1.0)
        let expanded = try XCTUnwrap(
            settledSheetHeight(of: root),
            "增行后 sheet 未在时限内落定"
        )
        print(
            "ATTACH-FIT-GROWTH collapsed=\(collapsed) "
                + "expanded=\(expanded)"
        )
        XCTAssertEqual(
            expanded, collapsed, accuracy: 1,
            "系统 detent 档位下内容增行不得改高："
                + "\(collapsed)→\(expanded)"
        )
        // 半窗带同 ①口径：detent 解析值＝帧高−底
        // 部安全区（presented 在场取其安全区）
        let probeSafeBottom = root.presentedViewController?
            .view.safeAreaInsets.bottom ?? 0
        XCTAssertEqual(
            collapsed - probeSafeBottom, windowH * 0.5,
            accuracy: 30,
            "探针 sheet detent 解析值 "
                + "\(collapsed - probeSafeBottom) 不在 .medium 半窗带"
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
