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
// §418（#23 图片管线换底）：kean/Nuke 图片管线（核心＋
// NukeUI），MIT；钉版 13.2.3（2026-11-08 发布，13.2 线
// 最新稳定 patch；14.0 仅 beta 不取）。
let package = Package(
    name: "OneDay",
    dependencies: [
        .package(
            url: "https://github.com/kean/Nuke.git",
            exact: "13.2.3"
        )
    ]
)
