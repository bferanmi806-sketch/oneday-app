import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit

/// 文件格（0.20.0 底栏第四格）：照用户给的 Muse 资
/// 源库页——顶部身份区（左抽屉钮／中央身份胶囊／右
/// 钮），其下大分段 [文件｜影音内容]。
///
/// **交付物口径（用户原话：用户让做的东西做好之后
/// 放里面的，如 PPT——不是服务器全部文件）**：数据
/// 自 A-06（伴生 1.0.66）起走文件库聚合读面（GET
/// /api/oneday-bridge/file-library）单流下发——产出
/// 根走查、准入（0.22.0 去污形态拦截＋根散白名单＋
/// 敏感名单第二道）、去重、排序全在服务端，单一事
/// 实源在 oneday_seg_filelibrary.py。P8（0.14.0）起
/// 的客户端爬 /api/files 目录树聚合（8 根硬编码、
/// 递归 ≤3 层、600 静默截断、客户端准入）已退役。
/// 服务端文件全量浏览不在本页（••• 菜单组3「系统
/// 文件」与设置「管理」共用 FilesBrowserView）。
///
/// **0.36.31 文件页 v2（规格 files-page-design-
/// 20261110 §4＋两附记）**：右上搜索钮撤除、改 •••
/// 菜单收纳（组1 显示 列表/网格、组2 排序 上次打开/
/// 上次修改/标题——页级状态 @AppStorage 持久化、两
/// 段共用；组3 系统文件；组4 上传文件）；搜索改下拉
/// 露出（滚动偏移触发、无新增手势件；下拉刷新因此
/// 退役——同一拉动手势只供一主，失败态给显式重试钮
/// 补位）；文件段网格＝双列内容卡（缩略首面＋展示标
/// 题＋类型签，§4.3 落值）；影音段补列表态；网格态
/// 文件段按 7 天窗分「最近/全部」（§4.5 自有口径）；
/// 打开写本地上次打开记录（排序辅助、丢了不伤数
/// 据，非第二真源——规格 §六切割声明）；条目菜单与
/// 打开分流按类型走 Core FileActionPolicy（附记硬规
/// 矩：文本类进文档阅读页并给复制文字/导出 PDF，敏
/// 感文件在本面已被准入挡下、浏览器面另有锁定）；
/// 聚合根新增 attachments（聊天发送的文件副本，
/// 0.36.29 通道落点——服务端无自动过期，本面呈现＋
/// 删除即其生命周期出口）。
struct DeliverablesView: View {
    @Environment(AppState.self) private var appState
    // 动效走令牌＋resolved 出口（0.25.0 起本面口径）
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 文件库聚合读面客户端（A-06）：聚合集唯一来源
    private let bridgeClient = OneDayBridgeClient()

    /// 0＝文件、1＝影音内容
    @State private var segment = 0
    /// §369（缓存 C4）：名单走 AppState 共享店＋落盘
    /// 快照（LibraryListStore）——冷启先显快照、后台
    /// 对账换新，删除本地摘行不重拉；本面只读消费
    private var listStore: LibraryListStore {
        appState.sharedLibraryListStore()
    }
    private var deliverables: [Deliverable]? {
        listStore.deliverables
    }
    /// F1：派生快照指纹缓存（LibrarySnapshotCache，
    /// 输入未变回存量快照、不整趟重算）
    @State private var snapshotCache = LibrarySnapshotCache()
    @State private var loadError: String?
    @State private var pendingDelete: Deliverable?
    @State private var shareItem: FileShareItem?
    @State private var notice: String?
    @State private var query = ""
    @State private var searchVisible = false
    /// 非图条目打开目的地（§125 合并）：旧
    /// previewEntry/readerEntry 双状态分流（预览页/
    /// 阅读页）退役，统一先进文件打开页
    @State private var previewEntry: WorkspaceFileEntry?
    /// 图片查看器路由（0.36.4）：图片直达查看器（系
    /// 统 zoom 转场、源＝格/卡的 matched 标记），不
    /// 再先进预览页
    @State private var viewerRoute: ImageViewerRoute?
    @Namespace private var viewerNamespace
    /// 上次打开记录（§4.3/§4.5 排序辅助，本地表）
    @State private var openHistory = FileOpenHistoryStore()
    /// 显示方式与排序：页级状态、持久化（§4.2）
    @AppStorage("files.displayMode")
    private var displayModeRaw = LibraryDisplayMode.list.rawValue
    @AppStorage("files.sort")
    private var sortRaw = LibrarySort.lastOpened.rawValue
    @State private var uploadPickerPresented = false
    @State private var systemFilesRoute: SystemFilesRoute?
    /// 定位高亮（§131）：「在文件页中打开」消费后置
    /// 位目标路径，行/卡闪高亮、数秒后自清
    @State private var revealedPath: String?

    /// 系统文件目的地（§131 泛化）：常规入口 dir/
    /// highlight 皆空；定位回指落空（文件不在聚合集
    /// 内）时带父目录＋文件名直达浏览器定位
    private struct SystemFilesRoute: Identifiable, Hashable {
        let dir: String?
        let highlight: String?
        var id: String { "\(dir ?? "")|\(highlight ?? "")" }
    }

    /// 置顶集（§131）：全 App 单例，与打开页切换态
    /// 同一份（FilePinStore 口径）
    private var pinStore: FilePinStore { .shared }

    private var displayMode: LibraryDisplayMode {
        LibraryDisplayMode.resolved(rawValue: displayModeRaw)
    }

    private var sort: LibrarySort {
        LibrarySort.resolved(rawValue: sortRaw)
    }

    /// 「更多」菜单两组 Picker 的 selection 绑定（样式
    /// 二期 S2-04）：读经 Core resolved 解析（未知原值
    /// 回落默认档、恰一勾），写回落盘原值
    private var displayModeBinding: Binding<LibraryDisplayMode> {
        Binding(
            get: { displayMode },
            set: { displayModeRaw = $0.rawValue }
        )
    }

    private var sortBinding: Binding<LibrarySort> {
        Binding(
            get: { sort },
            set: { sortRaw = $0.rawValue }
        )
    }

    /// 查看器集合载荷：同段图片条目＋起始索引
    private struct ImageViewerRoute: Identifiable, Hashable {
        let entries: [WorkspaceFileEntry]
        let initialIndex: Int
        var id: String { entries[initialIndex].path }
    }

    var body: some View {
        // §363（S4）：派生快照一趟只算一次、下传内容面
        // 共用（旧计算属性每访问整表重排，见
        // LibraryListSnapshot 头注）；F1（2026-11-23）：
        // 入口改走指纹缓存——输入未变回存量快照，整
        // 趟重算只在名单／搜索／排序／打开史／置顶／
        // 分段真变时发生
        let snapshot = snapshotCache.snapshot(
            deliverables: deliverables,
            query: query,
            sort: sort,
            openedAt: openHistory.openedAtMap,
            pinned: pinStore.pinnedPaths,
            segment: segment
        )
        return NavigationStack {
            VStack(spacing: 0) {
                identityHeader
                if searchVisible {
                    searchFieldRow
                }
                segmentControl
                if segment == 0 {
                    filesContent(snapshot)
                } else {
                    mediaContent(snapshot)
                }
            }
            // 0.43.0（A11Y-V7）：「文件」Rotor——条目
            // 与行/卡标记同名对位（见 fileRotorNames-
            // pace 注）
            .accessibilityRotor(
                L10n.string("文件")
            ) {
                ForEach(
                    segment == 0
                        ? snapshot.sortedDocuments.map(\.name)
                        : snapshot.sortedMedia.map(\.name),
                    id: \.self
                ) { name in
                    AccessibilityRotorEntry(
                        DeliverableFileType.displayTitle(
                            forFileName: name
                        ),
                        name, in: fileRotorNamespace
                    )
                }
            }
            .background {
                Palette.pageBG
                    .ignoresSafeArea()
            }
            .toolbar(.hidden, for: .navigationBar)
            // §125：打开分流收口——非图条目一律落文
            // 件打开页（中间页），文本类的阅读在其页
            // 内主钮进阅读页；旧 previewEntry/
            // readerEntry 双目的地分流退役（状态合并
            // 至 previewEntry）
            .navigationDestination(item: $previewEntry) { entry in
                FileOpenContent(
                    target: FileOpenTarget(entry: entry),
                    origin: .serverFile
                )
            }
            .navigationDestination(item: $systemFilesRoute) { route in
                FilesBrowserView(
                    initialPath: route.dir,
                    highlightName: route.highlight
                )
                .navigationTitle("系统文件")
                .navigationBarTitleDisplayMode(.inline)
            }
            .navigationDestination(item: $viewerRoute) { route in
                ImageViewerView(
                    items: route.entries.map {
                        ChatImageViewerItem(
                            source: .remotePath($0.path),
                            mtime: $0.mtime ?? 0
                        )
                    },
                    initialIndex: route.initialIndex,
                    onDeleteItem: { item in
                        if case .remotePath(let path) = item.source,
                           let entry = route.entries.first(
                               where: { $0.path == path }
                           ) {
                            Task { await deleteFromViewer(entry) }
                        }
                    }
                )
                .navigationTransition(
                    .zoom(
                        sourceID: route.entries[route.initialIndex]
                            .path,
                        in: viewerNamespace
                    )
                )
            }
            // §131：以文件库修订号为键——打开页改名成
            // 功递增修订号，本页重聚合不留旧名残影
            .task(id: appState.fileLibraryRevision) {
                await collect()
            }
            .onChange(of: appState.router.fileRevealPath) { _, _ in
                consumeRevealIfReady()
            }
            .modifier(
                FileUploadPickerModifier(
                    appState: appState,
                    isPresented: $uploadPickerPresented,
                    targetDirectory: Self.uploadsPath,
                    ensureDirectory: true
                ) { message, confirmed in
                    notice = message
                    if confirmed {
                        Task { await collect() }
                    }
                }
            )
            .confirmationDialog(
                "删除「\(pendingDelete?.entry.name ?? "")」？",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    // 触感矩阵（规格 §2.3）：删除确认
                    // 落锤＝impact heavy；删除成功后不
                    // 再叠 success（同一因果链只震一次）
                    Haptics.impact(.heavy)
                    if let item = pendingDelete {
                        Task { await delete(item) }
                    }
                    pendingDelete = nil
                }
                Button("取消", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("删除后无法恢复。")
            }
            .sheet(item: $shareItem) { item in
                FileShareSheet(url: item.url)
            }
        }
    }

    // MARK: - 顶部身份区（左抽屉钮／中央胶囊／右 •••）

    private var identityHeader: some View {
        ZStack {
            HStack {
                Button {
                    appState.router.drawerPresented = true
                } label: {
                    headerCircleButton("line.3.horizontal")
                }
                .buttonStyle(.odPressable)
                .accessibilityLabel("会话列表")
                Spacer()
                // §4.1/§4.2：右上改 ••• 菜单钮（搜索钮
                // 撤除）——组1 显示、组2 排序（每组单
                // 选）、组3 系统文件、组4 上传文件
                // （OneDay 扩展，规格标注）。两组单选改
                // 系统 Picker 承载（样式二期 S2-04）：
                // 勾由系统按 selection 绘制、占固定左
                // 槽、文字同 x 对齐；旧手工对勾塞 Label
                // 图标位的形态（选中行文字右移、无勾行
                // 贴边，与模型双勾 P-04 同根）整段退役，
                // 正道据 ChatView 模型菜单注释与苹果反
                // 馈 FB16679936（Toggle/Picker）
                Menu {
                    Section("显示") {
                        Picker("显示", selection: displayModeBinding) {
                            ForEach(
                                LibraryDisplayMode.allCases, id: \.self
                            ) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                    }
                    Section("排序") {
                        Picker("排序", selection: sortBinding) {
                            ForEach(
                                LibrarySort.allCases, id: \.self
                            ) { option in
                                Text(option.label).tag(option)
                            }
                        }
                    }
                    Section {
                        Button {
                            systemFilesRoute = SystemFilesRoute(
                                dir: nil, highlight: nil
                            )
                        } label: {
                            Label("系统文件", systemImage: "folder")
                        }
                    }
                    Section {
                        Button {
                            uploadPickerPresented = true
                        } label: {
                            Label(
                                "上传文件",
                                systemImage: "arrow.up.doc"
                            )
                        }
                    }
                } label: {
                    headerCircleButton("ellipsis")
                }
                .accessibilityLabel("资源库菜单")
            }
            IdentityAnchor(
                // 0.36.22：名与头像收敛档案出口
                name: appState.agentDisplayName,
                statusWord: appState.config == nil ? "未连接" : "在线",
                statusColor: appState.config == nil
                    ? Palette.inkMuted : Palette.success,
                // 真头像注入（0.22.0 审计 F3），与聊天页
                // 胶囊同一头像源
                avatarImage: appState.agentAvatarImage
            )
        }
        .padding(.horizontal, OneDayMetrics.pageGutter)
        .padding(.top, OneDayMetrics.spacingS)
        .padding(.bottom, OneDayMetrics.spacingXS)
    }

    private func headerCircleButton(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(
                size: HeaderButtonSpec.glyphPointSize,
                weight: .regular
            ))
            .foregroundStyle(Palette.ink)
            .frame(
                width: HeaderButtonSpec.diameter,
                height: HeaderButtonSpec.diameter
            )
            // 与聊天页顶栏圆钮同族材质：系统玻璃
            // .glassEffect(.regular)，视觉盘 40 不变
            .glassEffect(.regular, in: Circle())
            // 命中域外扩 44（视觉盘居中不变）
            .frame(
                width: OneDayMetrics.minTapTarget,
                height: OneDayMetrics.minTapTarget
            )
            .contentShape(Rectangle())
    }

    /// 下拉露出搜索栏（§4.2）：搜当前聚合集的文件名
    /// （本地过滤）；展开/收起由内容滚动偏移驱动（见
    /// handleScrollOffset），不新增手势识别器
    private var searchFieldRow: some View {
        FileSearchField(query: $query)
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.bottom, OneDayMetrics.spacingSM)
    }

    /// 下拉触发口径：内容被下拉过顶 56pt 露出搜索；
    /// 回滚到顶且关键词为空才收起（输入态——关键词
    /// 非空——保持展开，§4.2）
    private func handleScrollOffset(_ y: CGFloat) {
        if y < -56, !searchVisible {
            withAnimation(
                MotionTokens.resolved(
                    MotionTokens.swap, reduceMotion: reduceMotion
                )
            ) { searchVisible = true }
        } else if y > 10, searchVisible, query.isEmpty {
            withAnimation(
                MotionTokens.resolved(
                    MotionTokens.swap, reduceMotion: reduceMotion
                )
            ) { searchVisible = false }
        }
    }

    // MARK: - 大分段（2026-11-15 第 88 条收口：迁系统 segmented）

    /// 分段控件沿革：0.36.2 照 Muse 资源库图自制
    /// （SegmentedControlSpec 落值：总高 48／药丸 36
    /// ／内缩 6）；2026-11-15 主线裁决「系统件优先
    /// 为默认、自制为例外」，本面纯文字两段无例外
    /// 理由、自制件退役——现行形态与形态差见
    /// segmentControl 注

    /// 「文件」Rotor 命名空间（0.43.0，A11Y-V7）：
    /// 长列表/网格里按文件名直达——条目随当前段
    /// 取自 body 快照（§363），行/卡标记挂在各行
    /// 构建处（deliverableRow/mediaRow/fileCard/
    /// 影音网格钮），id＝文件名与条目一一对位
    @Namespace private var fileRotorNamespace

    /// 系统 segmented（第 88 条收口）：形态差如实
    /// 记——总高 48→系统约 32；轨道自 surface 白＋
    /// 发丝边改系统灰、选中垫自 selectionFill 改系
    /// 统白拇指（自带微影）；字阶自 .bodyText semi-
    /// bold 改系统分段字；左右边距自控件局部口径
    /// 16 回页面口径 pageGutter 20。触感矩阵（规格
    /// §2.3）：分段切换＝selection，保留；药丸滑移
    /// 由系统分段自带过渡替代
    private var segmentControl: some View {
        Picker("内容类型", selection: $segment) {
            Text("文件").tag(0)
            Text("影音内容").tag(1)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, OneDayMetrics.pageGutter)
        .padding(.vertical, OneDayMetrics.spacingSM)
        .sensoryFeedback(.selection, trigger: segment)
    }

    // MARK: - 派生集（过滤→页级排序→分组）

    /// App 上传落点（与 P8 同址：managed 根下专属目录）
    static var uploadsPath: String {
        FileBrowserLogic.joinPath(
            directory: "/opt/data",
            name: FileBrowserLogic.uploadsDirectoryName
        )
    }

    // §363（S4）：过滤/排序/按路径查一并收进
    // LibraryListSnapshot（body 一趟算一次下传）——
    // 旧 matchesQuery/documents/mediaItems/ordered/
    // sortedDocuments/sortedMedia/deliverable(for:)
    // 计算属性组就此退役（每访问整表重排＋每查线性
    // 扫描的病根，见快照头注与 DESIGN §363）

    // MARK: - 文件段

    @ViewBuilder
    private func filesContent(
        _ snapshot: LibraryListSnapshot
    ) -> some View {
        if deliverables == nil && loadError == nil {
            loadingState
        } else if let loadError, deliverables == nil {
            failureState(message: loadError)
        } else if snapshot.documents.isEmpty {
            emptyState(
                title: query.isEmpty ? "暂无交付物" : "没有匹配的文件",
                symbol: query.isEmpty
                    ? "doc.text.magnifyingglass" : "magnifyingglass",
                message: query.isEmpty
                    ? "智能体生成的文件与定时任务产出会出现在这里。"
                    : "换个关键词试试。"
            )
        } else if displayMode == .list {
            fileListView(snapshot)
        } else {
            fileGridView(snapshot)
        }
    }

    private var loadingState: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 失败态带显式重试（下拉刷新退役后的补位，见页头注）
    private func failureState(message: String) -> some View {
        ContentUnavailableView {
            Label("没读出来", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("重试") {
                Task { await collect() }
            }
        }
    }

    private func emptyState(
        title: String, symbol: String, message: String
    ) -> some View {
        // 空态编排（台账 177，§391）：走共用编排件
        // （分阶段入场＋减动效降级），两调用点同受益
        ODEmptyState(
            title, systemImage: symbol, description: message
        )
    }

    @ViewBuilder
    private var noticeView: some View {
        if let notice {
            Text(notice)
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.top, OneDayMetrics.spacingM)
                .padding(.horizontal, OneDayMetrics.pageGutter)
        }
    }

    /// 列表态：平铺不分组（§4.5——分组只在网格态）；
    /// §131 加 ScrollViewReader 承定位滚动（行 id＝
    /// 路径，与 reveal 消费同口径）
    private func fileListView(
        _ snapshot: LibraryListSnapshot
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // §363（S4）：急切 VStack 改 LazyVStack
                    // ——首建只建首屏行（骨架量测：1500 行
                    // 首建主线程卡顿 1799ms→51ms 量级，
                    // 见 DESIGN §363）；行 id 与 reveal
                    // 定位口径不变
                    LazyVStack(spacing: 0) {
                        ForEach(
                            Array(
                                snapshot.sortedDocuments
                                    .enumerated()
                            ),
                            id: \.element.id
                        ) { index, entry in
                            if index > 0 {
                                GroupDivider(
                                    inset: OneDayMetrics.dividerInset
                                )
                            }
                            deliverableRow(
                                entry, snapshot: snapshot
                            )
                        }
                    }
                    noticeView
                }
                .padding(.top, OneDayMetrics.spacingXS)
                .padding(.bottom, OneDayMetrics.spacingXL)
            }
            .background(Palette.pageBG)
            // §170（用户 2026-11-11 23:28 亲定）：底部导
            // 航栏同档收边（与输入框下方收边同档）——本格四个滚动面
            // （文件列表/网格、影音列表/网格）底缘一律
            // 挂 .hard，口径与映射见 FeedView 同注与
            // DESIGN §170.2
            // §185 按裁决改 .soft：该边缘内容可流到坞下、.hard 官方定义近乎不透明本身制造色带（solidband 裁决第四节）；§170 的 .hard 口径就此点被 §185 覆盖。
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, newValue in
                handleScrollOffset(newValue)
            }
            .onChange(of: revealedPath) { _, path in
                scrollToRevealed(path, proxy: proxy)
            }
        }
    }

    /// 定位滚动（§131 四面共用）：revealedPath 置位即
    /// 滚到该行居中；清零不滚
    private func scrollToRevealed(
        _ path: String?, proxy: ScrollViewProxy
    ) {
        guard let path else { return }
        withAnimation(
            MotionTokens.resolved(
                MotionTokens.swap, reduceMotion: reduceMotion
            )
        ) {
            proxy.scrollTo(path, anchor: .center)
        }
    }

    /// 文件行：类型图标盒＋展示标题（去扩展名，§4.3
    /// 行口径修正）＋类型小字＋行尾 ⋮；⋮ 与长按同出
    /// 一套按类型适配的动作集（FileActionPolicy 附记
    /// 硬规矩，覆盖 §4.7 的两件旧口径）；点行按类型
    /// 分流打开
    private func deliverableRow(
        _ entry: WorkspaceFileEntry,
        snapshot: LibraryListSnapshot
    ) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            // §363（S4，真机矩阵定案）：主区改原生 Button
            // ＋.odPressable——原「点按手势＋自研按压修饰（§379 已整件退役）」
            // 的 DragGesture(0) 在 SwiftUI ScrollView 里落
            // 指即识别、抢走滚动序列，行面全死（§363 四格
            // 矩阵）；Button 反馈由系统供、与滚动及长按菜
            // 单共存（目标面与本面影音网格同形态）。0.43.0
            // 合并按钮元素语义改由真 Button 承载；⋮ 菜单
            // 仍在按钮外独立可达，几何逐字不变
            Button {
                openEntry(entry, among: snapshot.sortedDocuments)
            } label: {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    FileIconBox(entry: entry)
                    VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                        Text(
                            DeliverableFileType.displayTitle(
                                forFileName: entry.name
                            )
                        )
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                        // 0.43.0（A11Y-D3）：AX 档放宽
                        .a11yLineLimit(1, ax: 2)
                        Text(
                            DeliverableFileType.label(
                                forFileName: entry.name
                            )
                        )
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                        .a11yLineLimit(1, ax: 2)
                    }
                }
                .frame(
                    maxWidth: .infinity, minHeight: 64,
                    alignment: .leading
                )
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.odPressable)
            Spacer(minLength: OneDayMetrics.spacingS)
            Menu {
                actionItems(
                    for: entry, among: snapshot.sortedDocuments,
                    deliverable: snapshot.deliverable(for: entry)
                )
            } label: {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Palette.inkSecondary)
                    // 命中域 44（0.22.0 审计 F4，字形不变）
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("更多操作")
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: 64)
        // §131：定位高亮（reveal 消费置位、数秒自清）
        .background(
            revealedPath == entry.path
                ? Palette.selectionFill : Color.clear
        )
        .contentShape(Rectangle())
        .id(entry.path)
        // 0.43.0（A11Y-V7）：Rotor 行标记
        .accessibilityRotorEntry(id: entry.name, in: fileRotorNamespace)
        .contextMenu {
            actionItems(
                for: entry, among: snapshot.sortedDocuments,
                deliverable: snapshot.deliverable(for: entry)
            )
        }
    }

    /// 网格态（§4.3）：双列、边距 16/列距 12/行距
    /// 16；排序≠标题时分「最近/全部」两组（§4.5）
    private func fileGridView(
        _ snapshot: LibraryListSnapshot
    ) -> some View {
        let sections = LibraryOrdering.grouped(
            snapshot.sortedDocuments,
            openedAt: openHistory.openedAtMap, now: Date(),
            pinned: pinStore.pinnedPaths
        )
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingL) {
                    ForEach(
                        Array(sections.enumerated()), id: \.offset
                    ) { _, section in
                        VStack(
                            alignment: .leading,
                            spacing: OneDayMetrics.spacingM
                        ) {
                            if let title = section.title {
                                Text(title)
                                    .font(.sectionLabel)
                                    .foregroundStyle(Palette.inkSecondary)
                                    .padding(
                                        .horizontal,
                                        OneDayMetrics.spacingM
                                    )
                            }
                            LazyVGrid(
                                columns: Self.cardColumns,
                                spacing: OneDayMetrics.spacingM
                            ) {
                                ForEach(section.entries) { entry in
                                    fileCard(entry, snapshot: snapshot)
                                }
                            }
                            .padding(
                                .horizontal, OneDayMetrics.spacingM
                            )
                        }
                    }
                    noticeView
                }
                .padding(.top, OneDayMetrics.spacingM)
                .padding(.bottom, OneDayMetrics.spacingXL)
            }
            .background(Palette.pageBG)
            // §170：底缘 .hard（口径见 fileListView 同注）
            // §185 按裁决改 .soft：该边缘内容可流到坞下、.hard 官方定义近乎不透明本身制造色带（solidband 裁决第四节）；§170 的 .hard 口径就此点被 §185 覆盖。
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, newValue in
                handleScrollOffset(newValue)
            }
            .onChange(of: revealedPath) { _, path in
                scrollToRevealed(path, proxy: proxy)
            }
        }
    }

    private static let cardColumns = [
        GridItem(.flexible(), spacing: OneDayMetrics.spacingSM),
        GridItem(.flexible(), spacing: OneDayMetrics.spacingSM),
    ]

    /// 内容卡（§4.3）：预览区 112（缩略首面/类型面，
    /// FileThumbnailStore 分档生成）＋信息条 64（展
    /// 示标题 semibold 一行＋类型签）；图片卡带 zoom
    /// 转场源标记（0.36.4 衔接）。
    /// §131 翻案：信息条尾加 ⋮ 钮（与行 ⋮/长按同源
    /// actionItems，§125「卡上无 ⋮」口径作废）——卡
    /// 本体由 Button 改点按手势＋无障碍按钮语义（行
    /// 同式），⋮ 才有独立命中、不被整卡点击吞掉
    private func fileCard(
        _ entry: WorkspaceFileEntry,
        snapshot: LibraryListSnapshot
    ) -> some View {
        // §363（S4，真机矩阵定案）：整卡改原生 Button＋
        // .odPressable（原因见文件行注与 §363 四格矩阵）。
        // ⋮ 菜单原在信息栏内、不能嵌进 Button 标签，改同
        // 位覆盖层：距顶＝缩略图 112＋栏顶距 spacingS、距
        // 尾＝栏边距 spacingSM，与原布局盒逐值同位；信息
        // 栏内留 40×40 占位（原菜单净布局盒）保文本列宽。
        // 已知差：按压缩放只作用卡体、⋮ 不随动（0.97／
        // 0.25s 级，见 §363 注记）
        Button {
            openEntry(entry, among: snapshot.sortedDocuments)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                FileThumbnailView(entry: entry, targetPixelSize: 440)
                    .frame(height: 112)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .matchedTransitionSource(
                        id: entry.path, in: viewerNamespace
                    )
                    .accessibilityHidden(true)
                HStack(alignment: .top, spacing: OneDayMetrics.spacingXS) {
                    VStack(
                        alignment: .leading, spacing: OneDayMetrics.spacingMicro
                    ) {
                        Text(
                            DeliverableFileType.displayTitle(
                                forFileName: entry.name
                            )
                        )
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        Text(typeTag(for: entry))
                            .font(.meta)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    // ⋮ 覆盖层占位（净布局盒 40×40 与原
                    // 菜单标签同值，文本列宽不变）
                    Color.clear
                        .frame(width: 40, height: 40)
                }
                .padding(.horizontal, OneDayMetrics.spacingSM)
                .padding(.vertical, OneDayMetrics.spacingS)
                .frame(height: 64, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                Palette.surface,
                in: RoundedRectangle(cornerRadius: OneDayMetrics.radiusPreview)
            )
            .overlay {
                RoundedRectangle(cornerRadius: OneDayMetrics.radiusPreview)
                    .strokeBorder(Palette.separator, lineWidth: 1)
            }
            .overlay {
                // §131：定位高亮（reveal 消费置位、数秒自清）
                if revealedPath == entry.path {
                    RoundedRectangle(
                        cornerRadius: OneDayMetrics.radiusPreview
                    )
                    .strokeBorder(Palette.primary, lineWidth: 2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: OneDayMetrics.radiusPreview))
            .contentShape(
                RoundedRectangle(cornerRadius: OneDayMetrics.radiusPreview)
            )
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.odPressable)
        .overlay(alignment: .topTrailing) {
            Menu {
                actionItems(
                    for: entry, among: snapshot.sortedDocuments,
                    deliverable: snapshot.deliverable(for: entry)
                )
            } label: {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: 40, height: 40)
                    // 第 83 条（命中域收口）：与同文件媒
                    // 体行同钮对齐——命中域外扩 44；负内
                    // 边距抵消外扩、文档行布局不动
                    .frame(
                        width: OneDayMetrics.minTapTarget,
                        height: OneDayMetrics.minTapTarget
                    )
                    .contentShape(Rectangle())
                    .padding(-(OneDayMetrics.minTapTarget - 40) / 2)
            }
            .accessibilityLabel("更多操作")
            .padding(.top, 112 + OneDayMetrics.spacingS)
            .padding(.trailing, OneDayMetrics.spacingSM)
        }
        .id(entry.path)
        // 0.43.0（A11Y-V7）：Rotor 卡标记（网格态）
        .accessibilityRotorEntry(id: entry.name, in: fileRotorNamespace)
        .contextMenu {
            actionItems(
                for: entry, among: snapshot.sortedDocuments,
                deliverable: snapshot.deliverable(for: entry)
            )
        }
    }

    /// 类型签（§4.3）：媒体给人话词（图片/视频/音
    /// 频）、文本类给「文本」，其余沿 Deliverable-
    /// FileType 大写扩展名表（PDF/DOCX/PPTX/HTML…）
    private func typeTag(
        for entry: WorkspaceFileEntry
    ) -> String {
        switch entry.mediaKind {
        case .image: return "图片"
        case .video: return "视频"
        case .audio: return "音频"
        case nil: break
        }
        if DocumentTextKind.kind(forFileName: entry.name) != nil {
            return "文本"
        }
        return DeliverableFileType.label(forFileName: entry.name)
    }

    // MARK: - 影音段

    @ViewBuilder
    private func mediaContent(
        _ snapshot: LibraryListSnapshot
    ) -> some View {
        if deliverables == nil && loadError == nil {
            loadingState
        } else if let loadError, deliverables == nil {
            failureState(message: loadError)
        } else if snapshot.mediaItems.isEmpty {
            emptyState(
                title: query.isEmpty
                    ? "暂无影音交付" : "没有匹配的文件",
                symbol: query.isEmpty
                    ? "photo.on.rectangle.angled" : "magnifyingglass",
                message: query.isEmpty
                    ? "智能体生成的图片、视频与音频会出现在这里。"
                    : "换个关键词试试。"
            )
        } else if displayMode == .grid {
            mediaGridView(snapshot)
        } else {
            mediaListView(snapshot)
        }
    }

    private let mediaColumns = [
        GridItem(.flexible(), spacing: OneDayMetrics.spacingMicro),
        GridItem(.flexible(), spacing: OneDayMetrics.spacingMicro),
        GridItem(.flexible(), spacing: OneDayMetrics.spacingMicro),
    ]

    /// 影音网格维持三列方形媒体格（§4.4：媒体本身即
    /// 内容、方形格是系统相册惯例，不随文件段网格变）
    private func mediaGridView(
        _ snapshot: LibraryListSnapshot
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    LazyVGrid(columns: mediaColumns, spacing: OneDayMetrics.spacingMicro) {
                        ForEach(snapshot.sortedMedia, id: \.id) { entry in
                            Button {
                                openEntry(entry, among: snapshot.sortedMedia)
                            } label: {
                                MediaCell(entry: entry)
                                    // zoom 转场源标记（0.36.4）
                                    .matchedTransitionSource(
                                        id: entry.path,
                                        in: viewerNamespace
                                    )
                                    // §131：定位高亮描边
                                    .overlay {
                                        if revealedPath == entry.path {
                                            Rectangle()
                                                .strokeBorder(
                                                    Palette.primary,
                                                    lineWidth: 2
                                                )
                                        }
                                    }
                            }
                            .buttonStyle(.odPressable)
                            .id(entry.path)
                            // §144：以可见格为锚向后预
                            // 取 2 行（6 格）360 档——
                            // 滚动方向上先暖缓存，格到
                            // 眼前时缩略已在、不阻塞布局
                            .onAppear {
                                prefetchMedia(
                                    after: entry,
                                    among: snapshot.sortedMedia
                                )
                            }
                            // 0.43.0（A11Y-V7）：Rotor 卡标记
                            .accessibilityRotorEntry(
                                id: entry.name, in: fileRotorNamespace
                            )
                            .contextMenu {
                                actionItems(
                                    for: entry,
                                    among: snapshot.sortedMedia,
                                    deliverable: snapshot
                                        .deliverable(for: entry)
                                )
                            }
                        }
                    }
                    noticeView
                }
                .padding(.bottom, OneDayMetrics.spacingXL)
            }
            .background(Palette.pageBG)
            // §170：底缘 .hard（口径见 fileListView 同注）
            // §185 按裁决改 .soft：该边缘内容可流到坞下、.hard 官方定义近乎不透明本身制造色带（solidband 裁决第四节）；§170 的 .hard 口径就此点被 §185 覆盖。
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, newValue in
                handleScrollOffset(newValue)
            }
            .onChange(of: revealedPath) { _, path in
                scrollToRevealed(path, proxy: proxy)
            }
        }
    }

    /// 影音列表（§4.4 新补）：56pt 缩略行——标题＋类
    /// 型签＋大小·日期小字（服务端无时长字段，时长
    /// 不摆、如实以大小日期代，§七同口径）
    private func mediaListView(
        _ snapshot: LibraryListSnapshot
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // §363（S4）：与文件列表同改 LazyVStack
                    // （同骨架同病根，见 fileListView 注）
                    LazyVStack(spacing: 0) {
                        ForEach(
                            Array(
                                snapshot.sortedMedia
                                    .enumerated()
                            ),
                            id: \.element.id
                        ) { index, entry in
                            if index > 0 {
                                GroupDivider(
                                    inset: OneDayMetrics.dividerInset
                                )
                            }
                            mediaRow(
                                entry, snapshot: snapshot
                            )
                        }
                    }
                    noticeView
                }
                .padding(.top, OneDayMetrics.spacingXS)
                .padding(.bottom, OneDayMetrics.spacingXL)
            }
            .background(Palette.pageBG)
            // §170：底缘 .hard（口径见 fileListView 同注）
            // §185 按裁决改 .soft：该边缘内容可流到坞下、.hard 官方定义近乎不透明本身制造色带（solidband 裁决第四节）；§170 的 .hard 口径就此点被 §185 覆盖。
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, newValue in
                handleScrollOffset(newValue)
            }
            .onChange(of: revealedPath) { _, path in
                scrollToRevealed(path, proxy: proxy)
            }
        }
    }

    private func mediaRow(
        _ entry: WorkspaceFileEntry,
        snapshot: LibraryListSnapshot
    ) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            // §363（S4）：与文件行同式改原生 Button＋
            // .odPressable（原因见文件行注与 §363）；缩略
            // ＋题＋副题合并语义改由真 Button 承载，⋮ 菜
            // 单仍在按钮外独立可达，几何逐字不变
            Button {
                openEntry(entry, among: snapshot.sortedMedia)
            } label: {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    ZStack {
                        FileThumbnailView(entry: entry, targetPixelSize: 168)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: OneDayMetrics.radiusThumb))
                        if entry.mediaKind == .video {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(
                                    Color.white, Palette.ink.opacity(0.55)
                                )
                                .accessibilityHidden(true)
                        }
                    }
                    .matchedTransitionSource(
                        id: entry.path, in: viewerNamespace
                    )
                    VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                        Text(
                            DeliverableFileType.displayTitle(
                                forFileName: entry.name
                            )
                        )
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                        // 0.43.0（A11Y-D3）：AX 档放宽
                        .a11yLineLimit(1, ax: 2)
                        Text(mediaSubtitle(entry))
                            .font(.rowSubtitle)
                            .foregroundStyle(Palette.inkSecondary)
                            .a11yLineLimit(1, ax: 2)
                    }
                }
                .frame(
                    maxWidth: .infinity, minHeight: 64,
                    alignment: .leading
                )
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.odPressable)
            Spacer(minLength: OneDayMetrics.spacingS)
            Menu {
                actionItems(
                    for: entry, among: snapshot.sortedMedia,
                    deliverable: snapshot.deliverable(for: entry)
                )
            } label: {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("更多操作")
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: 64)
        // §131：定位高亮（与文件行同口径）
        .background(
            revealedPath == entry.path
                ? Palette.selectionFill : Color.clear
        )
        .contentShape(Rectangle())
        .id(entry.path)
        // 0.43.0（A11Y-V7）：Rotor 行标记
        .accessibilityRotorEntry(id: entry.name, in: fileRotorNamespace)
        .contextMenu {
            actionItems(
                for: entry, among: snapshot.sortedMedia,
                deliverable: snapshot.deliverable(for: entry)
            )
        }
    }

    private func mediaSubtitle(
        _ entry: WorkspaceFileEntry
    ) -> String {
        let size = entry.size.map {
            ByteCountFormatter.string(
                fromByteCount: $0, countStyle: .file
            )
        }
        let date = AdminFormat.short(entry.modifiedAt)
        return [typeTag(for: entry), size, date]
            .compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: - 条目动作（按类型适配，附记硬规矩）

    /// ⋮ 与长按共用同一动作集：FileActionPolicy.menu-
    /// Actions 按类型出项（文本类多复制文字/导出
    /// PDF、二进制只给分享/下载/删除），删除项红色
    @ViewBuilder
    private func actionItems(
        for entry: WorkspaceFileEntry,
        among siblings: [WorkspaceFileEntry],
        deliverable: Deliverable
    ) -> some View {
        ForEach(
            FileActionPolicy.menuActions(for: entry), id: \.self
        ) { action in
            if action == .delete {
                Button(role: .destructive) {
                    pendingDelete = deliverable
                } label: {
                    Label(
                        action.label,
                        systemImage: action.systemImage
                    )
                }
            } else {
                Button {
                    perform(action, on: entry, among: siblings)
                } label: {
                    Label(
                        action.label,
                        systemImage: action.systemImage
                    )
                }
            }
        }
    }

    private func perform(
        _ action: FileItemAction,
        on entry: WorkspaceFileEntry,
        among siblings: [WorkspaceFileEntry]
    ) {
        switch action {
        case .preview:
            openEntry(entry, among: siblings)
        case .copyText:
            Task { await copyText(entry) }
        case .exportPDF:
            Task { await exportPDF(entry) }
        case .share, .download:
            // 分享与下载到本地同走系统分享单（全 App
            // 既有口径：取回临时文件→分享单，含「存
            // 储到文件」出口）
            Task { await download(entry) }
        case .delete:
            // 删除在菜单构造处直接挂确认（actionItems），
            // 不经本分发
            break
        case .pin, .unpin, .rename, .openInFiles:
            // 条目菜单（menuActions）不出这四项（打开页
            // 专属，见 openPageActions），落到即策略表
            // 漂移——静默不执行
            break
        }
    }

    /// 条目打开分流：先写上次打开记录；图片直达查
    /// 看器（集合＝同段全部图片、可翻页）；其余一律
    /// 落文件打开页（§125 中间页，类型内分流归它）
    private func openEntry(
        _ entry: WorkspaceFileEntry,
        among siblings: [WorkspaceFileEntry]
    ) {
        openHistory.record(path: entry.path)
        if entry.mediaKind == .image {
            let images = siblings.filter {
                $0.mediaKind == .image
            }
            viewerRoute = ImageViewerRoute(
                entries: images,
                initialIndex: images.firstIndex(of: entry) ?? 0
            )
        } else {
            // §125：文本类不再从本面直达阅读页——与
            // 聊天/文件浏览器同路先进中间页（单源壳）
            previewEntry = entry
        }
    }

    /// 影音网格预取（§144）：以刚露面的格为锚，向后
    /// 6 格（2 行）的图片/视频先把 360 档/海报暖进缩
    /// 略缓存（FileThumbnailStore 自带去重与并发闸，
    /// 已缓存的格零成本跳过）；滚动中只做占位→360
    /// 的单向填充，不阻塞布局
    private func prefetchMedia(
        after entry: WorkspaceFileEntry,
        among sorted: [WorkspaceFileEntry]
    ) {
        guard let index = sorted.firstIndex(
            where: { $0.path == entry.path }) else { return }
        let upcoming = sorted
            .dropFirst(index + 1).prefix(6)
            .filter {
                $0.mediaKind == .image || $0.mediaKind == .video
            }
        guard !upcoming.isEmpty else { return }
        Task {
            for next in upcoming {
                _ = await FileThumbnailStore.shared.thumbnail(
                    for: next, targetPixelSize: 360,
                    loader: FileThumbnailStore.originalLoader(
                        appState: appState, path: next.path),
                    renditionLoader: FileThumbnailStore
                        .renditionLoader(
                            appState: appState, path: next.path)
                )
            }
        }
    }

    private func fetchData(
        _ entry: WorkspaceFileEntry
    ) async throws -> Data {
        try await appState.performAdmin { client, config in
            try await client.fileData(config: config, path: entry.path)
        }
    }

    private func copyText(_ entry: WorkspaceFileEntry) async {
        do {
            let data = try await fetchData(entry)
            guard let text = FileTextExtractor.plainText(
                from: data, entry: entry
            ) else {
                notice = "「\(entry.name)」没能读出文字。"
                Haptics.error()
                return
            }
            UIPasteboard.general.string = text
            notice = "已复制「\(entry.name)」的文字。"
            Haptics.success()
        } catch {
            notice = (error as? HermesError)?.userMessage
                ?? "文件没读出来，可能是网络或服务暂时没响应"
            Haptics.error()
        }
    }

    private func exportPDF(_ entry: WorkspaceFileEntry) async {
        do {
            let data = try await fetchData(entry)
            guard let text = FileTextExtractor.plainText(
                from: data, entry: entry
            ) else {
                notice = "「\(entry.name)」没能读出文字，无法导出 PDF。"
                Haptics.error()
                return
            }
            let kind = DocumentTextKind.kind(
                forFileName: entry.name
            ) ?? .plain
            let title = DeliverableFileType.displayTitle(
                forFileName: entry.name
            )
            guard let pdf = DocumentPDFExporter.pdfData(
                title: title,
                blocks: DocumentReading.blocks(
                    for: text, kind: kind
                )
            ) else {
                notice = "导出 PDF 失败，请稍后再试。"
                Haptics.error()
                return
            }
            shareItem = try FileShareItem.write(
                data: pdf, name: "\(title).pdf"
            )
        } catch {
            notice = (error as? HermesError)?.userMessage
                ?? "导出 PDF 失败，请稍后再试。"
            Haptics.error()
        }
    }

    /// 查看器内删除（0.36.4）：与行删除同通道（§369
    /// 起同走名单店本地摘行＋真接口删、不重聚合）；
    /// 落锤触感已由查看器在点删时发过、本处成功不
    /// 叠、失败 error
    private func deleteFromViewer(_ entry: WorkspaceFileEntry) async {
        let outcome = await listStore.delete(
            paths: [entry.path]
        ) { path in
            try await appState.performAdmin { client, config in
                try await client.deleteFile(
                    config: config, path: path,
                    recursive: false
                )
            }
        }
        switch outcome {
        case .success:
            notice = "已删除「\(entry.name)」。"
        case .failed(let message):
            notice = message
            Haptics.error()
        }
    }

    // MARK: - 定位消费（§131「在文件页中打开」）

    /// 定位请求消费：聚合未完成先不消费（collect 末
    /// 尾再试）；消费即清零请求、收栈回根、清搜索
    /// ——命中聚合集切到对应段滚动高亮；不在聚合集
    /// 的文件（任意服务器路径）落系统文件浏览器父
    /// 目录＋文件名高亮，不假装它在文件页收录里
    private func consumeRevealIfReady() {
        guard let path = appState.router.fileRevealPath else { return }
        guard deliverables != nil else { return }
        appState.router.fileRevealPath = nil
        systemFilesRoute = nil
        previewEntry = nil
        viewerRoute = nil
        query = ""
        // §363：成员判定走快照过滤（不付排序账）
        let base = LibraryListSnapshot.filtered(
            deliverables: deliverables, query: query
        )
        if base.documents.contains(
            where: { $0.entry.path == path }
        ) {
            segment = 0
            flashReveal(path: path)
        } else if base.mediaItems.contains(
            where: { $0.entry.path == path }
        ) {
            segment = 1
            flashReveal(path: path)
        } else {
            systemFilesRoute = SystemFilesRoute(
                dir: (path as NSString).deletingLastPathComponent,
                highlight: (path as NSString).lastPathComponent
            )
        }
    }

    private func flashReveal(path: String) {
        revealedPath = path
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if revealedPath == path { revealedPath = nil }
        }
    }

    // MARK: - 聚合与动作（A-06 服务端读面）

    /// 聚合集只从伴生文件库读面单流消费（GET /file-
    /// library，伴生 1.0.66）：产出根走查、准入、去重、
    /// mtime 倒序全在服务端（oneday_seg_filelibrary
    /// 为单一事实源），本函数只做条目映射。0.50.60 前
    /// 的客户端 BFS 爬 /api/files（8 根硬编码、深度 3、
    /// 600 静默截断、客户端准入）已整套退役。
    /// 排序不在此处定案——视图层按页级排序状态走
    /// LibraryOrdering（本函数只负责聚合集本身）。
    /// 失败口径：首拉失败给错误态；已有数据时刷新失败
    /// 保留旧集不清屏（回响链同口径）
    /// §369（缓存 C4）：聚合走名单店对账——店内先以
    /// 落盘快照播种（冷启不等网络先上屏）、再恰一次
    /// 全量拉取差异合并换新；本函数只做接线（桥读面
    /// 单流）与既有 loadError 口径回填：无数据失败／
    /// 无配置才给错误态、成功且非空清错误、已有数据
    /// 刷新失败保留旧集不清屏（店内已保、本处不置错）
    private func collect() async {
        let outcome = await listStore.refresh(
            currentConfigKey: appState.config?.baseString
        ) {
            guard let config = appState.config else {
                // 键非 nil 时配置同源必在；店内当前键
                // 为 nil 时不会调用本闭包
                throw HermesError.sessionExpired
            }
            let page = try await bridgeClient.fileLibrary(
                config: config
            )
            return page.items.map {
                Deliverable(entry: $0.entry, source: $0.source)
            }
        }
        switch outcome {
        case .loaded:
            if !(deliverables?.isEmpty ?? true) {
                loadError = nil
            }
            // 聚合落定后补消费定位请求（请求先于数
            // 据到达时 onChange 已触发过、那时 deli-
            // verables 为空未消费，见 consumeReveal-
            // IfReady 的守卫）
            consumeRevealIfReady()
        case .noConfig, .failedNoData:
            if deliverables == nil {
                loadError = "产出目录没读出来，可能是网络或服务暂时没响应"
            }
        case .keptAfterFailure, .alreadyInFlight:
            break
        }
    }

    /// §369（缓存 C4）：删除走名单店本地摘行——先摘
    /// 行上屏、真接口确认，成功不整表重拉；失败店内
    /// 原位回滚，本处只管回执与触感
    private func delete(_ item: Deliverable) async {
        let outcome = await listStore.delete(
            paths: [item.entry.path]
        ) { path in
            try await appState.performAdmin { client, config in
                try await client.deleteFile(
                    config: config, path: path,
                    recursive: false
                )
            }
        }
        switch outcome {
        case .success:
            notice = "已删除「\(item.entry.name)」。"
            // 成功无触感：确认时的 heavy 落锤已代表
            // 本链（规格 §2.3，同一因果链只震一次）
        case .failed(let message):
            notice = message
            // 失败改判 error（0.36.2，表 D 语义归位）
            Haptics.error()
        }
    }

    /// 分享＝先把文件取回本机临时文件再调系统分享单
    /// （FileShareItem/FileShareSheet，P8 同通道）
    private func download(_ entry: WorkspaceFileEntry) async {
        do {
            let data = try await fetchData(entry)
            shareItem = try FileShareItem.write(
                data: data, name: entry.name
            )
        } catch {
            notice = (error as? HermesError)?.userMessage
                ?? "下载失败，请稍后再试。"
        }
    }
}

/// 交付物：工作区文件条目＋来源（产出目录语义名；
/// 来源只作数据层记录与排查，本页行副题按图只给类
/// 型词、不上屏来源）
struct Deliverable: Identifiable, Equatable {
    let entry: WorkspaceFileEntry
    let source: String

    var id: String { entry.path }

    var subtitle: String {
        let size = entry.size.map {
            ByteCountFormatter.string(
                fromByteCount: $0, countStyle: .file
            )
        }
        let date = AdminFormat.short(entry.modifiedAt)
        return [source, size, date]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
