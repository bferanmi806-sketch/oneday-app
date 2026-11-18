import SwiftData

/// 本地库版本化迁移链（根治版包 3，DESIGN §332；
/// 待办第 122 条 G-05）：自本版起本地库的 schema
/// 演进只许走版本链——现行模型集冻结为 V1，此后
/// 任何结构变更（加非可选字段/改名/改类型/删字段
/// 等）必须新开 ChatSchemaV2 并在 ChatMigration-
/// Plan 追加迁移段，不许再原地改 V1 的模型定义。
///
/// 冻结形态：V1 的模型集即 ChatStore.swift 的现行
/// 两模型本体（ChatThread/ChatEntry），本枚举只引
/// 用、不搬家——模型类型与实体指纹保持与已发布
/// 库逐字一致（指纹由 SchemaFoundationAppTests 的
/// 指纹测钉死：原地改模型必然触发红）。下一次变
/// 更时，先把 V1 两模型复制冻结为独立定义、新模
/// 型进 V2，链上逐级迁移。
enum ChatSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    /// 备份命名用的版本字面（与 versionIdentifier
    /// 同值，改版时两处同拍更新）
    static let versionTag = "1.0.0"

    static var models: [any PersistentModel.Type] {
        [ChatThread.self, ChatEntry.self]
    }
}

/// 当前版本别名：容器工厂只许引用本别名指向的版
/// 本立 Schema；升版时改指新版一处即可
typealias CurrentChatSchema = ChatSchemaV1

/// 迁移计划（§332）：版本序列与逐级迁移段的唯一
/// 声明处。本版只有 V1、无迁移段——链先立住，下
/// 一次 schema 变更在本计划内追加 V2 与迁移段，
/// 不许绕过计划直接换 Schema 打开旧库
enum ChatMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [ChatSchemaV1.self]
    }

    static var stages: [MigrationStage] { [] }
}
