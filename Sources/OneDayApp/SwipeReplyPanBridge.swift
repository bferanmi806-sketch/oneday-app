import OneDayCore
import SwiftUI
import UIKit

/// 右滑回复的 UIKit 识别器桥（§265，换代包 5；
/// 换代包 7 仲裁重做）：取代 SwipeReplyModifier
/// 旧用的 SwiftUI `.simultaneousGesture(DragGes-
/// ture)`——双审计（claude-/codex-chat-stack-
/// audit-20261114）定性：SwiftUI 手势与子树 UI-
/// Kit 手势同场时跟踪消耗触摸序列，UITextView
/// 双击选字所需的两次完整 down→up 被打断。用
/// 户 2026-11-14 亲令大厂机制三条之③：手势仲
/// 裁＝方向门＋失败依赖，禁 simultaneousGes-
/// ture 拖拽压文本手势。
///
/// 构造（全走 UIKit 官方仲裁入口，不自研识别）：
/// - UIPanGestureRecognizer 装在宿主滚动视图上
///   （装配走 ScrollViewTapDismiss 已验的 as-
///   cend 寻面：桥视图是行内容的 background、
///   恒在滚动视图子树内，新旧两承载同路）；每
///   行一枚、delegate 以「触点起始位置落在本
///   行帧内」圈定辖区（shouldReceive）；
/// - 失败依赖（纵滚让行）：安装时令宿主滚动视
///   图的自家 pan require(toFail: 本识别器)，纵
///   滚等本行横滑先失败（方向门判死即失败、延
///   迟只有起滑判定的一小段位移）；
/// - 起始点排除（代码块/表格横滚区）也在 should-
///   Begin 判：落在排除帧内直接 failed，触摸不
///   被 cancelsTouchesInView 吞掉、横滚区自家
///   滚动不受扰（旧 SwiftUI 构造靠同时识别＋回
///   调内忽略，本构造靠不开始）；
/// - 数值判定（起滑/触发/封顶）仍全走 Core
///   SwipeReplyMotion 单源，呈现层状态写回走
///   onPanChanged/onPanEnded 两条回调（修饰符
///   每次 body 求值经 updateUIView 刷新闭包，
///   与 ScrollViewTapDismiss 的 onBlankTap 同式）。
///
/// 换代包 7（0.50.78 真机反馈修复 B，仲裁重做）：
/// 方向判定改位移式方向锁（Core SwipeReplyMo-
/// tion.determineDirection，handlePan 早期消
/// 费累计位移）——起手前约 10pt 位移内按位移
/// 比判方向，横向锁定后立即 1:1 跟手；竖向判死
/// 只针对明确竖向位移（|dy| > |dx|）；仲裁关系
/// 收窄：只保留与滚动的失败依赖（纵滚等横滑）、
/// 去掉等点按/长按的无谓等待（位移锁已足够快，
/// 大厂通行做法）；触发阈值维持 60pt、越线给
/// soft 触觉（带回程 re-arm 迟滞 55pt）。
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

    // MARK: - 方向锁定状态（换代包 7）

    private var directionLocked: SwipeReplyMotion.SwipeDirection = .undetermined
    private var hasTriggeredHaptic = false
    private var currentOffset: CGFloat = 0

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
        // 横滑先失败才开始——横滑的方向门判死发
        // 生在位移判定点（约 10pt 内），纵滚延迟
        // 以点计
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

    // MARK: - 识别器动作（换代包 7 方向锁定重写）

    @objc private func handlePan(
        _ recognizer: UIPanGestureRecognizer
    ) {
        switch recognizer.state {
        case .began:
            // 重置状态
            directionLocked = .undetermined
            hasTriggeredHaptic = false
            currentOffset = 0
            // 开始判定方向
            let translation = recognizer.translation(in: recognizer.view)
            checkAndLockDirection(translation: translation, recognizer: recognizer)

        case .changed:
            let translation = recognizer.translation(in: recognizer.view)

            // 方向未锁定时继续判定
            if directionLocked == .undetermined {
                checkAndLockDirection(translation: translation, recognizer: recognizer)
            }

            // 已锁定为竖向，不处理（识别器已 failed）
            if directionLocked == .vertical {
                return
            }

            // 横向锁定，处理位移并检查触觉
            if directionLocked == .horizontal {
                processPanTranslation(translation.x)
                checkAndTriggerHaptic(translation.x)
            }

        case .ended, .cancelled, .failed:
            processPanEnd()
            directionLocked = .undetermined
            hasTriggeredHaptic = false
            currentOffset = 0

        default:
            break
        }
    }

    /// 方向锁定判定（换代包 7）：累计位移达到
    /// directionLockDistance（10pt）时按位移比判
    /// 方向——横向锁定后开始跟手、竖向判死让滚动
    private func checkAndLockDirection(
        translation: CGPoint,
        recognizer: UIPanGestureRecognizer
    ) {
        let absDx = abs(translation.x)
        let absDy = abs(translation.y)

        // 位移还不够，继续观察
        if max(absDx, absDy) < SwipeReplyMotion.directionLockDistance {
            return
        }

        // 判定方向
        let direction = SwipeReplyMotion.determineDirection(
            translationX: translation.x,
            translationY: translation.y
        )

        if direction == .vertical {
            // 竖向判死，让给滚动
            directionLocked = .vertical
            recognizer.state = .failed
        } else if direction == .horizontal {
            // 横向锁定，开始跟手
            directionLocked = .horizontal
        }
        // .undetermined 继续观察
    }

    /// 触觉反馈检查（换代包 7）：越过触发线
    /// （60pt）时给 soft 触觉、带回程 re-arm 迟
    /// 滞（回拖到 55pt 以下重新武装、防抖）
    private func checkAndTriggerHaptic(_ translationX: CGFloat) {
        let offset = SwipeReplyMotion.dragOffset(
            translationWidth: translationX,
            currentOffset: currentOffset
        )
        currentOffset = offset

        // 越过触发线且未触发过
        if !hasTriggeredHaptic && SwipeReplyMotion.shouldTrigger(offset: offset) {
            hasTriggeredHaptic = true
            let generator = UIImpactFeedbackGenerator(style: .soft)
            generator.impactOccurred()
        }

        // 回程 re-arm：回拖到 rearm 线以下重新武装
        if hasTriggeredHaptic && offset < SwipeReplyMotion.hapticRearmThreshold {
            hasTriggeredHaptic = false
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

    // MARK: - UIGestureRecognizerDelegate（仲裁）

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

    /// 起始点排除门（换代包 7 简化）：起滑点落在
    /// 排除帧（代码块/表格横滚区）内——不许开始
    /// （转 failed、触摸不被吞）。旧速度门已改位
    /// 移式方向锁（handlePan 内消费），本口只留
    /// 排除判定
    override func gestureRecognizerShouldBegin(
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
        return true
    }

    /// 失败依赖收窄（换代包 7）：不再等点按/长按
    /// 识别器——位移式方向锁已足够快（约 10pt 内
    /// 判定），点按/长按与横滑的共存靠方向锁解决
    /// （大厂通行做法，mature-practice-gestures-
    /// topbar-20261122.md 题 2.2①）。只保留与滚
    /// 动的失败依赖（安装时 require(toFail:) 显
    /// 式声明，不经本口）
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf
            otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }

    /// 与任何识别器都不同时识别：成败只走方向锁
    /// 与失败依赖两条明路，不留并行含糊面
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith
            otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }
}
