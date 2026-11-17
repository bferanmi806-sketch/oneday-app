import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §320（文件牌版本折算修复）真实时序装配断言：
/// 诊断 file-attach-invisible-diagnosis-20261117
/// §B5 的断点是时序形的——条目先以无附件形态物
/// 化（发送瞬间：正文已落盘、remoteFilePaths 恒
/// 空），上传回填随后才写 remoteFilePathsData。
/// 本例按此时序造例，不测静态有附件的行（静态
/// 行首帧即带附件、走的是另一条物化路，测不出
/// 断点）：
/// ①种子用户条目（正文＋无附件）整页装配——该
/// 行须物化为原生散文 cell（回填前的真实形态）；
/// ②按生产回填原样落盘（ChatView 发送链 §121：
/// remoteFilePathsData＝JSONEncoder().encode(
/// [String])＋save）——同一行须被重配为托管行：
/// cell 换装（非散文 cell）、视图树文本含文件
/// 名（FileChip 已挂）、行高较散文形态增长
/// ≥40（牌组估算补入＋量实同向）。
/// 机制注：承载 rowsEqual 闸以（键，版本，估
/// 算）判变——版本不翻则整行不重配、散文 cell
/// 恒在。故②的换装成立本身即「回填后版本必
/// 变」的装配级证据；版本折算本体见 ChatView
/// .carrierEntryVersion 的 §320 注。
@MainActor
final class FileChipVersionFixAssemblyTests: XCTestCase {

    /// 与整页组装回归同口径的设备窗：402×874、
    /// 安全区覆写 top 59／bottom 34（真机同值）
    private final class DeviceWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        }
    }

    private var window: DeviceWindow!
    /// §184：容器租约——挂载树的容器进进程级持有、
    /// 永不释放，见 SwiftDataTestMount
    private var swiftDataMount = SwiftDataTestMount()
    private var container: ModelContainer!
    private var entryID: UUID!
    private var nativeListFlagPrior: Any?

    /// 与诊断实证同名（用户 2026-11-17 13:12 真机
    /// 所发账单文件）
    private let filePath =
        "/opt/data/attachments/iCost_20261018200435.xlsx"
    private let fileName = "iCost_20261018200435.xlsx"

    override func setUp() async throws {
        nativeListFlagPrior = UserDefaults.standard.object(
            forKey: ChatNativeListFeature.defaultsKey
        )
        // 对象面是新面：旗键缺省＝开（R4 转默认口
        // 径），摘键即回缺省、不写显式值
        UserDefaults.standard.removeObject(
            forKey: ChatNativeListFeature.defaultsKey
        )
        try await super.setUp()
    }

    override func tearDown() async throws {
        if let prior = nativeListFlagPrior {
            UserDefaults.standard.set(
                prior, forKey: ChatNativeListFeature.defaultsKey
            )
        } else {
            UserDefaults.standard.removeObject(
                forKey: ChatNativeListFeature.defaultsKey
            )
        }
        nativeListFlagPrior = nil
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        container = nil
        await swiftDataMount.release()
        try await super.tearDown()
    }

    // MARK: - 装配

    private func assembleSeededPage() throws {
        let schema = Schema([ChatThread.self, ChatEntry.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
        // §184：容器进租约——方法返回后仍由租约强
        // 持有，不许只存方法局部
        swiftDataMount.retain(container)
        self.container = container

        // 种子：一条线程＋一条无附件用户条目（发
        // 送瞬间形态——正文已落盘、附件未回填）
        let context = ModelContext(container)
        let thread = ChatThread(title: "主线")
        let entry = ChatEntry(
            role: "user", content: "能不能看到", thread: thread
        )
        context.insert(thread)
        context.insert(entry)
        try context.save()
        entryID = entry.id

        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        // 落点须钉在种子线程：ChatView 冷启 bootstrap
        // 先 ensureMainThread 另建空主线、落点解析默认
        // 回主线——不预选则展示的是那条空线、种子行永
        // 不入列（第一轮 CI 实证：列表 0 行、阶段一超
        // 时）。走生产入口预选（抽屉线程选择，bootstrap
        // 里优先于落点解析消费）
        appState.router.drawerThreadSelection = thread.id
        let host = UIHostingController(
            rootView: ChatView(overviewStore: nil)
                .environment(appState)
                .environment(\.locale, AppLocale.uiLocale)
                .modelContainer(container)
        )
        window = DeviceWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
    }

    // MARK: - 定位助手

    private func findNativeRootController()
        -> ChatRootViewController? {
        var found: ChatRootViewController?
        func walk(_ vc: UIViewController) {
            if let hit = vc as? ChatRootViewController {
                found = hit
            }
            for child in vc.children { walk(child) }
        }
        if let root = window.rootViewController { walk(root) }
        return found
    }

    /// 泵主 runloop 直到条件成立或超时（跨上下文
    /// 落盘的传播与承载落定拍都在 runloop 上推进，
    /// 静态读数等不到）
    private func waitUntil(
        timeout: TimeInterval = 20,
        _ condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.main.run(
                until: Date().addingTimeInterval(0.1)
            )
        }
        return condition()
    }

    /// 当前可见 cell 中的散文形态（种子只有一条
    /// 条目，散文 cell 至多一只）
    private func proseCell(
        in controller: ChatRootViewController
    ) -> (cell: ChatNativeProseCell, indexPath: IndexPath)? {
        let cv = controller.collectionView
        for indexPath in cv.indexPathsForVisibleItems {
            if let cell = cv.cellForItem(at: indexPath)
                as? ChatNativeProseCell {
                return (cell, indexPath)
            }
        }
        return nil
    }

    private func frame(
        in controller: ChatRootViewController,
        at indexPath: IndexPath
    ) -> CGRect? {
        controller.collectionView
            .layoutAttributesForItem(at: indexPath)?.frame
    }

    /// 视图树文本采集（与 ChatNativeListR2Assem-
    /// blyTests 的 §294.1 定版通道同法：遍历真实
    /// 文本载体 UITextView／UILabel／UITextField
    /// ——UIHostingConfiguration 托管内容经无障碍
    /// 通道漏采且元素树懒生成、三轮 CI 实证时有
    /// 时无，本仓已定版改走视图树；同一载体 text
    /// 与 attributedText 只取其一防重复计数）
    private func renderTexts(in view: UIView) -> [String] {
        var out: [String] = []
        func walk(_ v: UIView) {
            if let textView = v as? UITextView {
                if let text = textView.text,
                   !text.isEmpty {
                    out.append(text)
                } else if let attributed =
                    textView.attributedText?.string,
                    !attributed.isEmpty {
                    out.append(attributed)
                }
            }
            if let label = v as? UILabel {
                if let text = label.text,
                   !text.isEmpty {
                    out.append(text)
                } else if let attributed =
                    label.attributedText?.string,
                    !attributed.isEmpty {
                    out.append(attributed)
                }
            }
            if let field = v as? UITextField,
               let text = field.text, !text.isEmpty {
                out.append(text)
            }
            v.subviews.forEach(walk)
        }
        walk(view)
        return out
    }

    // MARK: - 主例：回填时序换装

    func testSentFileChipAppearsAfterBackfillRedress() throws {
        try assembleSeededPage()

        // ① 回填前：原生面在场、该行是散文 cell
        var prose: (cell: ChatNativeProseCell,
                    indexPath: IndexPath)?
        var phase1Diag = "未见原生根控制器"
        let phase1 = waitUntil {
            guard let controller =
                self.findNativeRootController()
            else { return false }
            self.window.layoutIfNeeded()
            let cv = controller.collectionView
            phase1Diag = "items="
                + "\(cv.numberOfItems(inSection: 0))"
                + " visible="
                + "\(cv.indexPathsForVisibleItems.count)"
            prose = self.proseCell(in: controller)
            return prose != nil
        }
        XCTAssertTrue(
            phase1,
            "回填前该行须物化为原生散文 cell（发送瞬间形态）；"
                + "末次诊断：\(phase1Diag)"
        )
        let unwrappedProse = try XCTUnwrap(prose)
        let controller = try XCTUnwrap(
            findNativeRootController()
        )
        let proseHeight = try XCTUnwrap(
            frame(in: controller, at: unwrappedProse.indexPath)
        ).height

        // ② 生产回填原样落盘（§121 发送回填同形：
        // 回执路径 JSON 编码写入 remoteFilePaths-
        // Data＋save；落盘上下文＝视图的环境上下文
        // ——生产发送链正是经 ChatView 的 model-
        // Context 回填（markSendState(in: model-
        // Context) 同链），托管下即容器 mainContext；
        // 第二轮 CI 实证：兄弟上下文落盘不刷新视图
        // 经关系持有的条目实例、行永不重配）
        let context = container.mainContext
        let targetID = try XCTUnwrap(entryID)
        let descriptor = FetchDescriptor<ChatEntry>(
            predicate: #Predicate { $0.id == targetID }
        )
        let entry = try XCTUnwrap(
            try context.fetch(descriptor).first
        )
        entry.remoteFilePathsData =
            try JSONEncoder().encode([filePath])
        try context.save()

        // ③ 回填后：同行重配为托管行——散文 cell
        // 退场、文件名进视图树文本、行高增长
        let indexPath = unwrappedProse.indexPath
        var dressedHeight: CGFloat = 0
        var chipSeen = false
        var phase2Diag = "cell 未取到"
        let phase2 = waitUntil {
            self.window.layoutIfNeeded()
            guard let cell = controller.collectionView
                .cellForItem(at: indexPath)
            else {
                phase2Diag = "cell 未取到"
                return false
            }
            if cell is ChatNativeProseCell {
                phase2Diag = "仍是散文 cell（未重配）"
                return false
            }
            let texts = self.renderTexts(in: cell)
            chipSeen = texts.contains {
                $0.contains(self.fileName)
            }
            var classNames: [String] = []
            func collectClasses(_ v: UIView, _ depth: Int) {
                guard depth < 6,
                      classNames.count < 40
                else { return }
                classNames.append("\(type(of: v))")
                v.subviews.forEach {
                    collectClasses($0, depth + 1)
                }
            }
            collectClasses(cell, 0)
            phase2Diag = "cell="
                + "\(type(of: cell)) texts=\(texts.count)"
                + " chipSeen=\(chipSeen)"
                + " texts=["
                + texts.joined(separator: "|")
                    .prefix(120)
                + "] classes=["
                + classNames.joined(separator: ",")
                    .prefix(300)
                + "]"
            if let height = self.frame(
                in: controller, at: indexPath
            )?.height {
                dressedHeight = height
            }
            return chipSeen && dressedHeight > 0
        }
        XCTAssertTrue(
            phase2,
            "回填后该行须换装托管行且 FileChip 挂牌"
                + "（文件名入视图树文本）；末次诊断："
                + "\(phase2Diag)"
        )
        XCTAssertGreaterThan(
            dressedHeight - proseHeight, 40,
            "换装后行高须较散文形态增长牌高量级："
                + "\(proseHeight)→\(dressedHeight)"
        )
    }
}
