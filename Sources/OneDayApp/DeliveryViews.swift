import OneDayCore
import OneDayDesign
import SwiftUI

/// 助手侧登记交付项（§146，规格 delivery-registry-
/// spec-20261111 §7 消费契约）：正文标记只是号，
/// 呈现以登记端点回读的 meta 为唯一依据。状态机：
/// - meta 未到（在查/网络类查失败）：不显——不露
///   标记原文、不占位造假卡（与 §136 未确证不出
///   图同口径）；查失败不落账，下次渲染重查；
/// - 查无此号（404）：标记按纯文本原样显示——
///   规格 §4.2/§7.3，查不到就是一行符号文本，
///   不成卡、不拼路径；
/// - status=gone：一行安静文本「<文件名>（文件
///   已删除）」，不可点；
/// - status=stale：照常渲染、不加警示（文件被
///   更新不是错误，规格 §7.3）；
/// - kind=image：§130 定高卡出图（登记快照
///   thumb→cover 递进，无快照回落原图管线）；
/// - 其余 kind：§125 白卡形态的封面卡（cover
///   有则封面区＋名＋类型·大小；无 cover 走 §32
///   客户端管线回落，再无落 C8 图标行）。
struct AssistantDeliveryItem: View {
    @Environment(AppState.self) private var appState

    let id: String
    let onOpenImage: (BridgeDelivery) -> Void
    let onOpenFile: (BridgeDelivery) -> Void

    private let client = OneDayBridgeClient()

    var body: some View {
        Group {
            switch DeliveryStore.shared.metaResult(for: id) {
            case .loaded(let meta):
                loadedBody(meta)
            case .notFound:
                Text(DeliveryMarker.markerText(for: id))
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case nil:
                EmptyView()
            }
        }
        .task(id: id) {
            await DeliveryStore.shared.loadMeta(
                id: id, client: client, appState: appState
            )
        }
    }

    @ViewBuilder
    private func loadedBody(_ meta: BridgeDelivery) -> some View {
        if meta.status == .gone {
            Text(L10n.format("%@（文件已删除）", meta.name))
                .font(.callout)
                .foregroundStyle(Palette.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if meta.kind == "image" {
            DeliveryImageView(meta: meta, client: client) {
                onOpenImage(meta)
            }
        } else {
            DeliveryFileCard(meta: meta, client: client) {
                onOpenFile(meta)
            }
        }
    }
}

/// 登记图片的内联出图（§146）：卡形走 §130 定
/// 高卡（卡宽先按 meta 实测宽高算、图未到版式已
/// 定）；图源走登记快照递进——thumb（360）先
/// 到先显、cover（1080）到后换上；登记时无快
/// 照（cover 两档皆 false）或快照都取不到时，
/// 回落 §130 既有原图管线（ServerRemoteImage，
/// 自带占位/失败态）。点开/无障碍与 §136 图片
/// 行同口径（宿主回 ChatView 的查看器入口）。
struct DeliveryImageView: View {
    @Environment(AppState.self) private var appState

    let meta: BridgeDelivery
    let client: OneDayBridgeClient
    let onOpen: () -> Void

    @State private var thumb: UIImage?
    @State private var cover: UIImage?
    @State private var snapshotsSettled = false

    private var hasSnapshots: Bool {
        meta.cover.thumb || meta.cover.cover
    }

    private var displayImage: UIImage? { cover ?? thumb }

    var body: some View {
        // §379：原「点按手势＋自研按压修饰」迁原生
        // Button＋.odPressable（清点 #22 整件退役）；
        // 无障碍语义改由真 Button 承载
        Button {
            onOpen()
        } label: {
            Group {
                if !hasSnapshots
                    || (snapshotsSettled && displayImage == nil) {
                    // 无快照/快照全取不到：原图管线兜底
                    ServerRemoteImage(path: meta.path)
                } else if let displayImage {
                    let sizingBase = meta.imagePixelSize
                        ?? displayImage.size
                    let cardSize = ChatImageSizing.cardSize(
                        for: sizingBase
                    )
                    let fittedSize = ChatImageSizing.fittedSize(
                        for: displayImage.size,
                        in: cardSize
                    )
                    ZStack {
                        Image(uiImage: displayImage)
                            .resizable()
                            .frame(
                                width: fittedSize.width,
                                height: fittedSize.height
                            )
                    }
                    .frame(
                        width: cardSize.width,
                        height: cardSize.height
                    )
                    .background(
                        Palette.bubbleFill,
                        in: RoundedRectangle(
                            cornerRadius: OneDayMetrics.radiusCard
                        )
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: OneDayMetrics.radiusCard
                        )
                    )
                } else {
                    // 快照在路上：§130 占位卡同高，不跳动
                    RoundedRectangle(
                        cornerRadius: OneDayMetrics.radiusCard
                    )
                    .fill(Palette.bubbleFill)
                    .frame(
                        width: ChatImageSizing.placeholderCardSize.width,
                        height: ChatImageSizing.placeholderCardSize.height
                    )
                    .overlay { ProgressView() }
                }
            }
        }
        .buttonStyle(.odPressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            A11yText.imageLabel(fileName: meta.name)
        )
        .accessibilityHint(L10n.string("查看大图"))
        .task(id: meta.id) { await loadSnapshots() }
    }

    private func loadSnapshots() async {
        guard hasSnapshots else { return }
        if meta.cover.thumb, thumb == nil,
           let data = await DeliveryStore.shared.image(
               id: meta.id, variant: .thumb,
               client: client, appState: appState
           ) {
            thumb = UIImage(data: data)
        }
        if meta.cover.cover, cover == nil,
           let data = await DeliveryStore.shared.image(
               id: meta.id, variant: .cover,
               client: client, appState: appState
           ) {
            cover = UIImage(data: data)
        }
        snapshotsSettled = true
    }
}

/// 登记文件的封面卡（§146，§125 白卡形态）：白
/// 卡＝封面区（有封面时通栏）＋文件名（.body
/// semibold、至多 2 行）＋副行「类型 · 大小」；
/// 大小是登记时端点实测的真值（meta.size），不
/// 走文件牌的回填链、不编造。封面形态（§407
/// 定高）：只认登记旗 meta.cover.cover——在册
/// 即恒预留 148 封面区，取数序＝登记快照 cover
/// → §32 客户端管线回落填同区，都无则占位面落
/// 类型图标；不在册恒 C8 类型图标行（File-
/// IconBox），管线缩略图不再撑起封面区。点开
/// 落点由宿主给（§125 FileOpenView 中间页）。
struct DeliveryFileCard: View {
    @Environment(AppState.self) private var appState

    let meta: BridgeDelivery
    let client: OneDayBridgeClient
    let onOpen: () -> Void

    @State private var coverImage: UIImage?
    /// §407：封面取数已穷尽（快照＋管线皆空）——
    /// 占位面自此落类型图标、不再挂菊花
    @State private var coverSettled = false

    /// §32 客户端管线用的合成条目：名/路径/大小
    /// 全是登记实测，其余按名称口径推导——与
    /// FileChip 的合成条目同法
    private var entry: WorkspaceFileEntry {
        WorkspaceFileEntry(
            name: meta.name, path: meta.path, isDirectory: false,
            size: meta.size, mtime: nil, mimeType: meta.mime
        )
    }

    private var subtitle: String {
        let type = DeliverableFileType.label(forFileName: meta.name)
        let sizeText = ByteCountFormatter.string(
            fromByteCount: meta.size, countStyle: .file
        )
        return "\(type) · \(sizeText)"
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                // §407（文件行定高）：封面区按登记
                // 旗预留——cover 在册即恒占 148，图
                // 未到显占位面、到后只换图；不在册
                // 恒图标行形态。旧形态按 coverImage
                // 到达态出没封面区＝到图换高，退役
                // （合成器 deliveryFileCardHeight 同
                // 判：形态只认 meta.cover.cover）
                if meta.cover.cover {
                    if let coverImage {
                        Image(uiImage: coverImage)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 148)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Palette.bubbleFill)
                            .frame(maxWidth: .infinity)
                            .frame(height: 148)
                            .overlay {
                                if coverSettled {
                                    FileIconBox(
                                        name: meta.name,
                                        size: 40
                                    )
                                } else {
                                    ProgressView()
                                }
                            }
                    }
                }
                HStack(spacing: OneDayMetrics.spacingSM) {
                    if !meta.cover.cover {
                        FileIconBox(name: meta.name, size: 40)
                    }
                    VStack(
                        alignment: .leading,
                        spacing: OneDayMetrics.spacingXS
                    ) {
                        Text(meta.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, OneDayMetrics.spacingSM)
                .padding(.vertical, OneDayMetrics.cardInnerGap)
            }
            .background(
                Palette.surface,
                in: RoundedRectangle(
                    cornerRadius: OneDayMetrics.radiusPreview
                )
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: OneDayMetrics.radiusPreview
                )
            )
            .contentShape(
                RoundedRectangle(
                    cornerRadius: OneDayMetrics.radiusPreview
                )
            )
        }
        .buttonStyle(.odPressable)
        .task(id: meta.id) { await loadCover() }
    }

    private func loadCover() async {
        // §407：取图只许填已预留的封面区——登记旗
        // 不在册时整路不跑（恒图标行形态，管线缩
        // 略图不再把卡撑成封面形态）
        guard meta.cover.cover, coverImage == nil,
              !coverSettled
        else { return }
        if let data = await DeliveryStore.shared.image(
            id: meta.id, variant: .cover,
            client: client, appState: appState
        ),
           let image = UIImage(data: data) {
            coverImage = image
            return
        }
        // 登记快照取不到：§32 客户端管线回落填同
        // 一预留区（QL 首面/降采样）；再无则占位
        // 面落类型图标、形态不变
        coverImage = await FileThumbnailStore.shared.thumbnail(
            for: entry, targetPixelSize: 720
        ) {
            try? await appState.performAdmin { client, config in
                try await client.fileData(
                    config: config, path: meta.path
                )
            }
        }
        coverSettled = true
    }
}
