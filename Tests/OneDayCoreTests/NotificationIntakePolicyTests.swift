import XCTest

@testable import OneDayCore

/// §454 通知入账分级钉测：前台会话正常完成不入账、
/// 失败必入账、待批两处同数（角标待批轴与快照逐字
/// 同值——枢纽审核格与铃铛角标同出写闸待批一账：
/// 桥 _overview 的 pendingApprovals 取写闸 /status
/// 计数、枢纽 gateClient.pendingList 取同一写闸
/// /pending 名单，本包不新建第三计数）、二级聚合
/// 窗链式合并
final class NotificationIntakePolicyTests: XCTestCase {

    private func item(
        _ id: String, kind: String, refId: String? = nil,
        read: Bool = false,
        createdAt: String = "2026-11-24T03:00:00Z"
    ) -> OverviewNotification {
        OverviewNotification(
            id: id, kind: kind, title: "t", body: "b",
            createdAt: createdAt, read: read, refId: refId
        )
    }

    private let mine: Set<String> = ["sess-mine"]

    // MARK: - 三级：前台会话正常完成不入账

    func testUserSessionCompletionIsSuppressed() {
        let entry = item(
            "run-1", kind: "task_completed", refId: "sess-mine"
        )
        XCTAssertEqual(
            NotificationIntakePolicy.disposition(
                for: entry, userSessionIDs: mine
            ),
            .suppressed
        )
        XCTAssertEqual(
            NotificationIntakePolicy.suppressedIDs(
                notifications: [entry], userSessionIDs: mine
            ),
            ["run-1"]
        )
    }

    func testBackgroundCompletionIsKeptAsAggregatable() {
        let entry = item(
            "run-2", kind: "task_completed", refId: "sess-cron-9"
        )
        XCTAssertEqual(
            NotificationIntakePolicy.disposition(
                for: entry, userSessionIDs: mine
            ),
            .aggregatable
        )
        XCTAssertTrue(
            NotificationIntakePolicy.suppressedIDs(
                notifications: [entry], userSessionIDs: mine
            ).isEmpty
        )
    }

    func testCompletionWithoutRefIdIsKept() {
        // 正向识别不成立就不压：无 refId 的完成宁可
        // 留底，不许错杀
        let entry = item("run-3", kind: "task_completed")
        XCTAssertEqual(
            NotificationIntakePolicy.disposition(
                for: entry, userSessionIDs: mine
            ),
            .aggregatable
        )
    }

    func testEmptySessionChainSuppressesNothing() {
        let entry = item(
            "run-4", kind: "task_completed", refId: "sess-mine"
        )
        XCTAssertTrue(
            NotificationIntakePolicy.suppressedIDs(
                notifications: [entry], userSessionIDs: []
            ).isEmpty
        )
    }

    // MARK: - 一级：失败必入账、待批与回执逐条在账

    func testFailureIsImmediateEvenForUserSession() {
        let failed = item(
            "run-5", kind: "run_failed", refId: "sess-mine"
        )
        XCTAssertEqual(
            NotificationIntakePolicy.disposition(
                for: failed, userSessionIDs: mine
            ),
            .immediate
        )
        // error 信号同口径（与 NotificationTier 分类同源）
        let errored = item(
            "run-6", kind: "task_error", refId: "sess-mine"
        )
        XCTAssertEqual(
            NotificationIntakePolicy.disposition(
                for: errored, userSessionIDs: mine
            ),
            .immediate
        )
    }

    func testApprovalKindsAreImmediate() {
        let pending = item(
            "wgp-1", kind: "approval_pending", refId: "mem_1"
        )
        XCTAssertEqual(
            NotificationIntakePolicy.disposition(
                for: pending, userSessionIDs: mine
            ),
            .immediate
        )
        let receipt = item(
            "dec-1", kind: "write_gate_decision", refId: "mem_1"
        )
        XCTAssertEqual(
            NotificationIntakePolicy.disposition(
                for: receipt, userSessionIDs: mine
            ),
            .immediate
        )
    }

    func testMonitorChangeIsAggregatable() {
        let change = item(
            "mon-1", kind: "monitor_change", refId: "watch-1"
        )
        XCTAssertEqual(
            NotificationIntakePolicy.disposition(
                for: change, userSessionIDs: mine
            ),
            .aggregatable
        )
    }

    // MARK: - 待批同数：角标待批轴＝快照原值

    func testBadgePendingComponentIsSnapshotVerbatim() {
        let snapshot = OverviewSnapshot(
            hermesUp: true, activeSessions: 0,
            pendingApprovals: 3, unreadNotifications: 0,
            generatedAt: ""
        )
        XCTAssertEqual(OverviewBadge.count(snapshot: snapshot), 3)
        let mixed = OverviewSnapshot(
            hermesUp: true, activeSessions: 0,
            pendingApprovals: 3, unreadNotifications: 2,
            generatedAt: ""
        )
        XCTAssertEqual(OverviewBadge.count(snapshot: mixed), 5)
    }

    // MARK: - 二级聚合：同类短窗链式合并

    func testRowsAggregateBurstWithinWindow() {
        let rows = NotificationIntakePolicy.rows(items: [
            item("m3", kind: "monitor_change",
                 createdAt: "2026-11-24T03:10:00Z"),
            item("m2", kind: "monitor_change",
                 createdAt: "2026-11-24T03:07:00Z"),
            item("m1", kind: "monitor_change",
                 createdAt: "2026-11-24T03:02:00Z"),
        ])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].items.count, 3)
        XCTAssertEqual(rows[0].lead.id, "m3")
        XCTAssertTrue(rows[0].isAggregate)
    }

    func testRowsChainAcrossLongSpanBySmallGaps() {
        // 相邻间隔各 8 分钟（窗 10 分钟）：链式合并
        // 跨度 16 分钟仍并一行——突发以相邻密度判，
        // 不以总跨度判
        let rows = NotificationIntakePolicy.rows(items: [
            item("m3", kind: "monitor_change",
                 createdAt: "2026-11-24T03:10:00Z"),
            item("m2", kind: "monitor_change",
                 createdAt: "2026-11-24T03:02:00Z"),
            item("m1", kind: "monitor_change",
                 createdAt: "2026-11-24T02:54:00Z"),
        ])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].items.count, 3)
    }

    func testRowsSplitWhenGapExceedsWindow() {
        let rows = NotificationIntakePolicy.rows(items: [
            item("m2", kind: "monitor_change",
                 createdAt: "2026-11-24T03:10:00Z"),
            item("m1", kind: "monitor_change",
                 createdAt: "2026-11-24T02:50:00Z"),
        ])
        XCTAssertEqual(rows.count, 2)
        XCTAssertFalse(rows[0].isAggregate)
        XCTAssertFalse(rows[1].isAggregate)
    }

    func testRowsImmediateBreaksChain() {
        let rows = NotificationIntakePolicy.rows(items: [
            item("m2", kind: "monitor_change",
                 createdAt: "2026-11-24T03:10:00Z"),
            item("f1", kind: "run_failed",
                 createdAt: "2026-11-24T03:08:00Z"),
            item("m1", kind: "monitor_change",
                 createdAt: "2026-11-24T03:06:00Z"),
        ])
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[1].lead.id, "f1")
    }

    func testRowsDifferentKindsDoNotMerge() {
        let rows = NotificationIntakePolicy.rows(items: [
            item("m1", kind: "monitor_change",
                 createdAt: "2026-11-24T03:10:00Z"),
            item("r1", kind: "task_completed",
                 refId: "sess-cron-9",
                 createdAt: "2026-11-24T03:09:00Z"),
        ])
        XCTAssertEqual(rows.count, 2)
    }

    func testRowsSingleAggregatableStaysSingle() {
        let rows = NotificationIntakePolicy.rows(items: [
            item("m1", kind: "monitor_change",
                 createdAt: "2026-11-24T03:10:00Z"),
        ])
        XCTAssertEqual(rows.count, 1)
        XCTAssertFalse(rows[0].isAggregate)
        XCTAssertEqual(rows[0].lead.id, "m1")
    }

    func testRowsUnreadPropagatesToAggregate() {
        let rows = NotificationIntakePolicy.rows(items: [
            item("m2", kind: "monitor_change", read: true,
                 createdAt: "2026-11-24T03:10:00Z"),
            item("m1", kind: "monitor_change",
                 createdAt: "2026-11-24T03:08:00Z"),
        ])
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].hasUnread)
    }
}
