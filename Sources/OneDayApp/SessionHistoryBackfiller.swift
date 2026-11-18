import Foundation
import OneDayCore
import SwiftData

/// 导入落盘单点（§331 自 ChatView.insertImported-
/// Entries 收口）：富内容项 → ChatEntry 的组装只此
/// 一份——导入首开（ChatView 分页路）与后台回补
/// （SessionHistoryBackfiller）共用，组装口径漂移
/// 无处藏。口径（0.8.0 P1 不变）：工具调用成卡、
/// 图片标记剥成路径、服务端时刻落 createdAt；工
/// 具卡 role="tool" 不进发送上下文（send 组装只
/// 取 user/assistant 正文）。
enum SessionHistoryInserter {
    /// 一页原始消息落盘（导入首开口径：不过滤、全
    /// 落——去重在消息 id 层由调用方先行）
    @discardableResult
    static func insert(
        messages: [SessionMessage], into thread: ChatThread,
        context: ModelContext
    ) -> Int {
        insert(
            items: SessionHistoryImport.richItems(from: messages),
            into: thread, context: context
        )
    }

    /// 富内容项落盘（回补口径：指纹过滤在调用方，
    /// 此处只管组装插入）
    @discardableResult
    static func insert(
        items: [SessionHistoryImport.RichItem],
        into thread: ChatThread, context: ModelContext
    ) -> Int {
        for item in items {
            let chatEntry = ChatEntry(
                role: item.role, content: item.content,
                thread: thread, toolCard: item.toolCard,
                remoteImagePaths: item.imagePaths,
                remoteFilePaths: item.fileRefs
            )
            if let date = item.date {
                chatEntry.createdAt = date
            }
            context.insert(chatEntry)
        }
        return items.count
    }

    /// 本地条目 → 回补指纹（与拉回项同口径组装，
    /// 见 Core SessionHistorySync）
    static func fingerprint(
        of entry: ChatEntry
    ) -> HistoryFingerprint {
        HistoryFingerprint(
            role: entry.role, date: entry.createdAt,
            content: entry.content,
            attachmentPaths: entry.remoteImagePaths
                + entry.remoteFilePaths,
            toolCardID: entry.toolCard?.id
        )
    }
}

/// 历史回补一轮的结果：complete＝分页拉尽且处理
/// 量对齐服务端总数；partial＝中途失败/处理量未
/// 对齐，已落部分保留、待下轮续补；failed＝一页
/// 都没拉动（多为未登录/未连接，状态原样待触发）
enum HistoryPullOutcome: Equatable {
    case complete
    case partial
    case failed
}

/// 服务端历史后台回补（根治版包 2，DESIGN §331）：
/// §190 大厂对位——历史是渐进补齐的后台义务、不
/// 是打开/发送的前置（Muse／ChatGPT 同形态：
/// 先给可用会话、历史随后到齐）。一轮＝从头分页
/// 全拉（order=latest），逐页按指纹去重落盘到既
/// 有线程；指纹对账使重拉天然幂等：已落条目不重
/// 复落、分页窗口漂移不丢不重。状态落线程三字段
/// （historyUnsynced/historyServerCount/history-
/// LoadedCount），呈现层据此安静标记、不弹窗。
@MainActor
final class SessionHistoryBackfiller {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    /// 回补一轮。调用方负责触发时机与防重入（同一
    /// 线程同时只许一轮）；本函数只管拉与落
    @discardableResult
    func backfill(
        thread: ChatThread, context: ModelContext
    ) async -> HistoryPullOutcome {
        guard let sessionID = thread.serverSessionID,
              !sessionID.isEmpty,
              !SideChatLink.isMergeBucket(sessionID),
              appState.config != nil
        else { return .failed }
        // 分母先行：回读会话行刷新服务端总数（失败
        // 不拦拉取——总数未知时以分页拉尽判齐）
        if let session = try? await appState.performAdmin(
            { client, config in
                try await client.serverSession(
                    config: config, id: sessionID
                )
            }
        ) {
            thread.historyServerCount = session.messageCount ?? 0
        }
        var offset = 0
        var processed = 0
        while true {
            let page: [SessionMessage]
            do {
                page = try await appState.performAdmin { client, config in
                    try await client.sessionMessagesPage(
                        config: config, id: sessionID,
                        limit: SessionHistoryPagePlanner.pageSize,
                        offset: offset
                    )
                }
            } catch {
                // 降级口径：已落部分保留、未同步标记
                // 在位，整段失败呈现就此退役（§331）
                thread.historyUnsynced = true
                thread.historyLoadedCount = thread.entries.count
                try? context.save()
                return processed > 0 ? .partial : .failed
            }
            let ordered = SessionHistoryPagePlanner
                .chronological(page)
            let items = SessionHistoryImport.richItems(
                from: ordered
            )
            let existing = Set(thread.entries.map {
                SessionHistoryInserter.fingerprint(of: $0)
            })
            let unseen = SessionHistorySync.unseenItems(
                items, existing: existing
            )
            SessionHistoryInserter.insert(
                items: unseen, into: thread, context: context
            )
            processed += page.count
            // 进度分子＝本地现有条目数（用户屏幕上实
            // 有的量）；处理量只作下方对齐判据
            thread.historyLoadedCount = thread.entries.count
            try? context.save()
            guard let next = SessionHistoryPagePlanner.nextOffset(
                currentOffset: offset, receivedCount: page.count
            ) else { break }
            offset = next
        }
        // 拉齐判据：分页已尽，且处理量对齐已知总数
        // （总数未知时以拉尽为准）。未对齐多因拉取
        // 期间会话又长了——保持未同步、下轮再对账
        if thread.historyServerCount == 0
            || processed >= thread.historyServerCount {
            thread.historyUnsynced = false
            thread.historyLoadedCount = thread.entries.count
            try? context.save()
            return .complete
        }
        thread.historyUnsynced = true
        try? context.save()
        return .partial
    }
}
