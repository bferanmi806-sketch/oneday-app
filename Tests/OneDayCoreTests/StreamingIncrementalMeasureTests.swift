import XCTest
@testable import OneDayCore

/// §348 量测钉测：以切分求值账（StreamingSegmen-
/// tationMetrics）为代理指标钉死两条成本口径——
/// ①同拍重复调用只真求值一次（备忘收敛）；②追
/// 加流全程只发生一次全量求值、其余拍全走尾块增
/// 量（已完成块重建次数有界）；③非追加改写退化
/// 全量且结果逐值正确。
final class StreamingIncrementalMeasureTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StreamingBlockSegmenter.resetCachesForTesting()
        StreamingSegmentationMetrics.reset()
        MarkdownParseMetrics.reset()
    }

    /// 与探针同型的混合单元（标题/散文/列表/代码/
    /// 表格/引用），重复至数千字
    private func sample(target: Int) -> String {
        var text = ""
        var seed = 0
        while text.count < target {
            seed += 1
            text += """
                ## 小节 \(seed)：量测

                散文一段，交代背景与结论，含 **粗体** 标记与数字 \(seed)。

                - 列表项一
                - 列表项二 \(seed)

                ```swift
                let v\(seed) = \(seed)
                ```

                | 甲 | 乙 |
                | --- | --- |
                | \(seed) | 值 |

                > 引用一行 \(seed)。

                """
        }
        return text
    }

    /// 同拍 7 个调用点同文求值：只许一次真求值，
    /// 其余全走备忘
    func testSameTextRepeatedCallsEvaluateOnce() {
        let text = sample(target: 4_000)
        for _ in 0..<7 {
            _ = StreamingBlockSegmenter.blocks(for: text)
        }
        let metrics = StreamingSegmentationMetrics.snapshot()
        XCTAssertEqual(
            metrics.fullEvaluations
                + metrics.incrementalEvaluations, 1
        )
        XCTAssertEqual(metrics.memoHits, 6)
    }

    /// 追加流：首拍全量、后续每拍尾块增量，全量求
    /// 值次数恒为 1（已完成块不再被整体重切）；且
    /// 尾块域后缀远小于全文（增量路径在场实证）
    func testAppendStreamStaysIncremental() {
        let full = sample(target: 6_000)
        var length = 0
        var steps = 0
        while length < full.count {
            length = min(full.count, length + 97)
            steps += 1
            _ = StreamingBlockSegmenter.blocks(
                for: String(full.prefix(length))
            )
        }
        XCTAssertGreaterThan(steps, 40)
        let metrics = StreamingSegmentationMetrics.snapshot()
        XCTAssertEqual(metrics.fullEvaluations, 1)
        XCTAssertEqual(
            metrics.incrementalEvaluations, steps - 1
        )
        XCTAssertGreaterThan(
            metrics.lastIncrementalFullLength, 4_000
        )
        XCTAssertLessThan(
            metrics.lastIncrementalSuffixLength,
            metrics.lastIncrementalFullLength / 2
        )
        // 切分不再喂全文解析备忘：整场流式零全文解
        // 析未命中（旧制每拍一次）
        XCTAssertEqual(
            MarkdownParseMetrics.snapshot().blockMisses, 0
        )
    }

    /// 非追加（改写/替换）退化全量：求值账记全量，
    /// 结果与强制全量逐值一致
    func testNonAppendFallsBackToFull() {
        let first = sample(target: 2_000)
        _ = StreamingBlockSegmenter.blocks(for: first)
        let rewritten = "# 全新标题\n\n被整体替换的正文，与前文无前缀关系。"
        let result = StreamingBlockSegmenter.blocks(
            for: rewritten
        )
        let metrics = StreamingSegmentationMetrics.snapshot()
        XCTAssertEqual(metrics.fullEvaluations, 2)
        XCTAssertEqual(metrics.incrementalEvaluations, 0)
        XCTAssertEqual(
            result,
            StreamingBlockSegmenter
                .blocksForcingFullEvaluation(for: rewritten)
        )
    }

    /// 文本变短（回退/截断）同样退化全量且正确
    func testShrinkingTextFallsBackToFull() {
        let full = sample(target: 3_000)
        _ = StreamingBlockSegmenter.blocks(for: full)
        let shorter = String(full.prefix(500))
        let result = StreamingBlockSegmenter.blocks(
            for: shorter
        )
        XCTAssertEqual(
            result,
            StreamingBlockSegmenter
                .blocksForcingFullEvaluation(for: shorter)
        )
        let metrics = StreamingSegmentationMetrics.snapshot()
        XCTAssertEqual(metrics.fullEvaluations, 2)
    }
}
