import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §318 盲区堵漏（诊断 drawer-broken-diagnosis-
/// 20261117.md §2「为何 CI 没拦住」）：.64 的抽屉
/// 命名测试一律用桩内容根（EmptyView 系），只断言
/// transform 与显示原点——真 DrawerView 的安全区
/// 消费（标题浮层靠安全区顶定位、底条 .safeAreaBar
/// 靠安全区底落位）从未被任何断言覆盖，A-21 清零
/// 误伤因此全程绿灯。本套件以**真 DrawerView**（经
/// 容器 drawerBuilder 注入、与生产桥 apply() 同款
/// 环境）装配进真 DrawerContainerController＋设备
/// 窗（402×874、安全区覆写顶 59／底 34，与诊断真
/// 机同口径），断言渲染几何：
/// - 名单 ScrollView 的 adjustedContentInset.top
///   ＝115——量测口径经两轮实测定案：名单平台视
///   图帧全幅（帧顶 0）、SwiftUI 自排的标题带空
///   程 56 落 contentInset、宿主安全区派生经平台
///   调整层到达（adjusted＝56＋59＝115）；宿主清
///   零时调整层归零、adjusted 回 56。空程沿革：
///   初定 72（adjusted 131）→2026-11-21 抽屉样板
///   对齐包随身份行顶距改 56。身份行是覆盖
///   VStack 的首行、与名单同受根 ZStack 的同一
///   份宿主派生（行自排顶距 spacingS 8 出本体常
///   量 ⟹ 身份行顶 59＋8＝67），故本值达标 ⟺ 派
///   生到达 DrawerView 本体。
/// - 底条搜索字段中心 y＝810：底条内容底缘停在安
///   全区线之上 4pt（距屏底 34＋4＝38，诊断 §8 口
///   径），胶囊高 52 居中于条内 → 中心距屏底 64；
///   清零态整条下沉 34、中心移至 844，必红。
/// - 面板不透明量测：真 DrawerView 单独装宿主、背
///   后垫纯红，开态渲染采样面板空区像素——实色面
///   只可能落 chatSurface 双档（#FCFCFC 或纯黑，
///   通道差 ≤6）；thinMaterial 透红时呈粉灰、通道
///   差数十，必红（§318 材质定案的量测留证）。
@MainActor
final class DrawerSafeAreaRealRootTests: XCTestCase {

    /// 与诊断真机同口径的设备窗（402×874、安全区
    /// 覆写 top 59／bottom 34；R4 装配套件同款）
    private final class DeviceWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        }
    }

    private var window: DeviceWindow!
    private var appState: AppState!
    private var container: ModelContainer!
    /// §184：容器租约——见 SwiftDataTestMount
    private var swiftDataMount = SwiftDataTestMount()

    override func setUp() async throws {
        try await super.setUp()
        appState = AppState()
        let schema = Schema([ChatThread.self, ChatEntry.self])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
        swiftDataMount.retain(container)
        window = DeviceWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
    }

    override func tearDown() async throws {
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        await swiftDataMount.release()
        container = nil
        appState = nil
        try await super.tearDown()
    }

    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
    }

    /// 与生产桥 apply() 同款装配：真 DrawerView 经
    /// drawerBuilder 注入（环境逐项同桥）、内容侧替
    /// 身（桥级先例 DrawerBridgeHarness 同形态）
    private func assembleDrawerController() -> DrawerContainerController {
        let controller = DrawerContainerController()
        let appState = appState!
        let modelContext = container.mainContext
        controller.drawerBuilder = { width in
            AnyView(
                DrawerView(
                    width: width,
                    currentTab: .chat,
                    onSelectTab: { _ in },
                    onClose: {},
                    onOpenChannel: { _ in }
                )
                .environment(appState)
                .environment(\.modelContext, modelContext)
                .environment(\.locale, Locale(identifier: "zh-Hans"))
                .boldTextMapping()
            )
        }
        controller.contentRoot = AnyView(Text("content替身"))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        return controller
    }

    private func findAll<T: UIView>(
        _ type: T.Type, in view: UIView
    ) -> [T] {
        var found: [T] = []
        if let hit = view as? T { found.append(hit) }
        for sub in view.subviews {
            found.append(contentsOf: findAll(type, in: sub))
        }
        return found
    }

    /// 真 DrawerView 装配下：名单顶＝安全区顶、底条
    /// 搜索字段中心落位达标（§318 F1 回归钉）
    func testRealDrawerViewConsumesHostSafeArea() throws {
        let controller = assembleDrawerController()
        controller.setDrawer(true, animated: false)
        controller.view.layoutIfNeeded()
        spinRunLoop(seconds: 0.6)

        let drawerHostView = try XCTUnwrap(
            controller.view.subviews.first,
            "容器首子视图应为抽屉宿主"
        )
        XCTAssertFalse(drawerHostView.isHidden, "开态抽屉宿主应可见")

        // 名单安全区消费：宿主派生经平台调整层到达
        // （见文件头注）——adjusted＝56（标题带空
        // 程）＋59（宿主安全区顶）＝115；空程沿革：
        // §157 的 72 于 2026-11-21 抽屉样板对齐包随
        // 身份行顶距 24→8 改 56（titleStripHeight
        // 算式见 DrawerView 该令牌注）
        let scrollViews = findAll(UIScrollView.self, in: drawerHostView)
        let list = try XCTUnwrap(
            scrollViews.max(by: {
                $0.frame.height < $1.frame.height
            }),
            "真 DrawerView 内未找到名单 ScrollView"
        )
        XCTAssertEqual(
            list.adjustedContentInset.top, 115, accuracy: 2,
            "名单 adjustedContentInset.top 应为 115（标题带空程 56＋宿主安全区 59）；"
                + "实测 adjusted=\(list.adjustedContentInset.top)、"
                + "contentInset.top=\(list.contentInset.top)、"
                + "帧顶=\(list.convert(list.bounds, to: window).minY)"
                + "——宿主安全区派生若被清零 adjusted 回 56"
        )

        // 底条落位：搜索字段（底条三件中的平台视图）
        // 中心距屏底应 64（安全区 34＋条内底距 4＋行
        // 盒半高 26——2026-11-21 样板对齐包后控件 45
        // 居中于 52 行盒、字段中心与行盒中心同线，
        // 落位与改前同值；样板实测中心距屏底 64.2）
        let fields = findAll(UITextField.self, in: drawerHostView)
        let searchField = try XCTUnwrap(
            fields.first, "底条内未找到搜索 TextField"
        )
        let fieldFrameInWindow = searchField.convert(
            searchField.bounds, to: window
        )
        XCTAssertEqual(
            fieldFrameInWindow.midY, 874 - 64, accuracy: 3,
            "底条搜索字段中心应距屏底 64（落位 38＋半高 26）；"
                + "实测中心 \(fieldFrameInWindow.midY)——清零态整条下沉 34 至 844"
        )
    }

    /// §318 材质定案量测：面板实色零透出（背后纯红
    /// 不得混入面板空区采样）
    func testDrawerPanelIsOpaqueSolidOverSaturatedBackdrop() throws {
        let host = UIHostingController(
            rootView: ZStack(alignment: .leading) {
                Color.red
                DrawerView(
                    width: 301.5,
                    currentTab: .chat,
                    onSelectTab: { _ in },
                    onClose: {},
                    onOpenChannel: { _ in }
                )
                .environment(appState)
                .environment(\.modelContext, container.mainContext)
                .environment(\.locale, Locale(identifier: "zh-Hans"))
                .boldTextMapping()
            }
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        spinRunLoop(seconds: 0.6)

        // 采样点：面板右下空区（空库名单无行、底条之
        // 上），x 290 在面板内（宽 301.5）、离右缘留
        // 量避开滚动指示器带
        let pixel = try XCTUnwrap(
            samplePixel(in: window, at: CGPoint(x: 290, y: 700)),
            "窗口渲染采样失败"
        )
        let spread = max(pixel.r, pixel.g, pixel.b)
            - min(pixel.r, pixel.g, pixel.b)
        let isLightSolid = abs(pixel.r - 252) <= 10
            && abs(pixel.g - 252) <= 10 && abs(pixel.b - 252) <= 10
        let isDarkSolid = pixel.r <= 10 && pixel.g <= 10 && pixel.b <= 10
        XCTAssertTrue(
            (isLightSolid || isDarkSolid) && spread <= 6,
            "面板空区采样应为 chatSurface 实色（浅 252 或深 0、通道差 ≤6）；"
                + "实测 RGB=(\(pixel.r),\(pixel.g),\(pixel.b))——"
                + "若呈粉灰（R 独大）即材质透出了背后纯红"
        )
    }

    /// 窗口渲染单点采样（窗口点 → 图像像素按 scale
    /// 换算；行序按 CGImage 绘制惯例自顶向下）
    private func samplePixel(
        in window: UIWindow, at point: CGPoint
    ) -> (r: Int, g: Int, b: Int)? {
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            window.drawHierarchy(
                in: window.bounds, afterScreenUpdates: true
            )
        }
        guard let cg = image.cgImage else { return nil }
        let width = cg.width
        let height = cg.height
        var raw = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(
            data: &raw, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        let px = Int(point.x * image.scale)
        let py = Int(point.y * image.scale)
        guard px >= 0, px < width, py >= 0, py < height else {
            return nil
        }
        let offset = (py * width + px) * 4
        return (
            r: Int(raw[offset]), g: Int(raw[offset + 1]),
            b: Int(raw[offset + 2])
        )
    }
}
