import SwiftUI
import UIKit
import XCTest

/// 换引擎步骤 0 · 探针 A 线程件（单独成套、单独跑）：
/// 现行量测台（§331 ChatNativeRowMeasureDesk）在后台串行
/// 队列上算高——若行高来源换成 UIHostingController 托管
/// 量测，这条后台路必须仍然成立。本例在后台队列上：①对
/// 照组做 TextKit 量测（§251 量测台同技术、生产已证后台
/// 可行）；②实验组新建 UIHostingController 并 sizeThat
/// Fits。实验组若触发 UIKit 主线程断言/崩溃，本进程即以
/// 崩溃收场——那本身就是判定证据（故本套必须单独跑、
/// 不与任何其他套同轮）。本类刻意不标 @MainActor。
final class SwapStep0ProbeAThreadTests: XCTestCase {

    func testProbeAThreadFeasibility() {
        let text = """
        先把问题拆成三部分：第一是布局 pass 的自我失效路径，第二是行高来源，第三是验证方法。
        逐项核对之后发现闸门并不在这条路上，所以修法必须落在结构上而不是继续加守卫。
        最后把行高改成量测回喂的固定高，框架不再估算和修正，环按构造拆除。
        """
        // 对照组：TextKit 后台量测
        // 接管修正二/三（2026-11-23）：global().sync 与
        // 专用串行队列 .sync 两轮实测均被 GCD 同步交接
        // 跑回主线程（打印 mainThread=true）——dispatch_
        // sync 语义下提交线程可直执 block，队列形态救
        // 不了。改分离线程＋信号量：block 必在独立线程
        // 执行，后台性才可证。生产量测台（§331）以
        // async 投单、由工作池线程执行，与本 harness
        // 同属「非主线程」保证。
        func onDetachedThread(
            _ body: @escaping () -> Void
        ) {
            let done = DispatchSemaphore(value: 0)
            Thread.detachNewThread {
                body()
                done.signal()
            }
            done.wait()
        }
        var controlOutcome = "not-run"
        onDetachedThread {
            let storage = NSTextStorage(
                string: text,
                attributes: [
                    .font: UIFont.preferredFont(
                        forTextStyle: .body
                    ),
                ]
            )
            let layoutManager = NSLayoutManager()
            let container = NSTextContainer(
                size: CGSize(
                    width: 280,
                    height: CGFloat.greatestFiniteMagnitude
                )
            )
            container.lineFragmentPadding = 0
            storage.addLayoutManager(layoutManager)
            layoutManager.addTextContainer(container)
            layoutManager.ensureLayout(for: container)
            let h = layoutManager.usedRect(
                for: container
            ).height
            controlOutcome = "returned \(h)"
                + " mainThread=\(Thread.isMainThread)"
        }
        print("PROBEA-THREAD|textkit-bg|\(controlOutcome)")

        // 实验组：托管量测后台直调（可能崩溃——即证据）
        var hostedOutcome = "not-run"
        onDetachedThread {
            let host = UIHostingController(
                rootView: AnyView(
                    Text(text).frame(width: 280)
                )
            )
            let h = host.sizeThatFits(
                in: CGSize(
                    width: 280,
                    height: CGFloat.greatestFiniteMagnitude
                )
            ).height
            hostedOutcome = "returned \(h)"
                + " mainThread=\(Thread.isMainThread)"
        }
        print("PROBEA-THREAD|hosted-bg|\(hostedOutcome)")
        XCTAssertTrue(hostedOutcome.hasPrefix("returned"))
        // 接管修正（2026-11-23）：dispatch_sync 存在调用线程
        // 直执的优化可能——不断言非主线程执行，「后台返回」
        // 不构成可行性证据。
        XCTAssertTrue(
            hostedOutcome.contains("mainThread=false"),
            "托管量测须实证在非主线程执行：\(hostedOutcome)"
        )
    }
}
