import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §426 缺陷三装配钉：键盘事务贴底跟随——贴底意图
/// 须在键盘开始动之前捕获、事务全程末行完整可见；
/// 离底时键盘升起不许动用户位置。参照对照（用户
/// 双视频）：参照应用键盘起→内容同步上移稳落最新；
/// OneDay 旧链＝键盘不置任何钉底意图、量测在落定
/// 拍一次跳到终值、后续判定按新几何恒读「不在底」
/// →永不重钉、用户须手拉。
@MainActor
final class ChatKeyboardPinAssemblyTests: XCTestCase {
    private var window: UIWindow!
    private var controller: ChatRootViewController!
    private var handle: ChatNativeListHandle!
    private var ids: [UUID] = []

    private let windowHeight: CGFloat = 874
    private let keyboardHeight: CGFloat = 340

    override func tearDown() {
        window?.isHidden = true
        window = nil
        controller = nil
        handle = nil
        super.tearDown()
    }

    private func assemble() {
        let win = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: windowHeight)
        )
        let root = UIViewController()
        win.rootViewController = root
        win.makeKeyAndVisible()
        let listHandle = ChatNativeListHandle()
        let list = ChatRootViewController()
        list.handle = listHandle
        list.callbacks = ChatNativeListCallbacks(
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

    private func apply(_ rows: [ChatNativeRow]) {
        controller?.apply(
            rows: rows,
            layout: ChatNativeLayout(
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
        window?.layoutIfNeeded()
    }

    private func drain(_ seconds: TimeInterval) {
        let exp = expectation(description: "drain \(seconds)")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + seconds
        ) { exp.fulfill() }
        wait(for: [exp], timeout: seconds + 10)
        window?.layoutIfNeeded()
    }

    private func makeRows(count: Int) -> [ChatNativeRow] {
        if ids.count != count {
            ids = (0..<count).map { _ in UUID() }
        }
        return (0..<count).map { index in
            ChatNativeRow(
                key: "r\(index)", entryID: ids[index],
                revision: ChatNativeRowRevision(
                    parts: [.text("row \(index)")]
                ),
                height: 60,
                makeView: {
                    AnyView(
                        Text("row")
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                    )
                }
            )
        }
    }

    /// 装配＋落底＋意图消费殆尽（第二遍同批重喂不
    /// 再置冷开意图、留足落定拍把首轮意图按判据消
    /// 费）——键盘钉测的前置必须是「在底且无在途
    /// 意图」，与真机「停在底部读消息后点输入框」
    /// 同态
    private func assemblePinnedAndSettled() {
        assemble()
        let rows = makeRows(count: 40)
        apply(rows)
        drain(1.0)
        apply(rows)
        drain(0.8)
        XCTAssertTrue(
            handle.contentEndVisible,
            "前置：在底末行应完整可见"
        )
        XCTAssertLessThanOrEqual(
            handle.latestDistance, 1,
            "前置：距底应≈0，实 \(handle.latestDistance)"
        )
    }

    private func postKeyboardShow(
        height: CGFloat, duration: Double = 0.25
    ) {
        let frame = CGRect(
            x: 0, y: windowHeight - height,
            width: 402, height: height
        )
        NotificationCenter.default.post(
            name: UIResponder.keyboardWillShowNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey:
                    NSValue(cgRect: frame),
                UIResponder.keyboardAnimationDurationUserInfoKey:
                    duration,
                UIResponder.keyboardAnimationCurveUserInfoKey: 7,
            ]
        )
    }

    private func postKeyboardHide(duration: Double = 0.25) {
        let frame = CGRect(
            x: 0, y: windowHeight, width: 402, height: keyboardHeight
        )
        NotificationCenter.default.post(
            name: UIResponder.keyboardWillHideNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey:
                    NSValue(cgRect: frame),
                UIResponder.keyboardAnimationDurationUserInfoKey:
                    duration,
                UIResponder.keyboardAnimationCurveUserInfoKey: 7,
            ]
        )
    }

    /// 贴底→键盘起→末行完整可见零手拉（终态断言）
    func testKeyboardShowAtBottomLandsOnLatest() {
        assemblePinnedAndSettled()
        let insetBefore = handle.bottomInset
        postKeyboardShow(height: keyboardHeight)
        drain(0.7)
        XCTAssertTrue(
            handle.contentEndVisible,
            "键盘起后末行应完整可见（旧链缺陷：距底≈键盘高、末行被顶出视口）"
        )
        XCTAssertLessThanOrEqual(
            handle.latestDistance, 1,
            "键盘起后距底应≈0，实 \(handle.latestDistance)"
        )
        XCTAssertEqual(
            handle.bottomInset - insetBefore, keyboardHeight,
            accuracy: 1.5,
            "底部留位增量应恰＝键盘高"
        )
        // 收起回落同守：在底者回到在底
        postKeyboardHide()
        drain(0.7)
        XCTAssertTrue(handle.contentEndVisible)
        XCTAssertLessThanOrEqual(handle.latestDistance, 1)
    }

    /// 中途帧：键盘动画未走完时末行已完整可见、栈
    /// 留位一步到位不逐帧爬（无压扁/被盖的中间态）
    func testKeyboardShowMidAnimationTailAlreadyVisible() {
        assemblePinnedAndSettled()
        let insetBefore = handle.bottomInset
        postKeyboardShow(height: keyboardHeight, duration: 0.6)
        drain(0.12)
        XCTAssertTrue(
            handle.contentEndVisible,
            "动画中途帧末行应已完整可见，实距底 \(handle.latestDistance)"
        )
        XCTAssertEqual(
            handle.bottomInset - insetBefore, keyboardHeight,
            accuracy: 1.5,
            "中途帧留位应已一步到位（单事务记账），实增量 "
                + "\(handle.bottomInset - insetBefore)"
        )
        drain(0.8)
        XCTAssertTrue(handle.contentEndVisible)
        XCTAssertLessThanOrEqual(handle.latestDistance, 1)
    }

    /// 离底→键盘起→位置不动（不许把人拽回底部）
    func testKeyboardShowAwayFromBottomLeavesPosition() {
        assemblePinnedAndSettled()
        let pinnedOffset = controller.collectionView.contentOffset.y
        let target = pinnedOffset - 400
        controller.collectionView.setContentOffset(
            CGPoint(x: 0, y: target), animated: false
        )
        drain(0.5)
        XCTAssertFalse(
            handle.contentEndVisible,
            "前置：上翻 400 后末行不应完整可见"
        )
        XCTAssertEqual(
            controller.collectionView.contentOffset.y, target,
            accuracy: 1
        )
        postKeyboardShow(height: keyboardHeight)
        drain(0.7)
        XCTAssertEqual(
            controller.collectionView.contentOffset.y, target,
            accuracy: 1,
            "离底时键盘升起不许动用户位置"
        )
        XCTAssertFalse(handle.contentEndVisible)
    }
}
