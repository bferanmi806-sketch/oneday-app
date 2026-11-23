import OneDayCore
import UIKit
import XCTest

/// §403 结构钉测（§382 B1）：底栏图标脱离 symbol 身份、
/// 改模板图资产。把守三件：①tabLabel 图标处不得回归
/// Image(systemName:)——iOS 26 宿主的 fill 变体注入只
/// 作用于活 symbol image，改回符号路＝冷启实色复发
/// （定因 DESIGN §403）；②五枚资产在生产包内解析得
/// 出、画布＝标定布局框、模板渲染；③资产目录声明
/// Template 意图＋保矢量，目录改坏时先红、不静默回落。
final class TabBarTemplateAssetStructureTests: XCTestCase {

    private func repoFile(_ relative: String) throws -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
    }

    /// tabLabel 图标走资产、不走系统符号名
    func testTabLabelIconUsesAssetNotSystemName() throws {
        let src = try String(
            contentsOf: repoFile("Sources/OneDayApp/ContentView.swift"),
            encoding: .utf8
        )
        let start = try XCTUnwrap(
            src.range(of: "private func tabLabel"),
            "找不到 tabLabel"
        )
        let end = try XCTUnwrap(
            src.range(
                of: ".accessibilityLabel(pair.title)",
                range: start.lowerBound..<src.endIndex
            ),
            "找不到 tabLabel 的 accessibilityLabel 收尾"
        )
        let body = String(src[start.lowerBound..<end.upperBound])
        // 只扫代码行：注释里会正当提及被禁写法（如本函数
        // 的 §403 注），注释行不算回归（同仓结构钉惯例）
        let codeOnly = body
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        XCTAssertTrue(
            codeOnly.contains("Image(pair.asset)"),
            "§403：tabLabel 图标应走模板图资产 Image(pair.asset)"
        )
        XCTAssertFalse(
            codeOnly.contains("Image(systemName:"),
            "§403：tabLabel 图标不许回归 Image(systemName:)"
                + "——宿主 fill 注入的复发面"
        )
    }

    /// 五枚资产在宿主 App 包内解析：画布与标定布局框
    /// 一致（生成标定见 Scripts/make-tab-assets.swift，
    /// 墨迹框与符号活渲染逐格对齐、像素差 ≤0.51%），
    /// 且为模板渲染（吃 tint、不自带色）
    func testTabAssetsResolveInAppBundle() {
        let expected: [(String, CGSize)] = [
            ("tab.chat", CGSize(width: 31, height: 27)),
            ("tab.feed", CGSize(width: 26, height: 29)),
            ("tab.ideas", CGSize(width: 22, height: 31)),
            ("tab.goals", CGSize(width: 32, height: 28)),
            ("tab.files", CGSize(width: 34, height: 24)),
        ]
        XCTAssertEqual(TabBarSymbols.all.map(\.asset), expected.map(\.0))
        for (name, size) in expected {
            let image = UIImage(named: name)
            XCTAssertNotNil(
                image,
                "§403：资产 \(name) 在生产包内解析不出"
            )
            guard let image else { continue }
            XCTAssertEqual(
                image.size.width, size.width, accuracy: 0.6,
                "§403：\(name) 画布宽应为标定布局框 \(size)"
            )
            XCTAssertEqual(
                image.size.height, size.height, accuracy: 0.6,
                "§403：\(name) 画布高应为标定布局框 \(size)"
            )
            XCTAssertEqual(
                image.renderingMode, .alwaysTemplate,
                "§403：\(name) 应为模板渲染（吃 tint、不自带色）"
            )
        }
    }

    /// 资产目录声明：Template 意图＋保矢量＋PDF 实物在位
    func testAssetCatalogDeclaresTemplateVector() throws {
        for pair in TabBarSymbols.all {
            let dir = try repoFile(
                "App/Resources/Assets.xcassets/\(pair.asset).imageset"
            )
            let json = try String(
                contentsOf: dir.appendingPathComponent("Contents.json"),
                encoding: .utf8
            )
            XCTAssertTrue(
                json.contains("\"template-rendering-intent\""),
                "§403：\(pair.asset) Contents.json 缺 Template 意图"
            )
            XCTAssertTrue(
                json.contains("\"template\""),
                "§403：\(pair.asset) Template 意图值异常"
            )
            XCTAssertTrue(
                json.contains("\"preserves-vector-representation\" : true"),
                "§403：\(pair.asset) 缺保矢量声明"
            )
            let pdf = dir.appendingPathComponent("\(pair.asset).pdf")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: pdf.path),
                "§403：\(pair.asset) 矢量 PDF 缺失"
            )
        }
    }
}
