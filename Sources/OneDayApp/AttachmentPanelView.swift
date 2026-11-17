import OneDayCore
import OneDayDesign
import Photos
import SwiftUI
import UIKit

/// 附件面板（§147 立、§152 修订二）：「+」点开自底部
/// 升起的 sheet，照 Muse 形态——顶部「资源库」区
/// （左标题、右「查看全部」蓝链）＋横滑缩略图条
/// （首格相机、其后最近照片）；下半动作行「添加文
/// 件／添加视频」。§152 修订（用户 19:47 对照截图点
/// 名）：定高贴内容、照片格放大近方形、照片条改
/// 多选——点照片切换选中态（右上角勾选标记），选
/// 了至少一张时动作行上方出「添加 N 张」确认行，
/// 点之批量入待发附件条；未选时无确认行（与 Core
/// addSelectedTitle 的 nil 同源）。单张快选不回
/// 退：选 1 张点添加即走，与旧直达同效。
/// §303（A-08 定高收口）：定高机制自 §152/§154 的
/// 自造量测回路（本视图经 PreferenceKey 回报内容
/// 高→宿主状态→Core 决策→.height detent）改走
/// UIKit custom detent resolver 在呈现控制器内定
/// 高（本文件 AttachmentSheetDetentBridge）——高
/// 度由系统布局按内容理想尺寸单源求解，量测回
/// 路整套退役。SwiftUI .presentationSizing
/// (.fitted) 先行试过、经装配实测在 iPhone 底部
/// sheet 上不改变高度（§303.1），不取。
/// §326（小修批①，用户 2026-11-17 拍板）：精确贴
/// 合整套退役——custom detent resolver＋安全区反
/// 向补偿＋指纹 invalidate＋§317 过渡守卫（桥本
/// 体）全删，定高改系统 detent 档位 [.medium,
/// .large]（呈现口径见 attachmentPanelPresentat-
/// ion）；面板内容不再决定 sheet 高，确认行增减
/// 只改内容不改高。代价如实记：无库态内容约
/// 137pt、sheet 恒半高，内容顶锚、下方留白——
/// 换来的是定高零自造、与系统 sheet 行为全同构。
///
/// 授权纪律：照片条只同步读 PHPhotoLibrary 现态
/// （系统授权铁律：已决定绝不重走请求、未决定也不
/// 在此发请求——本面板不是授权流）；未授权时资源
/// 库区整段不显，动作行照常（选图器由系统代管、
/// 不需本 App 相册授权）。有限授权下 PHAsset 取数
/// 天然只回已授权子集，不另过滤。缩略图与原图数
/// 据都走 PHImageManager 既有系统通道。
struct AttachmentPanelView: View {
    /// 相机格点选（宿主收面板后开相机）
    let onCamera: () -> Void
    /// 确认批量入条（入参资产 localIdentifier 数组，
    /// 按照片条呈现序——Core orderedSelection 收口）
    let onConfirmPhotos: ([String]) -> Void
    /// 「查看全部」（宿主收面板后开全量选图器）
    let onViewAll: () -> Void
    /// 「添加文件」（宿主收面板后开文件选择器，
    /// §317 起走 DocumentPickerView 状态旗呈现）
    let onAddFile: () -> Void
    /// 「添加视频」（宿主收面板后开视频选图器）
    let onAddVideo: () -> Void

    @State private var photoIDs: [String] = []
    @State private var thumbnails: [String: UIImage] = [:]
    /// 照片条多选选中集（§152）：面板本地态，关面
    /// 板即弃——入条只认确认动作，不留半截选择
    @State private var selectedIDs: Set<String> = []
    /// 照片条取数代次（§303／A-24 顺带）：每次
    /// loadStrip 自增；PHImageManager 回调无取消
    /// 句柄，迟到回写按代次丢弃——面板快速开关/
    /// 重载后旧代的低清图不许覆写新代结果
    @State private var stripLoadGeneration = 0

    /// 照片条格边长（形态值，§152 修订：照 Muse 截
    /// 图近方形大格口径自 §147 的 76 放大；对屏宽约
    /// 390 的实测占比约 30%，一屏约 3 格＋露边引导横
    /// 滑；间距仍走 OneDayMetrics 梯队）
    private static let cellSize: CGFloat = 118

    /// 同步读现态（不在此发任何授权请求）
    private var photoAccess: AttachmentPanel.PhotoAccess {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized: return .authorized
        case .limited: return .limited
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    private var showsLibrary: Bool {
        AttachmentPanel.showsLibrary(access: photoAccess)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingM) {
            if showsLibrary {
                librarySection
            }
            if let confirmTitle = AttachmentPanel.addSelectedTitle(
                count: selectedIDs.count
            ) {
                confirmRow(title: confirmTitle)
            }
            actionRows
        }
        .padding(OneDayMetrics.spacingM)
        // §326：系统 detent 档位下 sheet 高恒大于内
        // 容高——内容顶锚（顶左对齐、向下吃满），
        // 不许居中漂浮
        .frame(
            maxWidth: .infinity, maxHeight: .infinity,
            alignment: .topLeading
        )
        .task {
            loadStrip()
        }
    }

    // MARK: - 资源库区

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingSM) {
            HStack {
                Text("资源库")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Button("查看全部") { onViewAll() }
                    .font(.body)
                    .foregroundStyle(Palette.primary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OneDayMetrics.spacingS) {
                    ForEach(
                        AttachmentPanel.stripCells(photoIDs: photoIDs),
                        id: \.self
                    ) { cell in
                        switch cell {
                        case .camera:
                            cameraCell
                        case .photo(let id):
                            photoCell(id: id)
                        }
                    }
                }
            }
        }
    }

    private var cameraCell: some View {
        Button {
            onCamera()
        } label: {
            Image(systemName: "camera")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(Palette.ink)
                .frame(width: Self.cellSize, height: Self.cellSize)
                .background(
                    Palette.bubbleFill,
                    in: RoundedRectangle(
                        cornerRadius: OneDayMetrics.radiusCard
                    )
                )
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: OneDayMetrics.radiusCard
                    )
                )
        }
        .buttonStyle(.odPressable)
        .disabled(
            !UIImagePickerController.isSourceTypeAvailable(.camera)
        )
        .accessibilityLabel("拍照")
    }

    private func photoCell(id: String) -> some View {
        let selected = selectedIDs.contains(id)
        return Button {
            selectedIDs = AttachmentPanel.toggledSelection(
                selectedIDs, id: id
            )
        } label: {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image = thumbnails[id] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Palette.bubbleFill
                    }
                }
                .frame(width: Self.cellSize, height: Self.cellSize)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: OneDayMetrics.radiusCard
                    )
                )
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Palette.primary)
                        .padding(OneDayMetrics.spacingXS)
                        .shadow(radius: 2)
                }
            }
            .contentShape(
                RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard)
            )
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel("照片")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - 确认行（§152 多选）

    /// 「添加 N 张」确认行：照动作行形态（图标＋标
    /// 题行、minHeight 同档），标题带实时已选计数；
    /// 点之按条内呈现序批量入条（Core 收口）
    private func confirmRow(title: String) -> some View {
        Button {
            onConfirmPhotos(
                AttachmentPanel.orderedSelection(
                    selected: selectedIDs, stripOrder: photoIDs
                )
            )
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Palette.primary)
                    .frame(width: 28)
                Text(title)
                    .font(.body)
                    .foregroundStyle(Palette.primary)
                Spacer()
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
    }

    // MARK: - 动作行

    private var actionRows: some View {
        VStack(spacing: 0) {
            actionRow(icon: "paperclip", title: "添加文件") {
                onAddFile()
            }
            Divider()
                .overlay(Palette.separator)
            actionRow(icon: "play.circle", title: "添加视频") {
                onAddVideo()
            }
        }
    }

    private func actionRow(
        icon: String, title: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 28)
                Text(title)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                Spacer()
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
    }

    // MARK: - 照片条取数

    /// 取最近照片 id（创建时间倒序、上限 Core 定版）
    /// ＋逐格缩略图：fetch 在有限授权下只回已授权子
    /// 集（系统收敛）；缩略图走 PHImageManager 机
    /// 会式交付、先低清后高清同格替换
    private func loadStrip() {
        guard showsLibrary else { return }
        stripLoadGeneration += 1
        let generation = stripLoadGeneration
        let options = PHFetchOptions()
        options.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: false)
        ]
        options.fetchLimit = AttachmentPanel.stripPhotoLimit
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var ids: [String] = []
        var assets: [String: PHAsset] = [:]
        result.enumerateObjects { asset, _, _ in
            ids.append(asset.localIdentifier)
            assets[asset.localIdentifier] = asset
        }
        photoIDs = ids
        let manager = PHImageManager.default()
        let thumbOptions = PHImageRequestOptions()
        thumbOptions.deliveryMode = .opportunistic
        thumbOptions.resizeMode = .fast
        let side = Self.cellSize * 2
        for id in ids {
            guard let asset = assets[id] else { continue }
            manager.requestImage(
                for: asset,
                targetSize: CGSize(width: side, height: side),
                contentMode: .aspectFill,
                options: thumbOptions
            ) { image, _ in
                guard let image else { return }
                Task { @MainActor in
                    // A-24：代次已过（重载/快速开关后
                    // 旧请求迟到）一律丢弃，不覆写新代
                    guard generation == stripLoadGeneration
                    else { return }
                    thumbnails[id] = image
                }
            }
        }
    }
}

extension View {
    /// 附件面板呈现口径单源——§326 起定高走系统
    /// detent 档位 [.medium, .large]（开在 .medium、
    /// 可上拖至 .large），拖拽指示同走 SwiftUI 声
    /// 明；§303 的 AttachmentSheetDetentBridge
    /// （custom detent 精确贴合＋安全区反向补偿）
    /// 已整套退役、不得复活。ChatView 呈现点与装
    /// 配测试共用本口径，不许在别处另抄一份
    func attachmentPanelPresentation() -> some View {
        self
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
    }
}
