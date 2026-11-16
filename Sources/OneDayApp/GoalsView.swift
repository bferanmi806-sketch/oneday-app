import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI

/// 目标格（0.11.0 P4 转正；0.33.0 P2 改呈现形态）：列表
/// 照 Muse 目标行实测形态——状态分组（色点组头）＋扁平
/// 行（22pt 方形勾选框＝完成开关、标题、进展摘要、⋮
/// 菜单），里程碑进度条退出列表行、移详情头部；详情改
/// 「呈现页」（简报/里程碑/进展时间线/子目标/状态动作），
/// 编辑收进独立编辑 sheet。桥未连接/未开通如实露、零假
/// 数据；写动作全部走 GoalsStore 的回读确认口径。
/// 创建流（0.40.0 两步：选分类→表单；§238 改三步
/// 终局：选分类→介绍卡→开目标旁聊在对话里聊定，
/// GA-1/GA-2 定版）——空态整页与有目标时的底部创
/// 建区/工具栏共用同一条流（分类组件
/// GoalCategoryRowsView 共用）；表单降为介绍卡上
/// 的次级入口「直接填写」，不删
private enum GoalCreateSheet: Identifiable {
    case categories
    case intro(GoalCategory)
    case form(GoalCategory?)

    var id: String {
        switch self {
        case .categories:
            return "categories"
        case .intro(let category):
            return "intro-\(category.rawValue)"
        case .form(let category):
            return "form-\(category?.rawValue ?? "none")"
        }
    }
}

struct GoalsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var store = GoalsStore()
    @State private var createSheet: GoalCreateSheet?
    @State private var expandedActive = false
    @State private var showCompletedGroup = false
    @State private var expandedCompleted = false
    @State private var editTarget: BridgeGoal?
    @State private var deleteTarget: BridgeGoal?

    var body: some View {
        NavigationStack {
            Group {
                switch store.loadState {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .notConnected(let message):
                    ContentUnavailableView {
                        Label("还没连上你的服务", systemImage: "link.badge.plus")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("重新检查") {
                            Task { await store.load(appState: appState) }
                        }
                        .buttonStyle(.bordered)
                    }
                case .failed(let message):
                    ContentUnavailableView {
                        Label("目标没读出来，可能是网络或服务暂时没响应", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("重试") {
                            Task { await store.load(appState: appState) }
                        }
                        .buttonStyle(.bordered)
                    }
                case .ready:
                    readyContent
                }
            }
            .background {
                Palette.pageBG
                    .ignoresSafeArea()
            }
            .navigationTitle("目标")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        createSheet = .categories
                    } label: {
                        Label("新建目标", systemImage: "plus")
                    }
                }
            }
            .task {
                await store.load(appState: appState)
            }
            .sheet(item: $createSheet) { sheet in
                switch sheet {
                case .categories:
                    GoalCategorySheetView { category in
                        createSheet = .intro(category)
                    }
                case .intro(let category):
                    GoalIntroView(
                        category: category,
                        onStart: { openGoalChat(category) },
                        onForm: { createSheet = .form(category) }
                    )
                case .form(let category):
                    GoalCreateView(
                        store: store, presetCategory: category
                    )
                }
            }
            .sheet(item: $editTarget) { goal in
                GoalEditView(store: store, goalID: goal.id)
            }
            .confirmationDialog(
                "删除这个目标？",
                isPresented: Binding(
                    get: { deleteTarget != nil },
                    set: { if !$0 { deleteTarget = nil } }
                ),
                titleVisibility: .visible,
                presenting: deleteTarget
            ) { goal in
                Button("删除目标", role: .destructive) {
                    Task {
                        _ = await store.delete(
                            appState: appState, goalID: goal.id
                        )
                    }
                }
                Button("取消", role: .cancel) {}
            } message: { _ in
                Text("子目标、进展记录与简报会一并删除。挂在这个目标上的点子会解除关联（点子本身保留）。")
            }
        }
    }

    /// 开目标旁聊（GA-1/GA-2 终局，§238）：新建一条旁
    /// 聊线程（本地出生记录，与点子开旁聊同一条链），
    /// 目标创建引用直写其待发状态（§219 引用道：不代
    /// 发、不写草稿账），切聊天格。目标本体不在这里
    /// 建——在对话里聊定后由智能体经 goals_create 落
    /// 桥（source=chat），回目标页回读列表见它出现才
    /// 算落定，不在此假报已创建
    private func openGoalChat(_ category: GoalCategory) {
        let fresh = ChatThread()
        modelContext.insert(fresh)
        try? modelContext.save()
        appState.pendingSourceQuotesByThread[fresh.id] =
            .goal(GoalQuote(category: category))
        appState.drawerThreadSelection = fresh.id
        appState.mainTabSwitchRequest = .chat
        createSheet = nil
    }

    @ViewBuilder
    private var readyContent: some View {
        if store.goals.isEmpty {
            categoryCreateFlow
        } else {
            let groups = GoalBoard.grouped(store.goals)
            ScrollView {
                LazyVStack(
                    alignment: .leading, spacing: OneDayMetrics.spacingL
                ) {
                    if !groups.active.isEmpty {
                        goalGroup(
                            title: "进行中", completed: false,
                            goals: groups.active,
                            expanded: $expandedActive
                        )
                    }
                    if !groups.completed.isEmpty {
                        completedGroup(goals: groups.completed)
                    }
                    if !store.ungroupedTasks.isEmpty
                        || store.ungroupedNote != nil {
                        ungroupedSection
                    }
                    createArea
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.vertical, OneDayMetrics.spacingM)
            }
            .refreshable {
                await store.load(appState: appState)
            }
            // §170（用户 2026-11-11 23:28 亲定）：底部导
            // 航栏同档收边（与输入框下方收边同档）——本页根 Scroll-
            // View 底缘挂 .hard，口径与映射见 FeedView
            // 同注与 DESIGN §170.2
            // §185 按裁决改 .soft：该边缘内容可流到坞下、.hard 官方定义近乎不透明本身制造色带（solidband 裁决第四节）；§170 的 .hard 口径就此点被 §185 覆盖。
            .scrollEdgeEffectStyle(.soft, for: .bottom)
        }
    }

    /// 无目标态整页＝分类创建流（0.40.0，规格第三章；
    /// §238 改三步终局）：「＋创建目标」标题行＋一句实
    /// 话说明＋七分类行；点一行先出该分类的介绍卡，
    /// 「开始吧」开目标旁聊在对话里聊定（GA-1/GA-2），
    /// 表单是介绍卡上的次级入口。普通空态（「暂无目
    /// 标」＋单个按钮）自 0.40.0 废弃
    private var categoryCreateFlow: some View {
        ScrollView {
            VStack(
                alignment: .leading, spacing: OneDayMetrics.spacingL
            ) {
                VStack(
                    alignment: .leading, spacing: OneDayMetrics.spacingS
                ) {
                    Label("创建目标", systemImage: "plus")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.bodyInk)
                    Text("选一个类别，接下来在对话里把目标聊定。定好之后，它的进展、任务和简报会慢慢长出来。")
                        .font(.body)
                        .foregroundStyle(Palette.inkSecondary)
                }
                GoalCategoryRowsView { category in
                    createSheet = .intro(category)
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.vertical, OneDayMetrics.spacingM)
        }
        .refreshable {
            await store.load(appState: appState)
        }
        // §170：无目标态（分类创建流）与有目标态同为本
        // 格根滚动面，底缘同挂 .hard（口径见 ready-
        // Content 同注）
        // §185 按裁决改 .soft：该边缘内容可流到坞下、.hard 官方定义近乎不透明本身制造色带（solidband 裁决第四节）；§170 的 .hard 口径就此点被 §185 覆盖。
        .scrollEdgeEffectStyle(.soft, for: .bottom)
    }

    /// 状态分组（照 Muse 行形态）：色点组头＋扁平行，
    /// 超过 4 条折叠为「显示另外N项」
    private func goalGroup(
        title: String, completed: Bool, goals: [BridgeGoal],
        expanded: Binding<Bool>
    ) -> some View {
        let folded = GoalBoard.folded(goals, expanded: expanded.wrappedValue)
        return VStack(alignment: .leading, spacing: OneDayMetrics.spacingSM) {
            GoalGroupHeader(title: title, completed: completed)
            ForEach(folded.visible) { goal in
                GoalRowView(
                    store: store,
                    goal: goal,
                    summary: GoalBoard.summary(
                        for: goal, latestEntry: goal.latestEntry
                    ),
                    acting: store.actingIDs.contains(goal.id),
                    onToggleStatus: {
                        Task {
                            _ = await store.setStatus(
                                appState: appState, goalID: goal.id,
                                status: goal.status == .completed
                                    ? .active : .completed
                            )
                        }
                    },
                    onEdit: { editTarget = goal },
                    onDelete: { deleteTarget = goal }
                )
                if let note = store.notes[goal.id] {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if folded.hiddenCount > 0 {
                Button {
                    expanded.wrappedValue = true
                } label: {
                    Label(
                        "显示另外\(folded.hiddenCount)项",
                        systemImage: "ellipsis"
                    )
                    .font(.body)
                    .foregroundStyle(Palette.inkSecondary)
                }
                .buttonStyle(.odPressable)
            }
        }
    }

    /// 已完成组：默认收起，点头展开（组内同样 4 条折叠）
    private func completedGroup(goals: [BridgeGoal]) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingSM) {
            Button {
                showCompletedGroup.toggle()
            } label: {
                HStack(spacing: OneDayMetrics.spacingS) {
                    GoalGroupHeader(
                        title: "已完成", completed: true
                    )
                    Text("\(goals.count)")
                        .font(.body)
                        .foregroundStyle(Palette.inkSecondary)
                    Spacer()
                    Image(systemName: showCompletedGroup
                          ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.inkMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)
            if showCompletedGroup {
                let folded = GoalBoard.folded(
                    goals, expanded: expandedCompleted
                )
                ForEach(folded.visible) { goal in
                    GoalRowView(
                        store: store,
                        goal: goal,
                        summary: GoalBoard.summary(
                            for: goal, latestEntry: goal.latestEntry
                        ),
                        acting: store.actingIDs.contains(goal.id),
                        onToggleStatus: {
                            Task {
                                _ = await store.setStatus(
                                    appState: appState, goalID: goal.id,
                                    status: .active
                                )
                            }
                        },
                        onEdit: { editTarget = goal },
                        onDelete: { deleteTarget = goal }
                    )
                    if let note = store.notes[goal.id] {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(Palette.danger)
                            .frame(
                                maxWidth: .infinity, alignment: .leading
                            )
                    }
                }
                if folded.hiddenCount > 0 {
                    Button {
                        expandedCompleted = true
                    } label: {
                        Label(
                            "显示另外\(folded.hiddenCount)项",
                            systemImage: "ellipsis"
                        )
                        .font(.body)
                        .foregroundStyle(Palette.inkSecondary)
                    }
                    .buttonStyle(.odPressable)
                }
            }
        }
    }

    /// 未归类任务区（GD-2，调和读法）：你在对话里安
    /// 排的、采纳点子时生成的任务，还没归到任何目标
    /// 下的集中在这里，点「归组」选一个目标即可；归
    /// 组后它的进展会记到那个目标里。纯系统/定时任
    /// 务不在此面（归台账）。此区只呈现＋用户点归，
    /// 系统不自动归组【归类口径：2026-11-14 19:05
    /// 用户拍板，按审计提案落码视同已追认】
    private var ungroupedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("未归类任务")
                .padding(.bottom, OneDayMetrics.spacingXS)
            Text("在对话里安排的、采纳点子时生成的任务，还没归到目标下。归组后，它的进展会记到那个目标里。")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                ForEach(store.ungroupedTasks, id: \.taskId) { row in
                    if row.taskId
                        != store.ungroupedTasks.first?.taskId {
                        GroupDivider()
                    }
                    UngroupedTaskRowView(
                        row: row,
                        detail: ungroupedRowDetail(row),
                        targets: store.goals.filter {
                            $0.status == .active
                        }
                    ) { goalID in
                        Task {
                            await store.assignUngroupedTask(
                                appState: appState,
                                taskID: row.taskId,
                                toGoalID: goalID
                            )
                        }
                    }
                }
            }
            if let note = store.ungroupedNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
                    .padding(.top, OneDayMetrics.spacingS)
            }
        }
    }

    /// 未归类行小字：状态（桥给的原生状态经既有状态
    /// 呈现解析）＋来源；状态缺失时只给来源，不编
    private func ungroupedRowDetail(
        _ row: BridgeUngroupedTask
    ) -> String {
        let origin = UngroupedTaskPresentation.originLabel(row.origin)
        guard let status = row.status else { return origin }
        let label = KanbanStatusPresentation.resolve(
            status: status, blockKind: nil, lastFailureError: nil
        ).label
        return "\(label) · \(origin)"
    }

    /// 列表底常驻创建区（照 Muse 目标页图位置）：分隔线
    /// 下「＋ 创建目标」＋一句说明；点入先出分类选择（与
    /// 空态同一分类组件），选完出介绍卡（§238 三步流）
    private var createArea: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            Divider()
            Button {
                createSheet = .categories
            } label: {
                Label("创建目标", systemImage: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.bodyInk)
            }
            .buttonStyle(.odPressable)
            Text("先选一个类别，再到对话里把目标聊定。定好之后它会出现在这里，进展和简报会慢慢长出来。")
                .font(.body)
                .foregroundStyle(Palette.inkSecondary)
        }
        .padding(.top, OneDayMetrics.spacingS)
    }
}

