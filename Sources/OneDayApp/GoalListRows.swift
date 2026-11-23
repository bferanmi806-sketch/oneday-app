import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI

/// A-11 结构拆分（2026-11-16）：自 GoalsView.swift 按职责拆出（列表行与共享行件），零行为变更（DESIGN §311）；goalActivityDotColor 因详情页跨文件共用去掉 private（可见性修饰），余逐字未改。

/// 未归类任务行（GD-2）：标题＋状态/来源小字＋右端
/// 「归组」菜单（选进行中目标即归组，动作经 onAssign
/// 回到列表页的 Store 调用）。独立成 View 与列表页
/// 解耦（同 GoalRowView 的拆分先例）
struct UngroupedTaskRowView: View {
    let row: BridgeUngroupedTask
    let detail: String
    let targets: [BridgeGoal]
    let onAssign: (String) -> Void

    var body: some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Image(systemName: "checklist")
                .font(.body)
                .foregroundStyle(Palette.inkSecondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.body)
                    .foregroundStyle(Palette.bodyInk)
                    .lineLimit(2)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                ForEach(targets, id: \.id) { goal in
                    Button(goal.title) {
                        onAssign(goal.id)
                    }
                }
            } label: {
                Text("归组")
                    .font(.body)
                    .foregroundStyle(Palette.primary)
            }
        }
        .padding(.vertical, OneDayMetrics.spacingSM)
    }
}

/// 分类七行（0.40.0）：图标＋类名＋右端「＋」，空态整页
/// 与分类选择 sheet 共用同一组件（规格第三章：同一分类
/// 组件两处复用）。图标走 SF Symbols 同语义位（宪法
/// §4），不仿绘参照图的 3D/字形原图
struct GoalCategoryRowsView: View {
    var onPick: (GoalCategory) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(
                Array(GoalCategory.creationOrder.enumerated()),
                id: \.element
            ) { index, category in
                if index > 0 {
                    GroupDivider()
                }
                Button {
                    onPick(category)
                } label: {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        Image(systemName: category.symbolName)
                            .font(.body)
                            .foregroundStyle(Palette.inkSecondary)
                            .frame(width: 24)
                        Text(category.title)
                            .font(.body)
                            .foregroundStyle(Palette.bodyInk)
                        Spacer()
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.inkMuted)
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .padding(.vertical, OneDayMetrics.spacingSM)
                }
                .buttonStyle(.odPressable)
            }
        }
        .odGroup()
    }
}

/// 分类选择 sheet（有目标时从底部创建区/工具栏进入）：
/// 选完把分类交给上层换成介绍卡（同一个 sheet 内换
/// 内容，不叠第二层 sheet；§238 前是换新建表单）
struct GoalCategorySheetView: View {
    @Environment(\.dismiss) private var dismiss
    var onPick: (GoalCategory) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(
                    alignment: .leading, spacing: OneDayMetrics.spacingL
                ) {
                    Text("选一个类别，接下来在对话里把目标聊定。")
                        .font(.body)
                        .foregroundStyle(Palette.inkSecondary)
                    GoalCategoryRowsView(onPick: onPick)
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.top, OneDayMetrics.spacingM)
                .padding(.bottom, OneDayMetrics.spacingXL)
            }
            .background(Palette.pageBG)
            .navigationTitle("创建目标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

/// 分类介绍卡（GA-1，§238）：点分类后的第二步——
/// 分类图标＋「创建X目标」题＋介绍文（Core introLead
/// 首句＋流程说明两句），说清这一类会怎么聊定、定
/// 好之后长在哪里。主钮「开始吧」＝开目标旁聊在对
/// 话里聊定（GA-2 终局：目标由智能体在对话里经
/// goals_create 落桥、source=chat）；次级入口
/// 「直接填写」走现行表单（不会聊的用户有退路，
/// 规格 GA-1 定版——表单不删、只降次级）
struct GoalIntroView: View {
    @Environment(\.dismiss) private var dismiss
    let category: GoalCategory
    var onStart: () -> Void
    var onForm: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(
                    alignment: .leading, spacing: OneDayMetrics.spacingL
                ) {
                    VStack(
                        alignment: .leading,
                        spacing: OneDayMetrics.spacingS
                    ) {
                        Image(systemName: category.symbolName)
                            .font(.title)
                            .foregroundStyle(Palette.primary)
                            .frame(width: 52, height: 52)
                            .background(
                                Palette.fieldFill,
                                in: Circle()
                            )
                        Text("创建\(category.title)目标")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Palette.bodyInk)
                        Text(category.introLead)
                            .font(.body)
                            .foregroundStyle(Palette.bodyInk)
                        Text("点「开始吧」会打开一条新对话，在对话里把这个目标聊定——想达成什么、怎么衡量、拆成哪些里程碑。聊定之后，目标会出现在这里，它的进展、任务和简报会慢慢长出来。")
                            .font(.body)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    VStack(spacing: OneDayMetrics.spacingS) {
                        Button {
                            onStart()
                        } label: {
                            Text("开始吧")
                                .font(.headline)
                                // 第 85 条（BC-1）：主钮改走
                                // primaryPale＋onPrimary 正道
                                // （旧白字压 primary 暗档 2.33）
                                .foregroundStyle(Palette.onPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(
                                    Palette.primaryPale, in: Capsule()
                                )
                        }
                        .buttonStyle(.odPressable)
                        Button {
                            onForm()
                        } label: {
                            Text("直接填写")
                                .font(.body)
                                .foregroundStyle(Palette.inkSecondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                        .buttonStyle(.odPressable)
                    }
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.top, OneDayMetrics.spacingM)
                .padding(.bottom, OneDayMetrics.spacingXL)
            }
            .background(Palette.pageBG)
            .navigationTitle("创建目标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

/// 分组头：浅色圆底＋状态点＋组名（进行中绿系、已完成
/// 灰系——已完成形态图上未见，色口径为推定，照设计档
/// §2.4 登记）
struct GoalGroupHeader: View {
    let title: String
    let completed: Bool

    var body: some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            ZStack {
                Circle()
                    .fill(completed ? Palette.surface : Palette.tintGreen)
                    .frame(width: 17, height: 17)
                Circle()
                    .fill(completed ? Palette.inkMuted : Palette.success)
                    .frame(width: 6.5, height: 6.5)
            }
            Text(title)
                // §364（台账 23）：组头改 semibold
                // （对位 Muse 实测半粗）——组头非
                // 行题、不撞 C14 行题单轨
                .font(.body.weight(.semibold))
                .foregroundStyle(
                    completed ? Palette.inkSecondary : Palette.successText
                )
        }
    }
}

/// 目标方形勾选框（22pt，照 Muse 行实测）：即状态开关
/// ——点框标完成/重开，走 PATCH 回读口径（调用方负责）
struct GoalCheckBox: View {
    let done: Bool
    var onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            ZStack {
                RoundedRectangle(cornerRadius: OneDayMetrics.radiusCheckbox, style: .continuous)
                    .fill(done ? Palette.ink : Color.clear)
                RoundedRectangle(cornerRadius: OneDayMetrics.radiusCheckbox, style: .continuous)
                    .strokeBorder(
                        done ? Color.clear : Palette.hairline,
                        lineWidth: 1.5
                    )
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            // 命中域 44×44（视觉框 22 不变）：-11 内
            // 边距抵消额外命中域、不改行布局
            // （0.36.0，无障碍 A11Y-V1/T1）
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .padding(-11)
        }
        .buttonStyle(.odPressable)
        // 开关语义（A11Y-V5）：动作标签＋状态值，
        // VoiceOver 能读出「这是什么开关、现在什么
        // 状态」，不再是无标签裸按钮
        .accessibilityLabel(done ? "重新打开目标" : "标记目标完成")
        .accessibilityValue(done ? "已完成" : "未完成")
        // 触感矩阵（0.36.2，规格 §2.3/§2.5）：勾选
        // 完成＝notification success；只在 未完成→
        // 完成 边沿响（done 是回读确认后的真状态，
        // 响在落定刻）；取消勾选不对称、不加
        .sensoryFeedback(.success, trigger: done) { old, new in
            !old && new
        }
    }
}

/// 目标扁平行：勾选框（状态开关）＋标题/进展摘要（点进
/// 详情）＋⋮ 菜单（编辑/状态/删除收进菜单，照设计档）
/// 活动状态点色（GD-1 呈现）：正在办＝主色、卡住
/// 了＝危险色、等着/闲置＝弱灰（与组头状态点同语
/// 义：色只表状态、不作装饰）
func goalActivityDotColor(
    _ state: GoalActivityState
) -> Color {
    switch state {
    case .running: return Palette.primary
    case .blocked: return Palette.danger
    case .waiting, .idle: return Palette.inkMuted
    }
}

struct GoalRowView: View {
    let store: GoalsStore
    let goal: BridgeGoal
    let summary: String
    let acting: Bool
    var onToggleStatus: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingSM) {
            GoalCheckBox(done: goal.status == .completed) {
                onToggleStatus()
            }
            .disabled(acting)
            .padding(.top, OneDayMetrics.spacingMicro)
            NavigationLink {
                GoalDetailView(store: store, goalID: goal.id)
            } label: {
                VStack(alignment: .leading, spacing: OneDayMetrics.stackGap) {
                    Text(goal.title)
                        // §364（台账 23，用户 2026-11-22
                        // 裁定）：行题同点子/动态例，改用
                        // contentListTitle（Title3 档
                        // semibold），破 C14 单轨——对位
                        // Muse 实测约 21pt semibold
                        .font(.contentListTitle)
                        .foregroundStyle(Palette.bodyInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !summary.isEmpty {
                        Text(summary)
                            .font(.body)
                            .foregroundStyle(Palette.inkSecondary)
                            // §364：截断 2→3 行（对位 Muse 2–3 行）
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                    // 活动行（GD-1 呈现，§238）：桥派生
                    // 的关联任务活动——状态点＋label 一
                    // 行（照 Linear 名单行 health 信号
                    // 的摆法：小状态信号＋最近进展）。
                    // 只对进行中目标且真有关联任务时
                    // 显；无关联/旧桥无 activity 时整行
                    // 不出，不拿别的数据脑补
                    if goal.status == .active,
                       let activity = goal.activity,
                       activity.linkedCount > 0 {
                        HStack(
                            spacing: OneDayMetrics.spacingMicro
                        ) {
                            Circle()
                                .fill(
                                    goalActivityDotColor(
                                        activity.state
                                    )
                                )
                                .frame(width: 7, height: 7)
                            Text(activity.label)
                                .font(.footnote)
                                .foregroundStyle(
                                    Palette.inkSecondary
                                )
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)
            Menu {
                Button {
                    onEdit()
                } label: {
                    Label("编辑目标", systemImage: "pencil")
                }
                Button {
                    onToggleStatus()
                } label: {
                    Label(
                        goal.status == .completed ? "重新打开" : "标为完成",
                        systemImage: goal.status == .completed
                            ? "arrow.uturn.backward" : "checkmark.circle"
                    )
                }
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("删除目标", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.inkMuted)
                    .rotationEffect(.degrees(90))
                    .frame(
                        width: OneDayMetrics.minTapTarget,
                        height: OneDayMetrics.minTapTarget
                    )
                    .contentShape(Rectangle())
            }
            // 0.43.0（A11Y-V6）：⋮ 菜单钮补标签（文件
            // 行同钮已有「更多操作」先例，此处对齐）
            .accessibilityLabel("更多操作")
            .disabled(acting)
        }
    }

}
