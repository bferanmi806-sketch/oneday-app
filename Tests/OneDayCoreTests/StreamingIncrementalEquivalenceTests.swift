import XCTest
@testable import OneDayCore

/// §348 差分等价钉测：追加链增量切分在任意步长下
/// 逐步产出必须与强制全量切分逐块逐值相等（kind/
/// sourceText/isTail/index 全比）。样本专挑解析器
/// 的状态修订路径：围栏跨拍闭合、表头与分隔行分
/// 拍到达、列表隔空行续表（lookahead 合并）、列
/// 表续行、有序列表打断段落规则、未闭合围栏收尾。
final class StreamingIncrementalEquivalenceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StreamingBlockSegmenter.resetCachesForTesting()
        StreamingSegmentationMetrics.reset()
    }

    private func assertEquivalence(
        _ sample: String, step: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        StreamingBlockSegmenter.resetCachesForTesting()
        var length = 0
        while length < sample.count {
            length = min(sample.count, length + step)
            let prefix = String(sample.prefix(length))
            let incremental =
                StreamingBlockSegmenter.blocks(for: prefix)
            let reference = StreamingBlockSegmenter
                .blocksForcingFullEvaluation(for: prefix)
            XCTAssertEqual(
                incremental, reference,
                "step=\(step) length=\(length) 前缀增量与全量不一致",
                file: file, line: line
            )
        }
    }

    private let prose = """
        第一段文字，交代背景。

        第二段继续展开，补充细节。

        第三段收尾。
        """

    private let fence = """
        前言一行。

        ```swift
        let a = 1
        let b = 2
        ```

        结尾段落。
        """

    private let table = """
        看下表：

        | 甲 | 乙 |
        | --- | --- |
        | 1 | 2 |
        | 3 | 4 |

        表后文字。
        """

    private let listLookahead = """
        - 甲
        - 乙

        - 丙

        后续段落。
        """

    private let listContinuation = """
        - 长项第一行
          缩进续行并入末项
        - 次项

        尾段。
        """

    private let quoteHeadingDivider = """
        # 标题

        > 引用一
        > 引用二

        ---

        正文。
        """

    private let orderedInterruption = """
        2024. 是年份不是列表。

        1. 第一步
        2. 第二步

        结束。
        """

    private let unclosedFence = """
        说明：

        ```
        未闭合代码
        第二行
        """

    private let taskList = """
        - [ ] 待办一
        - [x] 已办二

        散文尾。
        """

    func testProseEquivalence() {
        assertEquivalence(prose, step: 1)
        assertEquivalence(prose, step: 7)
    }

    func testFenceEquivalence() {
        assertEquivalence(fence, step: 1)
        assertEquivalence(fence, step: 5)
    }

    func testTableEquivalence() {
        assertEquivalence(table, step: 1)
        assertEquivalence(table, step: 9)
    }

    func testListLookaheadMergeEquivalence() {
        assertEquivalence(listLookahead, step: 1)
        assertEquivalence(listLookahead, step: 4)
    }

    func testListContinuationEquivalence() {
        assertEquivalence(listContinuation, step: 1)
        assertEquivalence(listContinuation, step: 6)
    }

    func testQuoteHeadingDividerEquivalence() {
        assertEquivalence(quoteHeadingDivider, step: 1)
        assertEquivalence(quoteHeadingDivider, step: 8)
    }

    func testOrderedInterruptionEquivalence() {
        assertEquivalence(orderedInterruption, step: 1)
        assertEquivalence(orderedInterruption, step: 11)
    }

    func testUnclosedFenceEquivalence() {
        assertEquivalence(unclosedFence, step: 1)
        assertEquivalence(unclosedFence, step: 3)
    }

    func testTaskListEquivalence() {
        assertEquivalence(taskList, step: 1)
        assertEquivalence(taskList, step: 7)
    }

    /// 列表在前、尾段首行逐字转成有序列表项：前列
    /// 表跨空行收编尾项（§348 差分实证的回归样本）
    func testListThenConvertedItemEquivalence() {
        let sample = """
            - 甲

            1. 新项

            尾段。
            """
        assertEquivalence(sample, step: 1)
        assertEquivalence(sample, step: 5)
    }

    func testMixedLongEquivalence() {
        var sample = ""
        for seed in 1...6 {
            sample += """
                ## 小节 \(seed)

                散文一段，含 **粗体** 与 `代码`。

                - 项一 \(seed)
                - 项二

                > 引用 \(seed)


                """
        }
        sample += "最终段落收尾。"
        assertEquivalence(sample, step: 64)
        assertEquivalence(sample, step: 13)
    }

    /// 链被无关文本打断（双流交错/落定替换）后回
    /// 到追加链：退化全量、结果仍须逐值正确
    func testChainDisturbedStillEquivalent() {
        let distractor = "# 另一个面\n\n毫不相关的正文，长度不同。"
        var length = 0
        while length < fence.count {
            length = min(fence.count, length + 6)
            let prefix = String(fence.prefix(length))
            _ = StreamingBlockSegmenter.blocks(for: distractor)
            let incremental =
                StreamingBlockSegmenter.blocks(for: prefix)
            let reference = StreamingBlockSegmenter
                .blocksForcingFullEvaluation(for: prefix)
            XCTAssertEqual(incremental, reference)
        }
    }
}
