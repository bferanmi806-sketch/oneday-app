import OneDayCore
import SwiftUI
import UIKit

/// 右滑回复的 UIKit 识别器桥（§265，换代包 5）：
/// 取代 SwipeReplyModifier 旧用的 SwiftUI
/// `.simultaneousGesture(DragGesture)`——双审计
/// （claude-/codex-chat-stack-audit-20261114）定
/// 性：SwiftUI 手势与子树 UIKit 手势同场时跟踪
/// 消耗触摸序列，UITextView 双击选字所需的两次
/// 完整 down→up 被打断。用户 2026-11-14 亲令大
/// 厂机制三条之③：手势仲裁＝方向门＋失败依赖，
/// 禁 simultaneousGesture 拖拽压文本手势。
///
/// 构造（全走 UIKit 官方仲裁入口，不自研识别）：
/// - UIPanGestureRecognizer 装在宿主滚动视图上
///   （装配走 ScrollViewTapDismiss 已验的 ascend
///   寻面：桥视图是行内容的 background、恒在滚
///   动视图子树内，新旧两承载同路）；每行一枚、
///   delegate 以「触点起始位置落在本行帧内」圈
///   定辖区（shouldReceive）；
/// - 方向门：gestureRecognizerShouldBegin 消费
///   Core SwipeReplyMotion.passesDirectionGate
///   （横向速度严格占优且向右才认）——纵滚起手
///   本识别器当场 failed、触摸完整归滚动；
/// - 失败依赖（点按先行）：shouldRequireFailu-
///   reOf 对一切 UITapGestureRecognizer/UILong-
///   PressGestureRecognizer 恒真——双击选字、长
///   按选字/编辑菜单的识别器不失败，本横滑不许
///   开始；反向一手：安装时令宿主滚动视图的自
///   家 pan require(toFail: 本识别器)，纵滚等本
///   行横滑先失败（方向门判死即失败、延迟只有
///   起滑判定的一小段位移）；
/// - 起始点排除（代码块/表格横滚区）也在
///   shouldBegin 判：落在排除帧内直接 failed，
///   触摸不被 cancelsTouchesInView 吞掉、横滚
///   区自家滚动不受扰（旧 SwiftUI 构造靠同时识
///   别＋回调内忽略，本构造靠不开始）；
/// - 数值判定（起滑/触发/封顶）仍全走 Core
///   SwipeReplyMotion 单源，呈现层状态写回走
///   onPanChanged/onPanEnded 两条回调（修饰符
///   每次 body 求值经 updateUIView 刷新闭包，
///   与 ScrollViewTapDismiss 的 onBlankTap 同式）。
struct SwipeReplyPanInstaller: UIViewRepresentable {
    var excludedFrames: [CGRect]
    var onPanChanged: (CGFloat) -> Void
    var onPanEnded: () -> Void

    func makeUIView(
        context: Context
    ) -> SwipeReplyPanInstallerView {
        let view = SwipeReplyPanInstallerView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onPanChanged = onPanChanged
        view.onPanEnded = onPanEnded
        return view
    }

    func updateUIView(
        _ uiView: SwipeReplyPanInstallerView,
        context: Context
    ) {
        uiView.excludedFrames = excludedFrames
        uiView.onPanChanged = onPanChanged
        uiView.onPanEnded = onPanEnded
        uiView.installIfNeeded()
    }

    static func dismantleUIView(
        _ uiView: SwipeReplyPanInstallerView,
        coordinator: ()
    ) {
        uiView.uninstall()
    }
}

/// 安装宿主视图兼识别器 delegate（与 TapDismiss-
/// InstallerView 同分工：本体随 SwiftUI 桥存活，
/// 识别器由滚动视图持有、target/delegate 指本
/// 视图；桥卸载时 uninstall 摘除识别器，滚动视
/// 图的 require(toFail:) 随识别器释放失效）
final class SwipeReplyPanInstallerView: UIView,
    UIGestureRecognizerDelegate
{
    var excludedFrames: [CGRect] = []
    var onPanChanged: ((CGFloat) -> Void)?
    var onPanEnded: (() -> Void)?

    private weak var installedScrollView: UIScrollView?
    private var pan: UIPanGestureRecognizer?
    private var retryScheduled = false

    static let recognizerName = "OneDaySwipeReplyPan"

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        installIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        installIfNeeded()
    }

    /// 定位宿主滚动视图并安装（幂等：已装在同一滚
    /// 动视图上直接返回；承载换人时旧识别器随旧
    /// 视图走、本视图在新视图上补装——与 TapDis-
    /// missInstallerView 同口径）。首试在入窗/更
    /// 新拍——彼时层级可能未定版，失败时排一次主
    /// 队列延迟重试（安装时机兜底、装成即止）
    func installIfNeeded() {
        guard let scrollView = findHostingScrollView()
        else {
            if window != nil, !retryScheduled {
                retryScheduled = true
                DispatchQueue.main.async { [weak self] in
                    self?.retryScheduled = false
                    self?.installIfNeeded()
                }
            }
            return
        }
        if installedScrollView === scrollView, pan != nil {
            return
        }
        uninstall()
        let recognizer = UIPanGestureRecognizer(
            target: self,
            action: #selector(handlePan(_:))
        )
        recognizer.name = Self.recognizerName
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = self
        scrollView.addGestureRecognizer(recognizer)
        // 失败依赖（纵滚让行）：列表纵滚须等本行
        // 横滑先失败才开始——横滑的速度门判死发
        // 生在起滑判定点，纵滚延迟以点计
        scrollView.panGestureRecognizer.require(
            toFail: recognizer
        )
        pan = recognizer
        installedScrollView = scrollView
    }

    /// 摘除本行识别器（桥 dismantle 时调用；识别
    /// 器释放后滚动视图侧的失败依赖随之失效）
    func uninstall() {
        if let pan, let installedScrollView {
            installedScrollView.removeGestureRecognizer(pan)
        }
        pan = nil
        installedScrollView = nil
    }

    /// 测试与普查入口：本视图当前持有的识别器
    var installedRecognizer: UIPanGestureRecognizer? {
        pan
    }

    private func findHostingScrollView() -> UIScrollView? {
        // 桥视图是行内容的 background、恒在宿主滚
        // 动视图子树内（旧承载 HostingScrollView/
        // 新承载 ChatListCarrier 的 UIScrollView 同
        // 理）——ascend 直达，不需要 TapDismiss 的
        // 窗口选面兜底（那是给「与滚动视图同父兄
        // 弟」的桥用的，本桥不在那个位置）
        var ancestor = superview
        var hops = 0
        while let current = ancestor, hops < 16 {
            if let scroll = current as? UIScrollView {
                return scroll
            }
            ancestor = current.superview
            hops += 1
        }
        return nil
    }

    // MARK: - 识别器动作

    @objc private func handlePan(
        _ recognizer: UIPanGestureRecognizer
    ) {
        switch recognizer.state {
        case .began, .changed:
            processPanTranslation(
                recognizer.translation(in: recognizer.view).x
            )
        case .ended, .cancelled, .failed:
            processPanEnd()
        default:
            break
        }
    }

    /// 拖动处理（与识别器动作的接缝：单测以合成
    /// 位移直调本口验回调链，触摸 plumbing 本身
    /// 归 UIKit、无可自验面）
    func processPanTranslation(_ translationX: CGFloat) {
        onPanChanged?(translationX)
    }

    /// 拖动收尾（松手/取消/失败同口：呈现层回位）
    func processPanEnd() {
        onPanEnded?()
    }

    // MARK: - UIGestureRecognizerDelegate（仲裁三条）

    /// 辖区圈定：触点起始位置落在本行帧内才接收
    /// （桥视图＝行内容 background、其帧即行帧；
    /// 坐标换算到滚动视图内容系，与触点同系比对）
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard let scrollView = installedScrollView
        else { return false }
        let point = touch.location(in: scrollView)
        let rowFrame = convert(bounds, to: scrollView)
        return rowFrame.contains(point)
    }

    /// 方向门＋排除门：速度不满足横向占优、或起
    /// 滑点落在排除帧（代码块/表格横滚区）内——
    /// 不许开始（转 failed、触摸不被吞）
    func gestureRecognizerShouldBegin(
        _ gestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard let pan = gestureRecognizer
            as? UIPanGestureRecognizer
        else { return true }
        if SwipeReplyMotion.isExcluded(
            startLocation: pan.location(in: self),
            frames: excludedFrames
        ) {
            return false
        }
        let velocity = pan.velocity(in: pan.view)
        return SwipeReplyMotion.passesDirectionGate(
            velocityX: velocity.x, velocityY: velocity.y
        )
    }

    /// 失败依赖（点按先行）：本横滑须等一切点按/
    /// 长按类识别器先失败——含 UITextView 自家
    /// 的双击选词与长按选字识别器（同触摸序列的
    /// 竞争者经本口径让行）、行内铬件的 context-
    /// Menu 长按、点空白收键盘的点按
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf
            otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        otherGestureRecognizer is UITapGestureRecognizer
            || otherGestureRecognizer
                is UILongPressGestureRecognizer
    }

    /// 与任何识别器都不同时识别：成败只走方向门
    /// 与失败依赖两条明路，不留并行含糊面
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith
            otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }
}
