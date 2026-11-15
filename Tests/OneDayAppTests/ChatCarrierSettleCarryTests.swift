import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §247（包 4）承载留高旗单测：流式行落定换代
/// 时（同键＋版本变＋带旗），落定帧行高按流式
/// 期量实连续（不回落估算）、托管重测后量实回
/// 填再纠偏；无旗行版本变仍按包 3 口径弃量实
/// 回估算。以 contentSize 为观测面（顶/底
/// padding 16/8 已知）：单行内容高＝content-
/// Size.height − 24。
///
/// 宿主形态（CI 二轮教训）：不用 UIWindow——
/// 测试宿主里窗口不布局、VC 宽度恒 0、layout-
/// Content 被守卫挡下（contentSize 恒 0）；改
/// 离屏直驱：loadViewIfNeeded＋定帧＋layout-
/// IfNeeded 触发 viewDidLayoutSubviews 定宽。
///
/// 驱动口径（§259 对齐）：量实只在落定拍里由
/// materialize 记下——apply 同步段只做量实移
/// 交与帧表重建，托管/量测/回填重排全排到
/// DispatchQueue.main.async 的合并落定拍。
/// 故断言读高前须先 drain 主 runloop 把落定
/// 拍泵到落定（拍一记量实→回填拍重建帧表），
/// 与 §259 热修自有 ReentrancyTests 同式；旧
/// 形态的 inset 切换同步泵只重算帧表、量实从
/// 未落定，读到的恒是估算值（终轮 CI 实证）。
@MainActor
final class ChatCarrierSettleCarryTests: XCTestCase {

    private var controller: ChatListCarrierViewController!

    private let layout = ChatCarrierLayout(
        horizontalPadding: 20, topPadding: 16,
        bottomPadding: 8, rowSpacing: 24,
        arrowTrailing: 16, arrowSize: 44
    )

    override func setUp() async throws {
        try await super.setUp()
        controller = ChatListCarrierViewController()
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(
            x: 0, y: 0, width: 402, height: 874
        )
        controller.view.layoutIfNeeded()
        XCTAssertEqual(
            controller.scrollView.bounds.width, 402,
            accuracy: 0.6, "离屏定宽未生效")
    }

    override func tearDown() async throws {
        controller = nil
        try await super.tearDown()
    }

    private func fixedRow(
        version: Int, estimated: CGFloat, viewHeight: CGFloat,
        carry: Bool
    ) -> ChatCarrierRow {
        ChatCarrierRow(
            key: "stream-user-1",
            entryID: nil,
            version: version,
            estimatedHeight: estimated,
            keepsMeasuredHeightOnVersionChange: carry,
            makeView: {
                AnyView(
                    Color.red.frame(width: 300, height: viewHeight)
                )
            }
        )
    }

    private func apply(_ row: ChatCarrierRow) {
        controller.apply(
            rows: [row], layout: layout,
            topInset: 0, bottomInset: 0, bottomSpace: 0,
            keyboardAnimationDuration: 0,
            keyboardAnimationCurveRaw: 0, arrowView: nil
        )
    }

    /// 落定拍泵：drain 主 runloop，把 §259 合并
    /// 调度排定的落定拍泵到落定——拍一 materialize
    /// 托管并记量实、量实回填再排一拍重建帧表，
    /// 两拍都在本次 drain 内跑完，返回时帧高已按
    /// 量实落定（与 ReentrancyTests 的 drainRunLoop
    /// 同式同参）
    private func drainRunLoop(
        seconds: TimeInterval = 0.5
    ) {
        RunLoop.main.run(
            until: Date().addingTimeInterval(seconds)
        )
    }

    private var contentRowHeight: CGFloat {
        controller.scrollView.contentSize.height - 24
    }

    func testSettleCarryKeepsMeasuredHeightAcrossVersionChange() {
        // 流式期：估算 100、托管量实 180——落定拍
        // materialize 记量实、回填重排后帧高按量
        // 实落定
        let streaming = fixedRow(
            version: 1, estimated: 100, viewHeight: 180,
            carry: false)
        apply(streaming)
        drainRunLoop()
        XCTAssertEqual(contentRowHeight, 180, accuracy: 0.6)

        // 落定帧：同键、版本变、带旗、新内容实高
        // 260、估算 90——apply 同步段移交量实并按
        // 180 重建帧表，落定拍到达前读高须仍为
        // 180（不回落估算、不抢跳新高）
        let settled = fixedRow(
            version: 2, estimated: 90, viewHeight: 260,
            carry: true)
        apply(settled)
        XCTAssertEqual(contentRowHeight, 180, accuracy: 0.6)

        // 落定拍托管重测记下新量实 260、回填重排
        // 后纠偏到 260（量实回填覆盖移交值）
        drainRunLoop()
        XCTAssertEqual(contentRowHeight, 260, accuracy: 0.6)
    }

    func testVersionChangeWithoutCarryDropsToEstimate() {
        let streaming = fixedRow(
            version: 1, estimated: 100, viewHeight: 180,
            carry: false)
        apply(streaming)
        drainRunLoop()
        XCTAssertEqual(contentRowHeight, 180, accuracy: 0.6)

        // 无旗：版本变即弃量实、同步回估算 90
        // （包 3 既有口径不许被留高旗误伤）
        apply(fixedRow(
            version: 2, estimated: 90, viewHeight: 260,
            carry: false))
        XCTAssertEqual(contentRowHeight, 90, accuracy: 0.6)
    }
}
