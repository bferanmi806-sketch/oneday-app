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
        .frame(maxWidth: .infinity, alignment: .leading)
        // §303 定高桥：内容高指纹（资源库区有无／
        // 确认行有无）喂呈现控制器 custom detent，
        // 高度在呈现层单源求解（见桥本体注）
        .background(
            AttachmentSheetDetentBridge(
                fingerprint: (showsLibrary ? 1 : 0)
                    | (selectedIDs.isEmpty ? 0 : 2)
            )
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
    /// §303（A-08 定高收口）：附件面板呈现口径单
    /// 源——拖拽指示走 SwiftUI 声明；定高不在此
    /// 处：由面板内的 AttachmentSheetDetentBridge
    /// 以 UIKit custom detent 在呈现控制器内求解
    /// （SwiftUI 无 iPhone 底部 sheet 的内容贴合
    /// 原语：.presentationSizing(.fitted) 经装配实
    /// 测不改变 sheet 高，§303.1）。ChatView 呈现
    /// 点与装配测试共用本口径，不许在别处另抄一份
    func attachmentPanelPresentation() -> some View {
        self
            .presentationDragIndicator(.visible)
    }
}

/// §303（A-08 定高收口）：附件面板 sheet 定高桥
/// ——UIKit 文档正道 `UISheetPresentationControl-
/// ler.Detent.custom(resolver:)`：resolver 在呈
/// 现控制器求解 detent 时，以系统布局对呈现内
/// 容取理想高（托管视图 sizeThatFits、无界高查
/// 询，与当前 detent 无关、无 §154 式自指），钳
/// 顶只认 context.maximumDetentValue（系统单
/// 源）；量测不可用时回半高（与旧 .medium 兜底
/// 同档、面板照常打开）。内容理想高只由指纹决
/// 定（资源库区有无／确认行有无——照片数与缩略
/// 图到达不改高），指纹变才 invalidateDetents
/// 触发重解；detent 集若被 SwiftUI 呈现层重置，
/// 每次 apply 按 identifier 自愈重断言。
struct AttachmentSheetDetentBridge: UIViewRepresentable {
    var fingerprint: Int

    func makeUIView(context: Context) -> BridgeView {
        BridgeView()
    }

    func updateUIView(_ uiView: BridgeView, context: Context) {
        uiView.apply(fingerprint: fingerprint)
    }

    final class BridgeView: UIView {
        private static let detentID =
            UISheetPresentationController.Detent.Identifier(
                "attachmentPanel.fit"
            )
        private var lastFingerprint: Int?
        /// §317：过渡期被守卫拦下的指纹 invalidate
        /// 待补旗——过渡落定后的下一次 apply 在此补
        /// 触发（见 apply 尾段）
        private var detentRefreshPending = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // 进窗拍可能早于呈现布局完成，下一轮以
            // 已存指纹再断言一次（apply 幂等）
            let fingerprint = lastFingerprint ?? 0
            DispatchQueue.main.async { [weak self] in
                self?.apply(fingerprint: fingerprint)
            }
        }

        func apply(fingerprint: Int) {
            guard let host = enclosingViewController(),
                  let sheet = host.sheetPresentationController
            else { return }
            // §303.2 候选②（候选①实测不净后换）：
            // 托管视图底部安全区源头归零——§303.1/
            // §303.2 量测律：in-sheet 量测计入底部
            // 安全区 +34、帧关系再按托管视图安全
            // 区叠一层 +34；候选①只减量测侧、帧仍
            // +34。归零落点：safeAreaRegions 是
            // UIHostingController 类型化 API，本桥
            // 经响应链只拿到 SwiftUI所建 sheet 宿
            // 主的 UIViewController 泛型面、到达不
            // 了（首试编译实证），改走 UIViewCon-
            // troller 的 additionalSafeAreaInsets
            // 反向补偿：按当前实测总量反推区域分
            // 量并抵消（不写死数值；补偿后总量 0、
            // 重入不累加），量测与帧附加项同灭
            let totalBottom = host.view.safeAreaInsets.bottom
            if totalBottom != 0 {
                host.additionalSafeAreaInsets.bottom
                    = host.additionalSafeAreaInsets.bottom
                    - totalBottom
            }
            if sheet.detents.first?.identifier != Self.detentID {
                installDetents(sheet: sheet, host: host)
            }
            if lastFingerprint != fingerprint {
                lastFingerprint = fingerprint
                detentRefreshPending = true
            }
            // §317（诊断 P2 守卫，窄口径）：呈现/收起
            // 过渡期不触发指纹 invalidateDetents——过
            // 渡中途的 detent 重解会拉长/扰动收起动
            // 画，是呈现竞速的加重项；指纹只登记待
            // 补，落定后下一次 apply（内容更新/did-
            // MoveToWindow 既有再断言）在此补触发。
            // 补偿与首装不在守卫内：补偿是 §303 量
            // 测律的载荷口径，首轮宽守卫曾连它一并
            // 拦下、ATTACH-FIT 实测 safeBottom=34/
            // 高 +34·+68 签名判红（§317.1 登记）——
            // 延后即错值，故只守 invalidate 一项
            let transitioning = host.isBeingPresented
                || host.isBeingDismissed
                || host.transitionCoordinator != nil
            if detentRefreshPending, !transitioning {
                detentRefreshPending = false
                sheet.invalidateDetents()
            }
        }

        /// §303 定高本体：custom detent 整组安装（解
        /// 析器在呈现控制器内以 sizeThatFits 单源求
        /// 解，口径自 §303 未动）。apply 内唯一安装
        /// 点（§317 守卫只拦指纹 invalidate、不拦首
        /// 装），不许分叉出第二套定高写法
        private func installDetents(
            sheet: UISheetPresentationController,
            host: UIViewController
        ) {
            sheet.detents = [
                .custom(identifier: Self.detentID) {
                    [weak host] context in
                    guard let host else {
                        return context.maximumDetentValue
                            * 0.5
                    }
                    let width = host.view.bounds.width > 0
                        ? host.view.bounds.width
                        : (host.view.window?.bounds.width
                            ?? 0)
                    guard width > 0 else {
                        return context.maximumDetentValue
                            * 0.5
                    }
                    let fit = host.view.sizeThatFits(
                        CGSize(
                            width: width,
                            height: .greatestFiniteMagnitude
                        )
                    ).height
                    guard fit > 0 else {
                        return context.maximumDetentValue
                            * 0.5
                    }
                    return min(
                        fit, context.maximumDetentValue
                    )
                },
            ]
            sheet.selectedDetentIdentifier = Self.detentID
            sheet.invalidateDetents()
        }

        /// 响应链上首个视图控制器即 sheet 的托管
        /// 呈现控制器本体（本桥恒挂在呈现内容内）
        private func enclosingViewController()
            -> UIViewController?
        {
            var responder: UIResponder? = self
            while let current = responder {
                if let vc = current as? UIViewController {
                    return vc
                }
                responder = current.next
            }
            return nil
        }
    }
}
