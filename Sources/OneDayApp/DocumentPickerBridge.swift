import os
import UIKit
import UniformTypeIdentifiers

/// 文件选择 UIKit 桥（0.36.31 件二换桥）：聊天页
/// 「选文件」不再走 SwiftUI `.fileImporter`——它在
/// 侧载设备类（万能签／TrollStore／Sideloadly 同
/// 类）上点「打开」毫无反应：picker 被呈现在正被
/// 拆毁的 SwiftUI 呈现上下文上、coordinator 已
/// 死、delegate 永不触发（不关闭、无结果、无报
/// 错；外部同形生产实证 LunWhale/minis-open 提交
/// e13e4b1 逐字定案，本仓诊断 file-picker-batch-
/// diagnosis-20261111）。本桥照公认修法形态：
/// UIDocumentPickerViewController 自当前最顶层
/// VC 呈现、绕开 SwiftUI coordinator；coordina-
/// tor 静态强持有到 picker 关闭；回调先 dismiss
/// 再把 URL 数组交回业务层（ChatView.loadPick-
/// edFiles）。asCopy: true——系统先把所选文件拷
/// 进 App 临时区再交 URL，副本在本 App 容器内、
/// 读取无需安全作用域（旧 .fileImporter 路的安
/// 全作用域起停配对随之退役）；多选保留、类型
/// [.item] 不变。
///
/// §317（2026-11-17 热修，诊断 attach-norespon-
/// se-diagnosis-20261117）：呈现时机整段换代——
/// 旧形态靠调用方固定睡 450ms 猜 sheet 收起完成，
/// iOS 26 收起时长非常量，收起未完时对 dismis-
/// sing 中的 VC 调 present 被 UIKit 静默丢弃
/// （面板收了、选择器永不来、无声）。新形态：
/// 调用方改走 sheet onDismiss 完成信号（见
/// ChatView.afterAttachPanelDismiss），本桥再设
/// 第二道门——present 前实查呈现者状态（在窗、
/// 不在呈现/收起过渡中），未就绪按固定间隔重
/// 试、有上限，超限走 onFailure 给人话提示，
/// 不许静默。全出口（取空/被拒/已呈现/选定/取
/// 消）落 ChatDiagTrace，终结本桥无声失败史。
enum DocumentPickerBridge {

    /// coordinator 静态强持有：picker 的 delegate
    /// 是弱引用，present 返回后若无人持有 coordi-
    /// nator，回调永远不会来——持有到选定/取消为
    /// 止，关闭时在回调里释放
    private static let coordinatorBox =
        OSAllocatedUnfairLock<Coordinator?>(initialState: nil)

    private static let log = Logger(
        subsystem: "site.didichou.oneday",
        category: "docpicker"
    )

    /// 呈现重试口径（§317）：呈现者未就绪时每
    /// 150ms 复查一次，最多 12 次（含首次）——覆
    /// 盖面 ≈1.65s，远超 sheet 收起时长量级；超
    /// 限即放弃并走 onFailure，不无限等、不静默
    static let presentMaxAttempts = 12
    static let presentRetryIntervalNs: UInt64 = 150_000_000

    /// 呈现者就绪快照（值型）：判定纯函数化，供
    /// 生产走查与时序单测共用同一口径
    struct Snapshot: Equatable {
        var hasPresenter: Bool
        var inWindow: Bool
        var isBeingDismissed: Bool
        var isBeingPresented: Bool
        var hasActiveTransition: Bool

        /// 就绪＝有呈现者、在窗、且不在任何呈现/
        /// 收起过渡中（对过渡中的 VC 调 present
        /// 会被 UIKit 静默丢弃，§317 病灶本体）
        var isReady: Bool {
            hasPresenter && inWindow
                && !isBeingDismissed && !isBeingPresented
                && !hasActiveTransition
        }

        /// 未就绪原因（日志与放弃回执用，人话短句）
        var blockedReason: String {
            if !hasPresenter { return "无呈现者" }
            if isBeingDismissed { return "呈现者收起中" }
            if isBeingPresented { return "呈现者呈现中" }
            if hasActiveTransition { return "呈现者过渡中" }
            if !inWindow { return "呈现者不在窗口" }
            return "已就绪"
        }
    }

    @MainActor
    static func snapshot(of presenter: UIViewController?)
        -> Snapshot
    {
        Snapshot(
            hasPresenter: presenter != nil,
            inWindow: presenter?.viewIfLoaded?.window != nil,
            isBeingDismissed: presenter?.isBeingDismissed
                ?? false,
            isBeingPresented: presenter?.isBeingPresented
                ?? false,
            hasActiveTransition:
                presenter?.transitionCoordinator != nil
        )
    }

    @MainActor
    static func present(
        allowsMultipleSelection: Bool = true,
        onPick: @escaping ([URL]) -> Void,
        onFailure: (() -> Void)? = nil
    ) {
        // 延一拍起步：等触发它的 Menu/面板收起信号
        // 落定再进呈现驱动（minis-open 的 Deferred-
        // Presentation 同口径）；真正的收起完成判
        // 定在驱动内实查呈现者状态，不再靠睡时长猜
        Task { @MainActor in
            await drivePresentation(
                resolve: {
                    let presenter = topmostViewController()
                    return (snapshot(of: presenter), presenter)
                },
                present: { presenter, attempt in
                    presentPicker(
                        from: presenter,
                        allowsMultipleSelection:
                            allowsMultipleSelection,
                        attempt: attempt,
                        onPick: onPick
                    )
                },
                onGiveUp: { _ in onFailure?() },
                sleep: { ns in
                    try? await Task.sleep(nanoseconds: ns)
                }
            )
        }
    }

    /// 呈现驱动（§317 本体，可测缝）：循环实查呈
    /// 现者快照——就绪即呈现并返回；未就绪且未达
    /// 上限则睡一档重试；达上限落放弃留痕并回调
    /// onGiveUp。收起未完的 present 自此不会被发
    /// 出（旧症：发出即被 UIKit 静默丢弃）
    @MainActor
    static func drivePresentation(
        maxAttempts: Int = presentMaxAttempts,
        retryIntervalNs: UInt64 = presentRetryIntervalNs,
        resolve: () -> (snapshot: Snapshot,
                        presenter: UIViewController?),
        present: (UIViewController, Int) -> Void,
        onGiveUp: (String) -> Void,
        sleep: (UInt64) async -> Void
    ) async {
        var attempt = 0
        while true {
            attempt += 1
            let (snapshot, presenter) = resolve()
            if snapshot.isReady, let presenter {
                present(presenter, attempt)
                return
            }
            if attempt >= maxAttempts {
                // 放弃出口（取空与被拒同归此处，原因
                // 字段分晓）：留痕＋人话提示回调，不
                // 许静默（P3 的静默 return 就此消灭）
                ChatDiagTrace.record(
                    "docpicker 呈现放弃：\(snapshot.blockedReason)"
                        + "（已试 \(attempt) 次）"
                )
                onGiveUp(snapshot.blockedReason)
                return
            }
            log.info(
                "docpicker 呈现延后：第 \(attempt) 次，\(snapshot.blockedReason, privacy: .public)"
            )
            await sleep(retryIntervalNs)
        }
    }

    @MainActor
    private static func presentPicker(
        from presenter: UIViewController,
        allowsMultipleSelection: Bool,
        attempt: Int,
        onPick: @escaping ([URL]) -> Void
    ) {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.item], asCopy: true
        )
        picker.allowsMultipleSelection =
            allowsMultipleSelection
        let coordinator = Coordinator(onPick: onPick)
        picker.delegate = coordinator
        coordinatorBox.withLock { $0 = coordinator }
        presenter.present(picker, animated: true) {
            ChatDiagTrace.record(
                "docpicker 已呈现（第 \(attempt) 次尝试）"
            )
        }
    }

    /// 沿 presentedViewController 链走到当前最顶层
    /// VC（干净的呈现上下文，不借道任何 SwiftUI
    /// 呈现修饰符的宿主）
    @MainActor
    private static func topmostViewController()
        -> UIViewController?
    {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        let keyWindow = windows.first { $0.isKeyWindow }
            ?? windows.first
        var controller = keyWindow?.rootViewController
        while let presented =
            controller?.presentedViewController
        {
            controller = presented
        }
        return controller
    }

    private static func releaseCoordinator() {
        coordinatorBox.withLock { $0 = nil }
    }

    private final class Coordinator: NSObject,
        UIDocumentPickerDelegate
    {
        private let onPick: ([URL]) -> Void

        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            ChatDiagTrace.record(
                "docpicker 已选定 \(urls.count) 个文件"
            )
            // 先 dismiss 再交回：业务层随后的状态变
            // 更（附件入条）不与 picker 收起同帧打架
            controller.dismiss(animated: true)
            DocumentPickerBridge.releaseCoordinator()
            onPick(urls)
        }

        func documentPickerWasCancelled(
            _ controller: UIDocumentPickerViewController
        ) {
            // 用户主动取消不打扰用户，但留痕归档
            // （§317 全出口留痕口径，取消非失败）
            ChatDiagTrace.record("docpicker 用户取消")
            DocumentPickerBridge.releaseCoordinator()
        }
    }
}
