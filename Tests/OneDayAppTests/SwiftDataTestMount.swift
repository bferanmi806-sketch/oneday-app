import Foundation
import SwiftData

/// §184 测试宿主 SwiftData 致命崩溃专项（2026-11-15）：装配层容器租约。
///
/// 定因（七 run 共因，见 swiftdata-host-crash-fix-20261115.md）：
/// 挂载生产页（RootView／ChatView／DrawerView）的测试类把
/// ModelContainer 只存在方法局部变量里——方法一返回容器即失
/// 去强持有，而挂载树（UIHostingController＋@Query 订阅＋在途
/// .task／通知观察者）还活着。SwiftData 在容器上下文失效时
/// reset，树里残留的观察者／在途任务再碰 ChatThread 即
/// BackingData.swift:835 致命崩溃（"This model instance was
/// destroyed by calling ModelContext.reset"），宿主重启、长测
/// 无终局。跨容器 save 是同一链的另一触发器（§184 配方：
/// 同进程多次整页装配＋异容器 save 必杀——KeyboardFlow-
/// AcceptanceTests 文件头在案）。
///
/// 规则（只约束测试装配层，生产行为零改动）：
/// 1. 挂载即 retain——容器强持有到 tearDown，不许只存方法局部；
/// 2. 释放顺序——先拆窗（window.rootViewController＝nil），再
///    await release()（0.6s 悬停排空在途更新／通知投递／任务
///    取消，此时容器仍活、任何残留访问都落在有效上下文上），
///    最后才放容器；
/// 3. 顺序反了（容器先于挂载树释放）即复现 §184。
/// 适用面：生产页挂载类（组装回归／设备条件探针／断网可靠性／
/// 边缘探针／键盘验收／键盘诊断／讨论引用复现／抽屉桥 harness）。
/// 不适用：不挂载生产页的纯替身壳（ComposerGuideHost／EdgeEffect-
/// Registration／TopBarHitIntermittent 等）与空容器壳（TabBarFloat／
/// HubSegments）——容器里不存在 ChatThread 实例、无从销毁，见报告 §六。
@MainActor
final class SwiftDataTestMount {
    private var container: ModelContainer?

    func retain(_ container: ModelContainer) {
        self.container = container
    }

    var isRetained: Bool { container != nil }

    /// 排空后释放：调用方须已拆窗。未 retain 时直接返回、不悬停。
    func release() async {
        guard container != nil else { return }
        try? await Task.sleep(nanoseconds: 600_000_000)
        container = nil
    }
}
