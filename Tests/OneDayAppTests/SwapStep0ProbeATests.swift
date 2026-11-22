import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 换引擎施工图步骤 0 · 探针 A（清点 #5 行高影子合成器去留）：
/// 真实托管视图量测（离屏 UIHostingController.sizeThatFits）与
/// 影子公式合成器（ChatNativeRowHeightComposer）逐 facet 对拍，
/// 并量两条路的成本。判定问题只有一个：托管量测能否替代公式
/// 成为行高来源。判据三条（沿 §329 口径）：①逐 facet 一致性
/// ——fit(无界) 与 fit(以合成高回喂) 均须与合成高 ±1pt 内；
/// ②成本——单行 µs 与 300 行冷量测总时（对照 120Hz 帧预算
/// 8.3ms 与量测台「开会话全表预量」的用途）；③线程——现行量
/// 测台（§331）在后台串行队列算高，托管量测若只能主线程，
/// 则全表预量须搬回主线程、与量测台立台目的冲突。
/// 本文件只产数与结论，不改任何生产码。环境与拟合钉测同口径
/// （屏宽 402／.large／scale 3），保证与 §329 既证账可比。
@MainActor
final class SwapStep0ProbeATests: XCTestCase {

    private let screenW: CGFloat = 402
    private var contentW: CGFloat { screenW - 40 }
    private var textW: CGFloat {
        screenW * OneDayMetrics.assistantTextWidthFraction
    }

    private func makeComposer(
        ledger: ChatRowStateLedger
    ) -> ChatNativeRowHeightComposer {
        ChatNativeRowHeightComposer(
            screenWidth: screenW,
            horizontalPadding: OneDayMetrics.pageGutter,
            sizeCategory: .large,
            boldText: false,
            displayScale: 3,
            ledger: ledger,
            hubStore: AppState().sharedHubStore(),
            agentDisplayName: "Hermes",
            emptyStateAvatarSize: 72
        )
    }

    /// 全新宿主拟合（冷路径：含 SwiftUI 图构建）
    private func fitFresh(
        _ view: AnyView, width: CGFloat,
        proposedHeight: CGFloat? = nil
    ) -> CGFloat {
        let host = UIHostingController(rootView: view)
        return host.sizeThatFits(
            in: CGSize(
                width: width,
                height: proposedHeight
                    ?? .greatestFiniteMagnitude
            )
        ).height
    }

    private func assistantBubbleView(
        _ text: String
    ) -> AnyView {
        AnyView(
            MarkdownText(text)
                .frame(
                    width: textW, alignment: .leading
                )
                .padding(
                    .vertical, OneDayMetrics.bubblePaddingV
                )
                .environment(\.dynamicTypeSize, .large)
        )
    }

    /// 与拟合钉测同构的用户行（HStack{Spacer＋泡}）
    private func userRowView(_ text: String) -> AnyView {
        AnyView(
            HStack {
                Spacer(
                    minLength: OneDayMetrics.bubbleSideInset
                )
                VStack(
                    alignment: .trailing,
                    spacing: OneDayMetrics.spacingXS
                ) {
                    SelectableInlineText(
                        paragraphs: [
                            InlineTextParagraph(
                                runs: TextShaping.shapeRuns(
                                    InlineRunBuilder.plainRuns(
                                        text
                                    )
                                )
                            ),
                        ],
                        textStyle: .body,
                        foreground: Palette.userBubbleText
                    )
                    .padding(
                        .horizontal,
                        OneDayMetrics.bubblePaddingH
                    )
                    .padding(
                        .vertical,
                        OneDayMetrics.bubblePaddingV
                    )
                }
            }
            .environment(\.dynamicTypeSize, .large)
        )
    }

    private struct FacetCase {
        let name: String
        let view: AnyView
        let width: CGFloat
        let composerHeight: CGFloat
    }

    private func facetCases() -> [FacetCase] {
        var cases: [FacetCase] = []
        let mdComposer = makeComposer(
            ledger: ChatRowStateLedger()
        )
        let mdTexts: [(String, String)] = [
            ("散文多段", """
            # 结论先行

            这是第一段正文，长度中等，包含一些需要折行的中文内容用来覆盖多行排版形态。

            - 列表项一
            - 列表项二，文字更长一些

            最后一段收尾，确认段间节奏与合成口径一致。
            """),
            ("引用块", """
            先看这条引用。

            > 引用第一行
            > 引用第二行，内容稍长一点用来折行

            引用之后还有正文。
            """),
            ("代码块", """
            代码如下：

            ```swift
            func greet(_ name: String) -> String {
                let message = "hello, \\(name)"
                print(message)
                return message
            }
            ```

            以上。
            """),
            ("表格Grid", """
            | 项目 | 状态 | 备注 |
            | --- | --- | --- |
            | 构建 | 通过 | 两轮 CI 全绿 |
            | 真机 | 待验 | 长会话上翻到顶三遍往返不崩才算治愈 |
            | 文档 | 已更新 | 设计节与待办总表都已落账 |
            """),
            ("表格降级列表", """
            | 甲 | 乙 | 丙 | 丁 | 戊 | 己 |
            | --- | --- | --- | --- | --- | --- |
            | 一行甲 | 一行乙 | 一行丙 | 一行丁 | 一行戊 | 一行己 |
            | 二行甲列长一点 | 二行乙 | 二行丙 | 二行丁 | 二行戊 | 二行己 |
            """),
            ("任务清单", """
            - [x] 已完成的一项
            - [ ] 待办的一项，文字长一点需要折行验证行高
            - [ ] 最后一项
            """),
            ("长文四节", (0..<4).map { i in
                """
                ## 第 \(i + 1) 节

                这是长回复的第 \(i + 1) 段正文，用来把行高拉到数百 pt 量级，与相邻的短行形成极端高差——真机崩溃正是发生在这种行集的上翻滚动里。

                - 要点一：量测与呈现同源
                - 要点二：行高回喂后框架不再修正
                """
            }.joined(separator: "\n\n")),
        ]
        for (name, text) in mdTexts {
            cases.append(FacetCase(
                name: "md-\(name)",
                view: assistantBubbleView(text),
                width: textW
                    + OneDayMetrics.bubblePaddingH * 2,
                composerHeight: mdComposer.markdownHeight(
                    text
                ) + OneDayMetrics.bubblePaddingV * 2
            ))
        }
        // 用户行（全行结构对 entryHeight）
        for (name, text) in [
            ("短行", "嗯"),
            ("长文", Array(
                repeating: "abcd", count: 64
            ).joined(separator: " ")),
        ] {
            let entry = ChatEntry(
                role: "user", content: text, thread: nil
            )
            cases.append(FacetCase(
                name: "user-\(name)",
                view: userRowView(text),
                width: contentW,
                composerHeight: mdComposer.entryHeight(
                    entry, dividerText: nil
                )
            ))
        }
        // 工具卡（收/展各一例，独立账本）
        let card = ToolCard(
            id: "tc-probe-a", toolName: "terminal",
            category: .terminal,
            title: "运行命令", summary: "ls -la /opt/data",
            result: "total 8\n-rw-r--r-- report.xlsx\n-rw-r--r-- notes.md",
            resultFailed: false,
            arguments: "{\"command\":\"ls -la /opt/data\"}"
        )
        for expanded in [false, true] {
            let ledger = ChatRowStateLedger()
            let key = ChatRowStateKeys.toolEntry(UUID())
            if expanded {
                ledger.setExpansion(true, for: key)
            }
            let composer = makeComposer(ledger: ledger)
            cases.append(FacetCase(
                name: expanded ? "toolcard-展开" : "toolcard-收起",
                view: AnyView(
                    ToolCardView(
                        card: card, expansionKey: key,
                        ledger: ledger
                    )
                    .environment(\.dynamicTypeSize, .large)
                ),
                width: contentW,
                composerHeight: composer.toolCardHeight(
                    card: card, width: contentW,
                    expanded: expanded, plain: false
                )
            ))
        }
        // 思考块（收/展）
        let reasoningText = """
        先把问题拆成三部分：第一是布局 pass 的自我失效路径，第二是行高来源，第三是验证方法。
        逐项核对之后发现闸门并不在这条路上，所以修法必须落在结构上而不是继续加守卫。
        最后把行高改成量测回喂的固定高，框架不再估算和修正，环按构造拆除。
        """
        for expanded in [false, true] {
            let ledger = ChatRowStateLedger()
            let key = ChatRowStateKeys.liveReasoning
            if expanded {
                ledger.setExpansion(true, for: key)
            }
            let composer = makeComposer(ledger: ledger)
            cases.append(FacetCase(
                name: expanded ? "reasoning-展开" : "reasoning-收起",
                view: AnyView(
                    ReasoningBlock(
                        text: reasoningText, seconds: nil,
                        isStreaming: false,
                        expansionKey: key, ledger: ledger
                    )
                    .environment(\.dynamicTypeSize, .large)
                ),
                width: contentW,
                composerHeight: composer.reasoningHeight(
                    text: reasoningText, expanded: expanded
                )
            ))
        }
        // 文件牌
        let chipPath = "/opt/data/report.xlsx"
        cases.append(FacetCase(
            name: "filechip",
            view: AnyView(
                FileChip(path: chipPath) {}
                    .environment(AppState())
                    .environment(\.dynamicTypeSize, .large)
            ),
            width: contentW,
            composerHeight: mdComposer.fileChipHeight(
                path: chipPath, width: contentW
            )
        ))
        return cases
    }

    // MARK: - 一致性：逐 facet delta 实数

    func testProbeAFacetDeltas() {
        let cases = facetCases()
        XCTAssertEqual(cases.count, 14)
        for c in cases {
            let composerH = c.composerHeight
            let fit1 = fitFresh(c.view, width: c.width)
            let fit2 = fitFresh(c.view, width: c.width)
            let refed = fitFresh(
                c.view, width: c.width,
                proposedHeight: composerH
            )
            print(String(
                format: "PROBEA|facet|%@|composer=%.2f|fit=%.2f"
                    + "|delta=%+.2f|fitRepeatDelta=%+.2f"
                    + "|refed=%.2f|refedDelta=%+.2f",
                c.name, composerH, fit1, fit1 - composerH,
                fit2 - fit1, refed, refed - composerH
            ))
            XCTAssertGreaterThan(composerH, 0, c.name)
            XCTAssertGreaterThan(fit1, 0, c.name)
        }
    }

    // MARK: - 成本：公式（冷）

    private func timingStats(
        _ samples: [Double]
    ) -> (mean: Double, median: Double) {
        let sorted = samples.sorted()
        let mean = samples.reduce(0, +)
            / Double(samples.count)
        return (mean, sorted[sorted.count / 2])
    }

    private func mdTemplates() -> [(String, String)] {
        [
            ("prose-medium", """
            # 结论先行

            这是第一段正文，长度中等，包含一些需要折行的中文内容用来覆盖多行排版形态。

            - 列表项一
            - 列表项二，文字更长一些

            最后一段收尾，确认段间节奏与合成口径一致。
            """),
            ("code", """
            代码段：

            ```swift
            let a = compute(1)
            let b = compute(2)
            let c = compute(3)
            print(a + b + c)
            ```

            代码之后一行收尾。
            """),
            ("table", """
            | 项目 | 状态 | 备注 |
            | --- | --- | --- |
            | 构建 | 通过 | 两轮 CI 全绿 |
            | 真机 | 待验 | 长会话上翻到顶三遍往返 |
            | 文档 | 已更新 | 设计节与待办总表都已落账 |
            """),
            ("long", (0..<4).map { i in
                """
                ## 第 \(i + 1) 节

                这是长回复的第 \(i + 1) 段正文，用来把行高拉到数百 pt 量级，与相邻的短行形成极端高差。

                - 要点一：量测与呈现同源
                - 要点二：行高回喂后框架不再修正
                """
            }.joined(separator: "\n\n")),
        ]
    }

    func testProbeAComposerCost() {
        let iterations = 50
        for (name, template) in mdTemplates() {
            // 预热（字体/解析缓存）
            let warmComposer = makeComposer(
                ledger: ChatRowStateLedger()
            )
            _ = warmComposer.markdownHeight(template)
            var samples: [Double] = []
            for i in 0..<iterations {
                // 内容逐轮唯一，避开合成器备忘命中
                let text = template + "\n\n附注编号 \(i)。"
                let composer = makeComposer(
                    ledger: ChatRowStateLedger()
                )
                let t0 = CFAbsoluteTimeGetCurrent()
                _ = composer.markdownHeight(text)
                samples.append(
                    (CFAbsoluteTimeGetCurrent() - t0)
                        * 1_000_000
                )
            }
            let s = timingStats(samples)
            print(String(
                format: "PROBEA|cost-composer|%@|meanUs=%.1f"
                    + "|medianUs=%.1f",
                name, s.mean, s.median
            ))
        }
    }

    // MARK: - 成本：托管量测（冷宿主/热宿主）

    func testProbeAHostedCost() {
        let iterations = 50
        for (name, template) in mdTemplates() {
            _ = fitFresh(
                assistantBubbleView(template),
                width: textW
                    + OneDayMetrics.bubblePaddingH * 2
            )
            var cold: [Double] = []
            for i in 0..<iterations {
                let view = assistantBubbleView(
                    template + "\n\n附注编号 \(i)。"
                )
                let t0 = CFAbsoluteTimeGetCurrent()
                _ = fitFresh(
                    view,
                    width: textW
                        + OneDayMetrics.bubblePaddingH * 2
                )
                cold.append(
                    (CFAbsoluteTimeGetCurrent() - t0)
                        * 1_000_000
                )
            }
            let host = UIHostingController(
                rootView: assistantBubbleView(template)
            )
            _ = host.sizeThatFits(in: CGSize(
                width: textW
                    + OneDayMetrics.bubblePaddingH * 2,
                height: .greatestFiniteMagnitude
            ))
            var warm: [Double] = []
            for i in 0..<iterations {
                host.rootView = assistantBubbleView(
                    template + "\n\n附注编号 \(i)。"
                )
                let t0 = CFAbsoluteTimeGetCurrent()
                _ = host.sizeThatFits(in: CGSize(
                    width: textW
                        + OneDayMetrics.bubblePaddingH * 2,
                    height: .greatestFiniteMagnitude
                ))
                warm.append(
                    (CFAbsoluteTimeGetCurrent() - t0)
                        * 1_000_000
                )
            }
            let cs = timingStats(cold)
            let ws = timingStats(warm)
            print(String(
                format: "PROBEA|cost-hosted|%@|coldMeanUs=%.1f"
                    + "|coldMedianUs=%.1f|warmMeanUs=%.1f"
                    + "|warmMedianUs=%.1f",
                name, cs.mean, cs.median, ws.mean, ws.median
            ))
        }
    }

    // MARK: - 成本：300 行冷量测总账

    func testProbeAThreeHundredRows() {
        let templates = mdTemplates()
        let latin = Array(
            repeating: "abcd", count: 64
        ).joined(separator: " ")
        // 300 行唯一内容（避两边备忘）：模 10 混排
        var mdRows: [String] = []
        var userRows: [String] = []
        for i in 0..<300 {
            switch i % 10 {
            case 0...3:
                mdRows.append(
                    templates[0].1 + "\n\n短行编号 \(i)。"
                )
            case 4...5:
                mdRows.append(
                    templates[0].1 + "\n\n中行编号 \(i)。"
                )
            case 6:
                mdRows.append(
                    templates[1].1 + "\n\n代码编号 \(i)。"
                )
            case 7:
                mdRows.append(
                    templates[2].1 + "\n\n表格编号 \(i)。"
                )
            case 9:
                mdRows.append(
                    templates[3].1 + "\n\n长行编号 \(i)。"
                )
            default:
                userRows.append(latin + " tail\(i)")
            }
        }
        XCTAssertEqual(mdRows.count + userRows.count, 300)
        // 公式路：单 composer 实例（生产 nativeRows 同式）
        let composer = makeComposer(
            ledger: ChatRowStateLedger()
        )
        let t0 = CFAbsoluteTimeGetCurrent()
        var composerTotalH: CGFloat = 0
        for text in mdRows {
            composerTotalH += composer.markdownHeight(text)
        }
        for text in userRows {
            let entry = ChatEntry(
                role: "user", content: text, thread: nil
            )
            composerTotalH += composer.entryHeight(
                entry, dividerText: nil
            )
        }
        let composerMs = (CFAbsoluteTimeGetCurrent() - t0)
            * 1_000
        // 托管冷路：逐行全新宿主
        let t1 = CFAbsoluteTimeGetCurrent()
        var hostedTotalH: CGFloat = 0
        for text in mdRows {
            hostedTotalH += fitFresh(
                assistantBubbleView(text),
                width: textW
                    + OneDayMetrics.bubblePaddingH * 2
            ) - OneDayMetrics.bubblePaddingV * 2
        }
        for text in userRows {
            hostedTotalH += fitFresh(
                userRowView(text), width: contentW
            )
        }
        let hostedColdMs = (CFAbsoluteTimeGetCurrent() - t1)
            * 1_000
        // 托管热路：单宿主换根（md 行与 user 行各一宿主）
        let mdHost = UIHostingController(
            rootView: assistantBubbleView(mdRows[0])
        )
        let userHost = UIHostingController(
            rootView: userRowView(userRows[0])
        )
        let t2 = CFAbsoluteTimeGetCurrent()
        var warmTotalH: CGFloat = 0
        for text in mdRows {
            mdHost.rootView = assistantBubbleView(text)
            warmTotalH += mdHost.sizeThatFits(in: CGSize(
                width: textW
                    + OneDayMetrics.bubblePaddingH * 2,
                height: .greatestFiniteMagnitude
            )).height - OneDayMetrics.bubblePaddingV * 2
        }
        for text in userRows {
            userHost.rootView = userRowView(text)
            warmTotalH += userHost.sizeThatFits(in: CGSize(
                width: contentW,
                height: .greatestFiniteMagnitude
            )).height
        }
        let hostedWarmMs = (CFAbsoluteTimeGetCurrent() - t2)
            * 1_000
        print(String(
            format: "PROBEA|rollup300|composerMs=%.2f"
                + "|hostedColdMs=%.2f|hostedWarmMs=%.2f"
                + "|composerPerRowUs=%.1f"
                + "|hostedColdPerRowUs=%.1f"
                + "|hostedWarmPerRowUs=%.1f"
                + "|heightSumDelta=%+.2f",
            composerMs, hostedColdMs, hostedWarmMs,
            composerMs * 1_000 / 300,
            hostedColdMs * 1_000 / 300,
            hostedWarmMs * 1_000 / 300,
            hostedTotalH - composerTotalH
        ))
        XCTAssertGreaterThan(composerTotalH, 0)
        XCTAssertGreaterThan(hostedTotalH, 0)
        XCTAssertGreaterThan(warmTotalH, 0)
    }
}
