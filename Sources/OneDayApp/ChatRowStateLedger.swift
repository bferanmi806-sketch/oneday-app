import Foundation
import OneDayCore

/// 行状态账本（§329）：聊天行内「影响行高、却只活在
/// 视图 @State 里」的状态统一上提到 ChatView 持有——
/// 行高改 .absolute 回喂后，合成器必须看得见每一份
/// 影响高度的状态，否则合成高与呈现高必然分叉。本
/// 账本只收两类：①展开覆盖（ReasoningBlock／工具
/// 卡／工具组的展开态——相位默认仍由各视图按既有
/// 口径现算，账本只存用户点按覆盖值）；②审批详情
/// 四态（展开/加载中/详情本体/错误文案——详情数据
/// 本就来自 AgentHubStore 的 loadDetail，落账后合成
/// 器可按同一份详情算高）。
///
/// 纪律：键由 ChatRowStateKeys 单点派生（视图侧与合
/// 成侧同源、不许各拼一份）；无账本环境（其他表面
/// 复用同视图时不传）视图回落本地 @State、行为逐字
/// 不变；账本变更经 @Observable 触发 ChatView 重渲
/// →nativeRows 重合成→apply 落写新高，与 §329 的
/// 单一数据源口径同路。
@MainActor
@Observable
final class ChatRowStateLedger {
    /// 展开覆盖：键→用户点按定下的展开值；无键＝跟
    /// 视图相位默认（ReasoningBlock）或收起（工具卡）
    private(set) var expansionOverrides: [String: Bool] = [:]
    /// 审批详情四态：记录 id→状态
    private(set) var approvalDetails: [String: ApprovalDetailState] = [:]

    func expansionOverride(for key: String) -> Bool? {
        expansionOverrides[key]
    }

    func setExpansion(_ expanded: Bool, for key: String) {
        expansionOverrides[key] = expanded
    }

    func approvalDetail(for recordID: String) -> ApprovalDetailState {
        approvalDetails[recordID] ?? ApprovalDetailState()
    }

    func updateApprovalDetail(
        _ recordID: String,
        _ mutate: (inout ApprovalDetailState) -> Void
    ) {
        var state = approvalDetails[recordID] ?? ApprovalDetailState()
        mutate(&state)
        approvalDetails[recordID] = state
    }
}

/// 审批详情四态（§329）：与 ChatApprovalCard 旧
/// @State 四件（detailExpanded/detail/detailError/
/// detailLoading）一一对应、整组搬运，语义不变
struct ApprovalDetailState {
    var expanded = false
    var detail: WriteGateDetail?
    var error: String?
    var loading = false
}

/// 行状态键单点派生（§329）：视图构造点与高度合
/// 成点共用本表——键形态只此一处出处
enum ChatRowStateKeys {
    static func reasoningEntry(_ entryID: UUID) -> String {
        "reasoning-entry-\(entryID.uuidString)"
    }

    static let liveReasoning = "reasoning-live"

    static func toolEntry(_ entryID: UUID) -> String {
        "tool-entry-\(entryID.uuidString)"
    }

    static func toolLive(_ cardID: String) -> String {
        "tool-live-\(cardID)"
    }

    /// 工具组：以行键为命名空间（落定组＝toolgroup-
    /// <首条目 id>、直播组＝live-toolgroup-<首卡 id>，
    /// 均由行构造点现成持有）
    static func toolGroupCard(
        groupKey: String, cardID: String
    ) -> String {
        "\(groupKey)/\(cardID)"
    }

    /// 直播工具组键：行键＝live-<LiveRenderItem.id>
    /// （item.id 恒为 toolgroup-<首卡 id>）
    static func liveToolGroup(_ itemID: String) -> String {
        "live-\(itemID)"
    }
}
