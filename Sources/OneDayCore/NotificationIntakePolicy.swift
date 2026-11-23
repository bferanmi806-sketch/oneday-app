import Foundation

/// 通知入账分级（§454，用户 2026-11-24 03:50 亲点
/// 「为什么每一次回复消息都有运行完成的提示」）：
/// 铃铛只装「需要用户知道或处理」的东西——回复本
/// 身即通知（§426 已在聊天侧定版），前台会话的正
/// 常完成不进铃铛；失败与待批永远逐条在账；背景事
/// 件留底，但同类短时窗内聚合为一条计数行，不许
/// 刷屏。本文件是入账判定的唯一落点：分类只认条
/// 目自带的结构信号（kind 与 refId），失败信号与
/// NotificationTier 的分类口径同源（kind 含 fail/
/// error）；View 与 Store 不许各自拼判定。
public enum NotificationIntakePolicy {

    public enum Disposition: Equatable, Sendable {
        /// 一级：即时＋留底，逐条呈现（待批/裁决回
        /// 执/失败与异常终态）
        case immediate
        /// 二级：留底，同类短窗可聚合（后台与定时任
        /// 务完成、监测变化、系统类）
        case aggregatable
        /// 三级：不进铃铛——不入名单、不入存档、不
        /// 进提醒规划（前台会话的正常完成）
        case suppressed
    }

    /// 二级聚合窗（秒，常量单源、不设用户开关）：
    /// 同类事件相邻间隔在此窗内链式合并。桥轮询
    /// 30 秒、cron/kanban 批量完成以分钟计——600
    /// 秒覆盖一波突发，又不把相隔久远的同类事件
    /// 误并成一行
    public static let aggregationWindow: TimeInterval = 600

    /// 条目 → 级。userSessionIDs＝用户在场会话链
    /// （本机线程已关联的服务端会话 id 集）；三级
    /// 只认正向识别：refId 命中会话链才压，认不出
    /// 的（无 refId/未收养会话）一律留底走二级，
    /// 宁可多留不可错杀
    public static func disposition(
        for item: OverviewNotification,
        userSessionIDs: Set<String>
    ) -> Disposition {
        // 失败/异常终态恒一级：哪怕出自用户自己的
        // 会话也必须在账——§426 对前台失败只消角
        // 标与弹卡、记录保留，本级与之同向
        let kind = item.kind.lowercased()
        if kind.contains("fail") || kind.contains("error") {
            return .immediate
        }
        // 待批请求与裁决回执恒一级：要用户处理或
        // 知晓结果的，不许聚合、不许压
        if item.kind == "approval_pending" || item.isDecisionReceipt {
            return .immediate
        }
        if item.kind == "task_completed" {
            if let refId = item.refId, !refId.isEmpty,
               userSessionIDs.contains(refId) {
                return .suppressed
            }
            return .aggregatable
        }
        // 监测变化与未知 kind（系统类兜底）：二级
        return .aggregatable
    }

    /// 一批条目里要压下的 id（入账口收口用）：会
    /// 话链为空（调用方给不出名单）时恒空——正向
    /// 识别不成立就不压
    public static func suppressedIDs(
        notifications: [OverviewNotification],
        userSessionIDs: Set<String>
    ) -> [String] {
        guard !userSessionIDs.isEmpty else { return [] }
        return notifications.compactMap { item in
            disposition(
                for: item, userSessionIDs: userSessionIDs
            ) == .suppressed ? item.id : nil
        }
    }

    // MARK: - 聚合行

    /// 铃铛列表行：单条，或同类二级事件的聚合
    /// （items 新→旧，lead＝最新一条，行面以它
    /// 为准、计数在元信息行申报）
    public struct Row: Equatable, Sendable, Identifiable {
        public let items: [OverviewNotification]

        public init(items: [OverviewNotification]) {
            self.items = items
        }

        public var lead: OverviewNotification { items[0] }
        public var id: String { lead.id }
        public var isAggregate: Bool { items.count > 1 }
        public var hasUnread: Bool {
            items.contains { !$0.read }
        }
    }

    /// 把一日的条目（新→旧序，NotificationGrouping
    /// 组内序）折成行：只有二级条目参与聚合，键＝
    /// kind；与上一条同键且间隔不超过聚合窗才并
    /// 入（链式）；一级条目恒单行并截断聚合链；
    /// 时间解析不出的条目不参与聚合（证不了窗）
    public static func rows(
        items: [OverviewNotification]
    ) -> [Row] {
        var result: [Row] = []
        var openKind: String?
        var openItems: [OverviewNotification] = []
        var openLastDate: Date?

        func flush() {
            guard !openItems.isEmpty else { return }
            result.append(Row(items: openItems))
            openItems = []
            openKind = nil
            openLastDate = nil
        }

        for item in items {
            // 行折叠只分一级/二级：三级条目入账口已
            // 拦下、不该到这；此处以空会话链判定，
            // task_completed 一律按二级待折（正向识
            // 别不在呈现层重演）
            let level = disposition(
                for: item, userSessionIDs: []
            )
            let date = NotificationGrouping.parseCreatedAt(
                item.createdAt
            )
            guard level == .aggregatable, let date else {
                flush()
                result.append(Row(items: [item]))
                continue
            }
            if openKind == item.kind, let last = openLastDate,
               last.timeIntervalSince(date) <= aggregationWindow {
                openItems.append(item)
                openLastDate = date
            } else {
                flush()
                openKind = item.kind
                openItems = [item]
                openLastDate = date
            }
        }
        flush()
        return result
    }
}
