import Foundation
import OneDayCore

/// 动态派生快照（§415，四面收口包）：搜索过滤＋
/// 时间序一趟算齐，下传列表本体共用。取代旧形
/// 态：visiblePosts 计算属性（搜索过滤）＋body 内
/// FeedBoard.sorted 每趟求值重排（与资源库面
/// §363 快照口径同 App 双轨，骨架排查 F1）。
///
/// 等价口径（钉测把守）：过滤谓词与旧 visible-
/// Posts 逐字同（搜索态且词非空才过滤、词先去首
/// 尾空白、标题或正文 localizedCaseInsensitive-
/// Contains）；排序直接走 FeedBoard.sorted 单源
/// （§177 单条时间流唯一口径）。
struct FeedListSnapshot {
    /// 可见帖（已过滤＋已排序，列表本体消费）
    let visiblePosts: [BridgeFeedPost]

    static func make(
        posts: [BridgeFeedPost],
        searchText: String,
        isSearching: Bool
    ) -> FeedListSnapshot {
        let query = searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let visible: [BridgeFeedPost]
        if isSearching, !query.isEmpty {
            visible = posts.filter {
                $0.title.localizedCaseInsensitiveContains(query)
                    || $0.body.localizedCaseInsensitiveContains(query)
            }
        } else {
            visible = posts
        }
        return FeedListSnapshot(
            visiblePosts: FeedBoard.sorted(visible)
        )
    }
}

/// 动态派生快照缓存（§415）：快照按全输入指纹缓
/// 存——输入未变直接复用上一份，body 因无关状态
/// （sheet 呈现/回跳挂起等）重跑时不整趟重付过滤
/// ＋排序。与 LibrarySnapshotCache 同式：指纹＝
/// 三入参逐值比对（帖名单逐项、搜索词、搜索
/// 态），任一变即整趟重算——不许显旧（钉测把守
/// 修订号）。本类自含、无外部状态，宿主持
/// @State 实例；只许主线程触碰，不做跨线程同步。
final class FeedSnapshotCache {
    private var lastPosts: [BridgeFeedPost]?
    private var lastSearchText: String?
    private var lastIsSearching: Bool?
    private var lastSnapshot: FeedListSnapshot?

    /// 快照修订号：每次真重算 +1、命中不增（钉测
    /// 以此断言 body 重跑不重算）
    private(set) var revision = 0

    /// 与 FeedListSnapshot.make 同参同果：首调与
    /// 输入变更时走 make 整趟，命中时回存量快照
    func snapshot(
        posts: [BridgeFeedPost],
        searchText: String,
        isSearching: Bool
    ) -> FeedListSnapshot {
        if let lastSnapshot,
           lastSearchText == searchText,
           lastIsSearching == isSearching,
           lastPosts == posts {
            return lastSnapshot
        }
        let made = FeedListSnapshot.make(
            posts: posts, searchText: searchText,
            isSearching: isSearching
        )
        lastPosts = posts
        lastSearchText = searchText
        lastIsSearching = isSearching
        lastSnapshot = made
        revision += 1
        return made
    }
}
