import UIKit
import XCTest
@testable import OneDayApp

/// §317 呈现时序断言（诊断 attach-noresponse-diag-
/// nosis-20261117 的 P1 竞速病）：DocumentPicker-
/// Bridge 的呈现驱动以呈现者快照为唯一判定面——
/// ①收起未完（dismissing）时 present 绝不发出（旧
/// 症：发出即被 UIKit 静默丢弃、选择器永不来）；
/// ②过渡清除后重试成功呈现（次数对账）；③恒未就
/// 绪时达上限放弃、onGiveUp 回调恰一次且 present
/// 零发出（不许静默）。驱动的 sleep 注入为空转，
/// 时序逻辑全速跑完、不靠真等待
@MainActor
final class DocumentPickerPresentTimingTests: XCTestCase {

    private typealias Snapshot =
        DocumentPickerBridge.Snapshot

    private let readySnapshot = Snapshot(
        hasPresenter: true, inWindow: true,
        isBeingDismissed: false, isBeingPresented: false,
        hasActiveTransition: false
    )
    /// sheet 收起中途形态：宿主仍在呈现链顶端、
    /// isBeingDismissed＋过渡协调器双在场
    private let dismissingSnapshot = Snapshot(
        hasPresenter: true, inWindow: true,
        isBeingDismissed: true, isBeingPresented: false,
        hasActiveTransition: true
    )

    /// 呈现记录袋：present 的每次调用连同当时尝试
    /// 次序一并记下，供「只在就绪后发出」对账
    private final class Recorder {
        var resolveCount = 0
        var sleepCount = 0
        var presentedAttempts: [Int] = []
        var giveUpReasons: [String] = []
    }

    private func drive(
        recorder: Recorder,
        maxAttempts: Int = 12,
        presenter: UIViewController,
        snapshotAt: @escaping (Int) -> Snapshot
    ) async {
        await DocumentPickerBridge.drivePresentation(
            maxAttempts: maxAttempts,
            retryIntervalNs: 1,
            resolve: {
                recorder.resolveCount += 1
                return (
                    snapshot: snapshotAt(recorder.resolveCount),
                    presenter: presenter
                )
            },
            present: { _, attempt in
                recorder.presentedAttempts.append(attempt)
            },
            onGiveUp: { reason in
                recorder.giveUpReasons.append(reason)
            },
            sleep: { _ in recorder.sleepCount += 1 }
        )
    }

    // MARK: - ①② 收起未完不丢弃、落定后重试成功

    func testDefersWhileDismissingThenPresents() async {
        let recorder = Recorder()
        await drive(
            recorder: recorder,
            presenter: UIViewController()
        ) { call in
            call <= 3 ? dismissingSnapshot : readySnapshot
        }
        // 收起中三查全拦下（present 零发出）、第 4 查
        // 就绪才呈现恰一次；重试间隔恰走 3 档
        XCTAssertEqual(recorder.presentedAttempts, [4])
        XCTAssertEqual(recorder.resolveCount, 4)
        XCTAssertEqual(recorder.sleepCount, 3)
        XCTAssertTrue(recorder.giveUpReasons.isEmpty)
    }

    /// 已就绪时首次即呈现、不空转重试
    func testPresentsImmediatelyWhenReady() async {
        let recorder = Recorder()
        await drive(
            recorder: recorder,
            presenter: UIViewController()
        ) { _ in readySnapshot }
        XCTAssertEqual(recorder.presentedAttempts, [1])
        XCTAssertEqual(recorder.sleepCount, 0)
        XCTAssertTrue(recorder.giveUpReasons.isEmpty)
    }

    /// 呈现中（isBeingPresented）同属未就绪：等对
    /// 方呈现落定后才发，不与在飞呈现撞车
    func testDefersWhileAnotherPresentationInFlight()
        async
    {
        let recorder = Recorder()
        let presenting = Snapshot(
            hasPresenter: true, inWindow: true,
            isBeingDismissed: false, isBeingPresented: true,
            hasActiveTransition: true
        )
        await drive(
            recorder: recorder,
            presenter: UIViewController()
        ) { call in
            call <= 2 ? presenting : readySnapshot
        }
        XCTAssertEqual(recorder.presentedAttempts, [3])
        XCTAssertTrue(recorder.giveUpReasons.isEmpty)
    }

    // MARK: - ③ 超限放弃：不呈现、不静默

    func testGivesUpAfterCapWithoutPresenting() async {
        let recorder = Recorder()
        await drive(
            recorder: recorder,
            maxAttempts: 4,
            presenter: UIViewController()
        ) { _ in dismissingSnapshot }
        // 达上限：present 零发出、放弃回调恰一次且
        // 原因＝收起中；查数恰为上限（不多查一轮）
        XCTAssertTrue(recorder.presentedAttempts.isEmpty)
        XCTAssertEqual(
            recorder.giveUpReasons, ["呈现者收起中"]
        )
        XCTAssertEqual(recorder.resolveCount, 4)
        XCTAssertEqual(recorder.sleepCount, 3)
    }

    // MARK: - 快照本体（生产走查口径）

    /// 取空：无呈现者即未就绪、原因「无呈现者」
    /// （P3 的静默 return 在新口径下必经放弃留痕）
    func testNilPresenterSnapshotIsBlocked() {
        let snapshot = DocumentPickerBridge.snapshot(
            of: nil
        )
        XCTAssertFalse(snapshot.isReady)
        XCTAssertEqual(snapshot.blockedReason, "无呈现者")
    }

    /// 不在窗口的控制器未就绪：view 未装窗时
    /// inWindow＝false，present 不许发给它
    func testWindowlessPresenterSnapshotIsBlocked() {
        let snapshot = DocumentPickerBridge.snapshot(
            of: UIViewController()
        )
        XCTAssertTrue(snapshot.hasPresenter)
        XCTAssertFalse(snapshot.inWindow)
        XCTAssertFalse(snapshot.isReady)
    }
}
