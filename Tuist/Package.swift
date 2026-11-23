// swift-tools-version: 5.9
import PackageDescription

#if TUIST
import ProjectDescription

let packageSettings = PackageSettings(
    productTypes: [:]
)
#endif

// 外部 SPM 依赖总账（Tuist 4 口径：依赖声明在本文件、
// Project.swift 侧以 .external(name:) 引用；版本钉死、
// 解析结果随仓入库，升级须单独成包记账）。
// §417（#13 Markdown 换底）：swiftlang/swift-markdown
// 解析核，Apache-2.0；钉版 0.6.0（2026-11-23 最新稳定版）。
let package = Package(
    name: "OneDay",
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-markdown.git",
            exact: "0.6.0"
        )
    ]
)
