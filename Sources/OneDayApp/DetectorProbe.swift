import SwiftUI
import UIKit

/// 【探针分支 probe/gen5-t4-detectors 专用，禁止合入任何线】
/// 包 5 T4 数据检测探针（筹备稿 chat-gen5-prep-20261114 §2.2-2）：
/// - DetectorProbeConfig：仅启动参 -odProbeDetectors 在场时生效，
///   给 SelectableTextRepresentable.makeUIView 的 dataDetectorTypes
///   提供覆写值；正常启动恒 nil＝产品口径 [] 不变。
/// - DetectorProbeScene：以真 MarkdownText（真承载＋真 Coordinator）
///   渲染语料行，场景层覆写环境 openURL 为录音动作，UI 探针据此
///   读「点按命中段后出口去了哪」。
enum DetectorProbeConfig {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-odProbeDetectors")
    }

    /// makeUIView 唯一消费点；nil＝不覆写（生产口径）
    static var detectorTypesOverride: UIDataDetectorTypes? {
        guard isEnabled else { return nil }
        for arg in ProcessInfo.processInfo.arguments
        where arg.hasPrefix("-odProbeDetectorsSet=") {
            switch String(arg.dropFirst("-odProbeDetectorsSet=".count)) {
            case "candidate":
                return [.phoneNumber, .link, .calendarEvent, .address]
            case "all":
                return .all
            case "phone":
                return [.phoneNumber]
            case "link":
                return [.link]
            case "calendar":
                return [.calendarEvent]
            case "address":
                return [.address]
            case "off":
                return []
            default:
                break
            }
        }
        return [.phoneNumber, .link, .calendarEvent, .address]
    }
}

struct DetectorProbeEntry: Equatable {
    let id: String
    let text: String
}

enum DetectorProbeCorpus {
    /// 单测引擎扫描＋文本视图链接显形共用全集
    static let all: [DetectorProbeEntry] = [
        .init(id: "phoneMobile", text: "13800138000"),
        .init(id: "phoneMixed", text: "有急事打 13800138000，或者座机 010-62558888，都能找到我。"),
        .init(id: "phoneIntl", text: "国际拨打 +86 138 0013 8000"),
        .init(id: "linkURL", text: "https://example.com/docs/guide?lang=zh"),
        .init(id: "linkBare", text: "文档在 www.example.org/guide 上，记得看。"),
        .init(id: "email", text: "inkroot001@gmail.com"),
        .init(id: "dateAbsZh", text: "2026年11月16日中午13:00"),
        .init(id: "dateAbsZhText", text: "婚礼定在 2026年11月16日中午 13:00，在村里办，提前一天回来。"),
        .init(id: "dateRelZh", text: "明天下午三点开会，后天上午十点再对一遍，今晚八点半先发我。"),
        .init(id: "dateEn", text: "The review is on November 20, 2026 at 3:30 PM, don't be late."),
        .init(id: "addrZh", text: "陕西省延安市洛川县土基镇西故现村"),
        .init(id: "addrZhText", text: "快递寄到陕西省延安市洛川县土基镇西故现村 12 号，收件人杨敏杰。"),
        .init(id: "addrCityText", text: "公司在西安市高陵区上品湾 43 号楼 2 单元 202 室，邮编 710200。"),
        .init(id: "addrEn", text: "350 5th Ave, New York, NY 10118"),
        .init(id: "fpOrder", text: "订单号 20261114160922334455 已支付 ¥1,299.00，发票随后发。"),
        .init(id: "fpIDs", text: "会话 bfb4e3ed，构建号 173，版本 0.50.45，端口 8642。"),
        .init(id: "fpTracking", text: "顺丰单号 SF1234567890123 已揽收，预计周三送达。"),
        .init(id: "fpFlight", text: "航班 CA1832 于 11月18日 17:55 起飞，座位 23A。"),
        .init(id: "fpNums", text: "一共 53 个工具，分三批：第一批 25 个、第二批 18 个、第三批 10 个。"),
        .init(id: "fpDateish", text: "11月14日那天他发了 3 条消息，最长一条 2045 字，用时 42 分钟。"),
        .init(id: "mixedLong", text: "王工你好，会议改到 2026年11月20日下午 2:30，地点在西安市高陵区上品湾 43 号楼会议室；会前把方案发到 inkroot001@gmail.com，有问题打 13800138000；材料在 https://example.com/plan 上先看一遍。另，昨天那笔订单 20261114160922334455 的发票还没收到。"),
        .init(id: "plainProse", text: "这是一段没有任何联系方式的普通文字，专门用来对照长按菜单的基线形态。"),
    ]

    /// UI 探针点按行：单目标短行，点中心即命中目标段
    static let tapRows: [DetectorProbeEntry] = [
        .init(id: "phoneMobile", text: "13800138000"),
        .init(id: "dateAbsZh", text: "2026年11月16日中午13:00"),
        .init(id: "addrZh", text: "陕西省延安市洛川县土基镇西故现村"),
        .init(id: "linkURL", text: "https://example.com/docs/guide?lang=zh"),
        .init(id: "email", text: "inkroot001@gmail.com"),
        .init(id: "plainProse", text: "这是一段没有任何联系方式的普通文字，专门用来对照长按菜单的基线形态。"),
    ]
}

/// openURL 录音机：探针场景把每次出口调用记进可见文本，
/// UI 探针读 accessibilityIdentifier=probe.openURLLog 的内容判定出口
final class DetectorProbeRecorder: ObservableObject {
    @Published var entries: [String] = []
}

struct DetectorProbeScene: View {
    @StateObject private var recorder = DetectorProbeRecorder()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("openURL 出口记录（点按命中段后看这里）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(recorder.entries.isEmpty ? "(空)" : recorder.entries.joined(separator: "\n"))
                    .font(.caption2)
                    .accessibilityIdentifier("probe.openURLLog")
                Divider()
                ForEach(DetectorProbeCorpus.tapRows, id: \.id) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.id)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        MarkdownText(entry.text)
                            .accessibilityIdentifier("probe.row.\(entry.id)")
                    }
                }
            }
            .padding()
        }
        .environment(\.openURL, OpenURLAction { url in
            recorder.entries.append(url.absoluteString)
            return .handled
        })
    }
}
