import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// S3 基线探针（§372.1 量测草稿件，未提交）：300 档
/// 提供者重召数／全量布局 pass 耗时／无变化重喂与单
/// 行变化重喂的 apply 本体成本。装配与 ChatSettle-
/// ScopeS5Tests 同式。数字只作同机相对对账。
@MainActor
final class S3BaselineProbeTests: XCTestCase {
    private var window: UIWindow?
    private var controller: ChatRootViewController?
    private var handle: ChatNativeListHandle?

    override func tearDown() {
        window?.isHidden = true
        window = nil
        controller = nil
        handle = nil
        super.tearDown()
    }

    private func assemble() {
        let win = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        let root = UIViewController()
        win.rootViewController = root
        win.makeKeyAndVisible()
        let listHandle = ChatNativeListHandle()
        let list = ChatRootViewController()
        list.handle = listHandle
        list.callbacks = ChatListCarrierCallbacks(
            onScrollGeometry: {},
            onTopVisibleEntry: { _ in },
            onBlankTap: {}
        )
        listHandle.controller = list
        root.addChild(list)
        list.view.frame = root.view.bounds
        root.view.addSubview(list.view)
        list.didMove(toParent: root)
        root.view.layoutIfNeeded()
        window = win
        controller = list
        handle = listHandle
    }

    private func apply(
        _ rows: [ChatNativeRow], settleLayout: Bool = true
    ) {
        controller?.apply(
            rows: rows,
            layout: ChatCarrierLayout(
                horizontalPadding: OneDayMetrics.pageGutter,
                topPadding: OneDayMetrics.spacingM,
                bottomPadding: 8,
                rowSpacing: OneDayMetrics.spacingL,
                arrowTrailing: OneDayMetrics.spacingM,
                arrowGapAboveComposer: 8,
                arrowSize: OneDayMetrics.minTapTarget
            ),
            topInset: 122,
            bottomMargin: 0,
            composerView: AnyView(
                Rectangle()
                    .fill(Color.gray)
                    .frame(height: 54)
            ),
            arrowView: AnyView(Color.clear)
        )
        if settleLayout {
            window?.layoutIfNeeded()
        }
    }

    private func drain(_ seconds: TimeInterval) {
        let exp = expectation(description: "drain \(seconds)")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + seconds
        ) { exp.fulfill() }
        wait(for: [exp], timeout: seconds + 10)
        window?.layoutIfNeeded()
    }

    private func quiesce(timeout: TimeInterval = 15) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var stable = 0
        var last = -1
        while Date() < deadline {
            drain(0.25)
            window?.layoutIfNeeded()
            let now = controller?.testSectionProviderCallCount ?? -2
            if now == last {
                stable += 1
                if stable >= 3 { return true }
            } else {
                stable = 0
                last = now
            }
        }
        return false
    }

    private func textRow(
        _ key: String, text: String, height: CGFloat = 60
    ) -> ChatNativeRow {
        ChatNativeRow(
            key: key, entryID: nil,
            revision: ChatNativeRowRevision(
                parts: [.text(text)]
            ),
            height: height,
            makeView: {
                AnyView(
                    Text(text).frame(
                        maxWidth: .infinity, alignment: .leading
                    )
                )
            }
        )
    }

    private func makeRows(
        count: Int, height: CGFloat = 60
    ) -> [ChatNativeRow] {
        (0..<count).map {
            textRow("k\($0)", text: "row \($0)", height: height)
        }
    }

    private func benchBest(
        passes: Int = 5, _ body: () -> Void
    ) -> UInt64 {
        body()
        var best = UInt64.max
        for _ in 0..<passes {
            let start = DispatchTime.now().uptimeNanoseconds
            body()
            best = min(
                best, DispatchTime.now().uptimeNanoseconds - start
            )
        }
        return best
    }

    /// 300 档：全量失效的提供者重召数＋布局 pass 耗时；
    /// 无变化重喂／单行变化重喂的 apply 本体成本
    func testProviderWidthAndApplyCostAt300() throws {
        assemble()
        let vc = try XCTUnwrap(controller)
        let rows = makeRows(count: 300)
        apply(rows)
        XCTAssertTrue(quiesce(), "装配后提供者计数须收敛稳态")
        let layout = vc.collectionView.collectionViewLayout

        // 提供者重召数（全量失效一趟）
        let p0 = vc.testSectionProviderCallCount
        layout.invalidateLayout()
        window?.layoutIfNeeded()
        let providerDelta =
            vc.testSectionProviderCallCount - p0
        XCTAssertTrue(quiesce(), "全量失效后须再收敛")

        // 全量布局 pass 耗时（失效＋layoutIfNeeded 一趟）
        let layoutPassNs = benchBest {
            layout.invalidateLayout()
            self.window?.layoutIfNeeded()
        }
        XCTAssertTrue(quiesce(), "布局量测后须再收敛")

        // 无变化重喂 apply 本体（同 rows 再喂：applyNow
        // 全量对账税的现行读数，不含布局 pass）
        let noChangeNs = benchBest {
            self.apply(rows, settleLayout: false)
        }
        window?.layoutIfNeeded()

        // 单行变化重喂 apply 本体（第 150 行修订翻转）
        var flip = false
        let singleNs = benchBest {
            flip.toggle()
            var changed = rows
            changed[150] = self.textRow(
                "k150",
                text: flip ? "row 150 changed" : "row 150"
            )
            self.apply(changed, settleLayout: false)
        }
        window?.layoutIfNeeded()

        print(
            "S3 基线探针：300 行全量失效提供者重召 "
                + "\(providerDelta) 次；全量布局 pass "
                + "\(layoutPassNs / 1_000)µs；无变化重喂 apply "
                + "\(noChangeNs / 1_000)µs；单行变化重喂 apply "
                + "\(singleNs / 1_000)µs（best-of-5，实验室口径）"
        )
        XCTAssertEqual(
            providerDelta, 300,
            "300 行全量失效须重召全部 300 个 section 提供者"
        )
        drain(0.5)
    }
}
