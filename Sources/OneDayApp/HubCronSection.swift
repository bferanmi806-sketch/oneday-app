import OneDayCore
import OneDayDesign
import SwiftUI

/// 枢纽页定时段（规格 §3.4）：只读概览——提醒/每日/
/// 时间间隔（＋其他周期兜底组），点行跳 CronJobsView
/// 管理；本段不放新建/删除/启停。行型走共用
/// CronOverviewRow（提醒/每日日历方片＋琥珀角标 L5、
/// 间隔时钟圆盘）。
/// 数据（台账 198 收敛·普查 R4/D2 追加条）：全走
/// 共享 CronStore——与正主 CronJobsView、状态页摘
/// 录同一份取数与缓存；此前本段经 AgentHubStore 私
/// 拉一份（jobsCache/runsCache），自此退役。分组/
/// 排序/间隔人话由 Core CronHubClassifier 派生。
struct HubCronSection: View {
    let appState: AppState

    private var store: CronStore { appState.sharedCronStore() }

    var body: some View {
        Group {
            if !store.hasLoaded, store.loadFailed {
                ContentUnavailableView {
                    Label("定时任务没读出来，可能是网络或服务暂时没响应", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("请稍后再试。")
                } actions: {
                    Button("重试") {
                        Task { await store.refresh() }
                    }
                    .buttonStyle(.bordered)
                }
            } else if store.hasLoaded {
                if store.hubGroups.isEmpty {
                    ContentUnavailableView(
                        "暂无定时任务",
                        systemImage: "clock",
                        description: Text("还没有建过定时任务")
                    )
                } else {
                    List {
                        ForEach(store.hubGroups, id: \.kind) { group in
                            Section(group.kind.groupTitle) {
                                ForEach(group.items) { item in
                                    NavigationLink {
                                        CronJobsView()
                                    } label: {
                                        CronOverviewRow(item: item)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await store.loadIfNeeded()
            await store.loadLastRunsIfNeeded()
        }
    }
}
