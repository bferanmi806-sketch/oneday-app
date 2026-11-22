import Foundation
import OneDayCore

/// 资源库派生快照（§363，流畅度 S4）：一趟 body 只算一
/// 次——过滤（文件/影音分段＋搜索词）→当前段排序→按路径
/// 字典，下传给内容面/行/菜单闭包共用。取代旧形态：计
/// 算属性 sortedDocuments/sortedMedia 每次访问都整表重
/// 排（rotor＋内容＋列表一趟三排、行点按与影音格预取
/// 每次触发再排），deliverable(for:) 每查一次线性扫描
/// 整表（行构建口径 O(N²) 的一半）。
///
/// 等价口径（钉测把守）：过滤谓词与旧 matchesQuery 逐
/// 字同（条目名 localizedCaseInsensitiveContains、词先
/// 去空白、空词全过）；排序直接走 LibraryOrdering
/// .sorted 单源、入参顺序与旧 ordered() 同（过滤后原
/// 序）；字典同路径取首个（与旧 first(where:) 同义），
/// 查无回落 Deliverable(entry:source: "") 与旧兜底逐字
/// 同。排序口味不在本包（标题序的汉字/拼音口径是用户
/// 待裁项，本包只搬运不改判）。
struct LibraryListSnapshot {
    /// 过滤后文件段（未排序）
    let documents: [Deliverable]
    /// 过滤后影音段（未排序）
    let mediaItems: [Deliverable]
    /// 当前段已排序条目（非当前段为空数组，本趟无人消费）
    let sortedDocuments: [WorkspaceFileEntry]
    let sortedMedia: [WorkspaceFileEntry]
    /// 路径→交付物（同路径首个优先，与旧线性首命中同义）
    let deliverableByPath: [String: Deliverable]

    /// 按路径查交付物：字典直达，缺失回落旧兜底形态
    func deliverable(for entry: WorkspaceFileEntry) -> Deliverable {
        deliverableByPath[entry.path]
            ?? Deliverable(entry: entry, source: "")
    }

    /// 过滤＋字典（不排序）：reveal 消费等只需成员判定
    /// 的事件路径走这里，不付排序账
    static func filtered(
        deliverables: [Deliverable]?,
        query: String
    ) -> (
        documents: [Deliverable],
        mediaItems: [Deliverable],
        byPath: [String: Deliverable]
    ) {
        let all = deliverables ?? []
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        func matches(_ item: Deliverable) -> Bool {
            trimmed.isEmpty
                || item.entry.name.localizedCaseInsensitiveContains(trimmed)
        }
        var byPath: [String: Deliverable] = [:]
        byPath.reserveCapacity(all.count)
        for item in all where byPath[item.entry.path] == nil {
            byPath[item.entry.path] = item
        }
        return (
            documents: all.filter {
                $0.entry.mediaKind == nil && matches($0)
            },
            mediaItems: all.filter {
                $0.entry.mediaKind != nil && matches($0)
            },
            byPath: byPath
        )
    }

    /// 整快照：过滤＋字典＋当前段排序（segment 0＝文件、
    /// 1＝影音，与宿主分段口径同）
    static func make(
        deliverables: [Deliverable]?,
        query: String,
        sort: LibrarySort,
        openedAt: [String: TimeInterval],
        pinned: Set<String>,
        segment: Int
    ) -> LibraryListSnapshot {
        let base = filtered(deliverables: deliverables, query: query)
        let sortedDocuments = segment == 0
            ? LibraryOrdering.sorted(
                base.documents.map(\.entry), by: sort,
                openedAt: openedAt, pinned: pinned
            )
            : []
        let sortedMedia = segment == 1
            ? LibraryOrdering.sorted(
                base.mediaItems.map(\.entry), by: sort,
                openedAt: openedAt, pinned: pinned
            )
            : []
        return LibraryListSnapshot(
            documents: base.documents,
            mediaItems: base.mediaItems,
            sortedDocuments: sortedDocuments,
            sortedMedia: sortedMedia,
            deliverableByPath: base.byPath
        )
    }
}
