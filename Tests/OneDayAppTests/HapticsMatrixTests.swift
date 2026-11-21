import XCTest

/// 触感矩阵钉测（2026-11-14 定版包）：触感生成器是
/// 即发即忘的 UIKit 通道、运行时无可观测输出，能测
/// 的只有「落点在不在、语义对不对、越界有没有」——
/// 故按源码扫描钉死矩阵关键数：定版三点（发送
/// impact .light／完成 success 保留／不设开关）＋
/// 24 事件矩阵计数＋防腻清单零越界。源码在测试环
/// 境不可达时整套跳过（真机验项在报告中另列）。
/// 基线对账：rel-05041 存量 90 落点（盘点报告
/// haptics-inventory-20261114，基线 rel-05039 同数）
/// ＋本包新增 2（发送、抽屉手势吸附）＝92。
final class HapticsMatrixTests: XCTestCase {

    /// 仓库 Sources 根（本文件在 Tests/OneDayAppTests/）
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
            throw XCTSkip("源码树在测试环境不可达，落点断言跳过")
        }
        return sources
    }

    /// 全 Sources 拼接文本（剔除封装本体 Haptics.swift：
    /// 盘点口径只数调用点、不数定义与头注）
    private func callSiteText() throws -> String {
        let sources = try sourcesRoot()
        let enumerator = FileManager.default.enumerator(
            at: sources,
            includingPropertiesForKeys: nil
        )
        var chunks: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  url.lastPathComponent != "Haptics.swift",
                  let text = try? String(
                      contentsOf: url, encoding: .utf8
                  )
            else { continue }
            chunks.append(text)
        }
        guard !chunks.isEmpty else {
            throw XCTSkip("未读到任何源码文件，落点断言跳过")
        }
        return chunks.joined(separator: "\n")
    }

    private func fileText(_ relative: String) throws -> String {
        let url = try sourcesRoot().appendingPathComponent(relative)
        guard let text = try? String(contentsOf: url, encoding: .utf8)
        else { throw XCTSkip("\(relative) 不可达，断言跳过") }
        return text
    }

    private func count(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    // MARK: - 定版点一：发送动作补最轻档 impact

    func testSendActionHasLightImpact() throws {
        let chat = try fileText("OneDayApp/ChatView.swift")
        XCTAssertTrue(
            chat.contains("发送触感（2026-11-14 定版）"),
            "ChatView.send() 落盘点必须有发送触感定版标记"
        )
        // ChatView 内 impact .light 共两处：发送动作＋
        // 右滑引用过阈（0.36.19），不得多加
        XCTAssertEqual(count(of: "Haptics.impact(.light)", in: chat), 2)
    }

    func testDrawerGestureSnapHasLightImpact() throws {
        let drawer = try fileText("OneDayApp/DrawerContainerView.swift")
        XCTAssertTrue(
            drawer.contains("opens != semanticPresented"),
            "抽屉手势吸附触感必须以状态真翻转为闸"
        )
        XCTAssertEqual(
            count(of: "Haptics.impact(.light)", in: drawer), 1,
            "抽屉内 impact .light 只许手势吸附这一处（按钮开合无触感）"
        )
    }

    // MARK: - 矩阵计数（24 事件矩阵＋2026-11-14 定版）

    func testMatrixCallSiteCounts() throws {
        let all = try callSiteText()
        // 配对一期（台账 153/160）：连接页扫码认领
        // 新增四处失败落点（载荷验形不过／指纹对不
        // 上／认领分型错／兜底错），与 submit() 失败
        // 同口径用 error（49→53）
        // 台账 198 收敛 S4：设置根页重启执行副本删
        // 除，其 error/success 落点各 −1（53→52、
        // 17→16）；重启触感由网关状态页正主 perform()
        // 的既有落点承接（成功 success／失败 error
        // 原在位），行为不丢
        XCTAssertEqual(count(of: "Haptics.error()", in: all), 52)
        XCTAssertEqual(count(of: "Haptics.warning()", in: all), 6)
        // §259（文件预览双轨合一）：自研文档阅读页退
        // 役，其「复制全文」success 落点 −1（18→17）；
        // 复制动作由打开页与 QL 承载面承接、两面各自
        // 的 success 落点原在位，行为不丢。error 净不
        // 变：阅读页导出 PDF 的 error −1 与 QL 承载面
        // 新补 exportPDF 的 error ＋1 相抵（仍 49）
        XCTAssertEqual(count(of: "Haptics.success()", in: all), 16)
        XCTAssertEqual(count(of: "Haptics.impact(.heavy)", in: all), 8)
        // §295（原生重建 R3）：右滑回复触发的最轻
        // impact 在原生散文 cell 增一落点（5→6）——
        // 与 SwipeReplyModifier 的落点是同一事件的
        // 双承载形态（一行只走其一：原生面走 cell、
        // 托管面走修饰符），行为不重不丢。
        // §325（B 档退役）：散文 cell 整件删除、单渲
        // 染路径落定，cell 落点随之退役——现行由
        // SwipeReplyModifier 单路承接，计数回 5（即
        // R3 前单承载原数）；0.50.68 顺修期待值 6→5
        XCTAssertEqual(count(of: "Haptics.impact(.light)", in: all), 5)
        XCTAssertEqual(
            count(of: ".sensoryFeedback(.selection", in: all), 3)
        XCTAssertEqual(
            count(of: ".sensoryFeedback(.success", in: all), 3)
        // 封装外禁止直调生成器（Haptics.swift 本体已剔除）
        XCTAssertEqual(
            count(of: "UINotificationFeedbackGenerator()", in: all), 0)
        XCTAssertEqual(
            count(of: "UIImpactFeedbackGenerator(style:", in: all), 0)
        XCTAssertEqual(
            count(of: "UISelectionFeedbackGenerator()", in: all), 0)
        // 命令式 selection 零落点（离散切换全走声明式，
        // 与 Haptics.swift 头注口径一致）
        XCTAssertEqual(count(of: "Haptics.selection()", in: all), 0)
    }

    // MARK: - 定版点三：不设 App 内触感开关

    func testNoInAppHapticsSetting() throws {
        let all = try callSiteText()
        XCTAssertFalse(all.contains("hapticsEnabled"))
        XCTAssertFalse(all.contains("HapticsEnabled"))
        let settings = try fileText("OneDayApp/SettingsView.swift")
        XCTAssertFalse(
            settings.contains(".sensoryFeedback"),
            "设置页开关面禁止叠加声明式触感（系统 Toggle 自带）"
        )
    }
}
