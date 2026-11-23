import OneDayDesign
import OneDayCore
import SwiftUI

/// 连接详情（设置·服务器）：0.6.0 直登口径——本页与
/// 欢迎页同字段（服务器地址＋密钥），改址/换钥在此编辑
/// 后「保存并测试」：走 AppState.connectDirect 两步校验，
/// 全过才落 Keychain（坏地址/坏钥匙不落盘）；另有「重新
/// 测试连接」用已存凭据复跑（存量三件套三步、直登两步，
/// AppState.retestConnection 内分流）。面板账号退出本页
/// （直登不依赖面板凭据；存量账号只在 Keychain 里供
/// 管理面自动重登，本页不展示）。
struct ServerDetailView: View {
    @Environment(AppState.self) private var appState

    @State private var serverText = ""
    @State private var apiKeyText = ""
    @State private var isSaving = false
    @State private var saveResult: String?
    @State private var saveFailed = false
    @State private var isRetesting = false
    @State private var retestResult: String?
    @State private var retestFailed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("这台服务器")
                    .padding(.bottom, OneDayMetrics.spacingS)
                VStack(spacing: 0) {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        StatusDot(color: retestFailed ? Palette.danger : Palette.success)
                        Text(retestFailed ? "连接异常" : "连接正常")
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                    }
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .frame(minHeight: OneDayMetrics.rowHeight)
                    GroupDivider()
                    // 地址/密钥字段走共用件（台账 198 收
                    // 敛 S3：ServerCredentialForm，与连接
                    // 页同一份；显隐切换自此统一 eye 钮，
                    // 本页原文字钮「显示/隐藏」退役）
                    ServerAddressFieldRow(text: $serverText)
                    GroupDivider()
                    ServerSecretFieldRow(
                        label: "密钥", text: $apiKeyText,
                        placeholder: "Hermes 的 Bearer 密钥"
                    )
                }
                .odGroup()

                if let saveResult {
                    Group {
                        if saveFailed {
                            InlineError(saveResult)
                        } else {
                            HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: FrameworkIcon.composerGlyphSize))
                                    .foregroundStyle(Palette.success)
                                    .accessibilityHidden(true)
                                Text(saveResult)
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.ink)
                            }
                        }
                    }
                    .padding(.top, OneDayMetrics.spacingM)
                }

                Button(isSaving ? "正在测试…" : "保存并测试") {
                    Task { await save() }
                }
                .buttonStyle(.odPrimary)
                .disabled(isSaving || !isEdited)
                .padding(.top, OneDayMetrics.spacingL)

                SectionLabel("连接测试")
                    .padding(.top, OneDayMetrics.sectionOuterSpacing)
                    .padding(.bottom, OneDayMetrics.spacingS)
                VStack(spacing: 0) {
                    Button {
                        Task { await retest() }
                    } label: {
                        HStack {
                            Text("重新测试连接")
                                .font(.body)
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            if isRetesting {
                                ProgressView()
                            }
                        }
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .frame(minHeight: OneDayMetrics.rowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.odPressable)
                    .disabled(isRetesting)
                    if let retestResult {
                        GroupDivider()
                        Group {
                            if retestFailed {
                                InlineError(retestResult)
                            } else {
                                HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
                                    Image(systemName: "checkmark.circle")
                                        .font(.system(size: FrameworkIcon.composerGlyphSize))
                                        .foregroundStyle(Palette.success)
                                        .accessibilityHidden(true)
                                    Text(retestResult)
                                        .font(.subheadline)
                                        .foregroundStyle(Palette.ink)
                                }
                            }
                        }
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .padding(.vertical, OneDayMetrics.spacingSM)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .odGroup()

                // 添加与配对（§450 收纳）：一次性引
                // 导不占设置根行——添加设备（出码入
                // 驻）与设备配对（平台用户准入）自根
                // 页服务器段收进本页，点达仍走设置路
                // 由原目的地（行为不变、只换门的位置）
                SectionLabel("添加与配对")
                    .padding(.top, OneDayMetrics.sectionOuterSpacing)
                    .padding(.bottom, OneDayMetrics.spacingS)
                VStack(spacing: 0) {
                    NavigationLink(value: SettingsRoute.addDevice) {
                        serverLinkRow(
                            title: "添加设备",
                            summary: "生成认领二维码，让新设备扫码连上这台服务器"
                        )
                    }
                    GroupDivider()
                    NavigationLink(value: SettingsRoute.pairingManagement) {
                        serverLinkRow(
                            title: "设备配对",
                            summary: "批准在消息平台上申请和网关对话的新用户"
                        )
                    }
                }
                .odGroup()

                // 版本与更新段（DESIGN §360；台账 36
                // 案 A 只读感知面，段本体自带取数）
                ServerVersionSection()

            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .navigationTitle("当前服务器")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // 进页回填已存值（只回填本机 Keychain 的值，
            // 不从任何远端取凭据）
            if serverText.isEmpty {
                serverText = appState.config?.baseString ?? ""
            }
            if apiKeyText.isEmpty {
                apiKeyText = appState.apiKey ?? ""
            }
        }
    }

    /// 页内导航行（§450）：与本页既有行同几何（横
    /// 向距＋行高），题＋副行＋右箭头
    private func serverLinkRow(
        title: String, summary: String
    ) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
            Spacer()
            DisclosureChevron(font: .system(size: FrameworkIcon.composerGlyphSize))
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: OneDayMetrics.rowHeight)
        .contentShape(Rectangle())
    }

    /// 有改动才许保存：与已存值逐字比对（地址按归一化前
    /// 的原文比，归一化在提交时做）
    private var isEdited: Bool {
        serverText != (appState.config?.baseString ?? "")
            || apiKeyText != (appState.apiKey ?? "")
    }

    private func save() async {
        saveResult = nil
        guard let config = ServerConfig(rawInput: serverText) else {
            saveFailed = true
            saveResult = HermesError.invalidServerAddress.userMessage
            // 失败改判 error（0.36.2，表 D 语义归位）
            Haptics.error()
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await appState.connectDirect(config: config, apiKey: apiKeyText)
            // 回填归一化后的值，isEdited 随之归零
            serverText = config.baseString
            apiKeyText = appState.apiKey ?? apiKeyText
            saveFailed = false
            saveResult = "已保存：健康检查与密钥验证都通过。"
            Haptics.success()
        } catch {
            saveFailed = true
            saveResult = (error as? HermesError)?.userMessage ?? "保存失败，请稍后再试。"
            // 失败改判 error（0.36.2，表 D 语义归位）
            Haptics.error()
        }
    }

    private func retest() async {
        isRetesting = true
        retestResult = nil
        defer { isRetesting = false }
        do {
            try await appState.retestConnection()
            retestFailed = false
            retestResult = "连接正常：校验全部通过。"
        } catch {
            retestFailed = true
            retestResult = (error as? HermesError)?.userMessage ?? "连接失败。"
        }
    }
}
