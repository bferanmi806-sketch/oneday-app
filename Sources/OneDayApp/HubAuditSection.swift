import OneDayCore
import OneDayDesign
import SwiftUI

/// 枢纽页审核段（§434 新格，对位参照大头态盾格）：
/// 授权账本＋审批记录——数据全走真回读：授权清单
/// ＝GET /v1/grants（能力 #12，exec 命令授权＋写闸
/// 规则只读投影两源拼合，AgentHubStore.loadGrants
/// 承接）；审批记录＝写闸决定账（decisionHistory，
/// 与待批同轮拉取）＋本进程就地裁决结果行。exec
/// 授权可在此撤销（POST /v1/grants/revoke，终局以
/// 回读为准）；写闸规则的撤销仍归设置·权限区既有
/// 规则面，本段只读呈现、不新造写路。待审批的裁
/// 决仍只在聊天界面（§155 口径不变），本段只给计
/// 数与去处。§482 起段末增「审批规则」入口（规则
/// 页自设置迁回本段，改判 §244）。
struct HubAuditSection: View {
    let hubStore: AgentHubStore

    var body: some View {
        List {
            pendingSection
            grantsSection
            recordsSection
            rulesSection
        }
        .listStyle(.plain)
        .task {
            await hubStore.loadGrants()
        }
    }

    // MARK: - 待审批（只计数，裁决在聊天）

    @ViewBuilder
    private var pendingSection: some View {
        if case .ready(let records) = hubStore.approvalState,
           !records.isEmpty {
            Section {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    iconBox(
                        systemImage: "hourglass",
                        tint: Palette.warning
                    )
                    VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                        Text("\(records.count) 条待审批")
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                        Text("在对话里处理")
                            .font(.subheadline)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                .listRowSeparator(.hidden)
                .listRowInsets(rowInsets)
            }
        }
    }

    // MARK: - 授权账本

    @ViewBuilder
    private var grantsSection: some View {
        Section {
            switch hubStore.grantsState {
            case .loading:
                ProgressView()
                    .listRowSeparator(.hidden)
                    .listRowInsets(rowInsets)
            case .unavailable:
                quietRow("授权清单没读出来，可能是网络或服务暂时没响应")
            case .ready(let response):
                if response.partial {
                    quietRow("有一边没读全，下面的清单可能不完整")
                }
                if let note = hubStore.grantsNote {
                    quietRow(note)
                }
                if response.grants.isEmpty {
                    quietRow("暂无授权记录")
                } else {
                    ForEach(response.grants) { entry in
                        grantRow(entry)
                    }
                }
            }
        } header: {
            Text("授权清单")
        }
    }

    private func grantRow(_ entry: GrantEntry) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            iconBox(
                systemImage: entry.source == .exec
                    ? "terminal" : "checkmark.shield",
                tint: Palette.inkSecondary
            )
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                Text(entry.scopeLabel)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                Text(grantMeta(entry))
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            if entry.source == .exec {
                Button("撤销") {
                    Task { await hubStore.revokeGrant(entry) }
                }
                .font(.subheadline)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(
                    hubStore.revokingGrantKeys.contains(entry.grantKey)
                )
            }
        }
        .listRowSeparator(.hidden)
        .listRowInsets(rowInsets)
        .padding(.vertical, OneDayMetrics.spacingXS)
    }

    private func grantMeta(_ entry: GrantEntry) -> String {
        let sourceWord = entry.source == .exec
            ? L10n.string("命令授权") : L10n.string("写闸规则")
        guard let grantedAt = entry.grantedAt else { return sourceWord }
        return sourceWord + " · "
            + Self.relativeFormatter.localizedString(
                for: grantedAt, relativeTo: Date()
            )
    }

    // MARK: - 审批记录

    @ViewBuilder
    private var recordsSection: some View {
        Section {
            if hubStore.resolvedLines.isEmpty,
               hubStore.decisionHistory.isEmpty {
                quietRow("暂无审批记录")
            } else {
                ForEach(hubStore.resolvedLines) { line in
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        iconBox(
                            systemImage: line.outcome.isPositive
                                ? "checkmark" : "xmark",
                            tint: line.outcome.isPositive
                                ? Palette.success : Palette.danger
                        )
                        VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                            Text(line.summary)
                                .font(.body)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(2)
                            Text(line.outcome.label)
                                .font(.subheadline)
                                .foregroundStyle(Palette.inkSecondary)
                                .lineLimit(1)
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(rowInsets)
                    .padding(.vertical, OneDayMetrics.spacingXS)
                }
                ForEach(hubStore.decisionHistory) { record in
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        iconBox(
                            systemImage: record.decision == "approved"
                                ? "checkmark" : "xmark",
                            tint: record.decision == "approved"
                                ? Palette.success : Palette.danger
                        )
                        VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                            Text(record.summary)
                                .font(.body)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(2)
                            Text(recordMeta(record))
                                .font(.subheadline)
                                .foregroundStyle(Palette.inkSecondary)
                                .lineLimit(1)
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(rowInsets)
                    .padding(.vertical, OneDayMetrics.spacingXS)
                }
            }
        } header: {
            Text("审批记录")
        }
    }

    private func recordMeta(_ record: WriteGateDecisionRecord) -> String {
        var parts: [String] = [
            record.decision == "approved"
                ? L10n.string("已批准") : L10n.string("已驳回")
        ]
        if record.viaRule != nil {
            parts[0] = L10n.string("已按规则放行")
        }
        if let decidedAt = record.decidedAt {
            parts.append(
                Self.relativeFormatter.localizedString(
                    for: decidedAt, relativeTo: Date()
                )
            )
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - 审批规则（§482 迁入，与账本/记录同家）

    /// 审批规则入口：规则页本体 ApprovalRules-
    /// SettingsView（§244 曾归设置页，§482 改判迁
    /// 回本段直推）；页内含「总是允许」规则撤销、
    /// 命令授权与写入审批状态
    private var rulesSection: some View {
        Section {
            NavigationLink {
                ApprovalRulesSettingsView()
            } label: {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    iconBox(
                        systemImage: "checkmark.shield",
                        tint: Palette.inkSecondary
                    )
                    VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                        Text("审批规则")
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                        Text("「总是允许」规则、命令授权与写入审批")
                            .font(.subheadline)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                    }
                }
                .listRowSeparator(.hidden)
                .listRowInsets(rowInsets)
                .padding(.vertical, OneDayMetrics.spacingXS)
            }
        } header: {
            Text("审批规则")
        }
    }

    // MARK: - 共用件

    private func quietRow(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(Palette.inkSecondary)
            .listRowSeparator(.hidden)
            .listRowInsets(rowInsets)
    }

    /// 行左图标盒（§434 行解剖对位：40pt 圆角方＋
    /// 状态字形，与工作行同型）
    private func iconBox(systemImage: String, tint: Color) -> some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: OneDayMetrics.radiusThumb
            )
            .fill(Palette.fillSecondary)
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(tint)
        }
        .frame(width: 40, height: 40)
    }

    private var rowInsets: EdgeInsets {
        EdgeInsets(
            top: OneDayMetrics.spacingXS,
            leading: OneDayMetrics.pageGutter,
            bottom: OneDayMetrics.spacingXS,
            trailing: OneDayMetrics.pageGutter
        )
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
