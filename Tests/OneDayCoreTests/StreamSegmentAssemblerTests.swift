import OneDayCore
import XCTest

/// 流式分段装配（第 93 条）：确定性回放「文字段 A
/// →工具调用→文字段 B」钉死跨段不串字——B 的实
/// 时呈现（当前段）只含 B、A 只在封存列出现一次；
/// 段内拼接/发布节流与单闸口径逐字同；合并全文与
/// 落定拼接（"\n\n"）同制。时刻为注入的单调时钟
/// 字面值（秒）。
final class StreamSegmentAssemblerTests: XCTestCase {

    /// 第 93 条事故原文回放：A＝落库 4640 段全文、
    /// B＝4643 段全文（主线服务端取证原样），分片
    /// 喂入＋工具边界封段后逐项对账
    func testIncidentReplaySegmentsDoNotCarryOver() {
        let segmentA = "好，我换个更可靠的方式——用 Replicate 的公开 "
            + "DeOldify 模型，不需要 API key 的那种，或者直接调一个免费的彩色化服务。"
        let segmentB = "好，我直接用 colorize.cc 或 DeepAI 的免费接口，不需要注册。先试 DeepAI。"
        var assembler = StreamSegmentAssembler()
        var now = 0.0
        for chunk in ["好，我换个", "更可靠的方式——用 Replicate 的公开 ",
                      "DeOldify 模型，不需要 API key 的那种，",
                      "或者直接调一个免费的彩色化服务。"] {
            assembler.offer(chunk, at: now)
            now += 0.01
        }
        // 工具调用开始＝段边界：A 封存
        XCTAssertEqual(
            assembler.sealCurrentSegment(at: now), segmentA
        )
        now += 0.01
        for chunk in ["好，我直接用 colorize.cc 或 ",
                      "DeepAI 的免费接口，不需要注册。先试 DeepAI。"] {
            assembler.offer(chunk, at: now)
            now += 0.01
        }
        // B 的实时呈现只有 B：不含 A 的任何一部分
        XCTAssertEqual(assembler.currentFullText, segmentB)
        XCTAssertFalse(assembler.currentFullText.hasPrefix("好，我换个"))
        // A 只出现一次、在封存列
        XCTAssertEqual(assembler.sealedSegments, [segmentA])
        XCTAssertEqual(
            assembler.fullSegments, [segmentA, segmentB]
        )
        // 合并全文与落定拼接同制（段间空行、逐字一致）
        XCTAssertEqual(
            assembler.mergedFullText,
            segmentA + "\n\n" + segmentB
        )
    }

    /// 段内增量拼接不回退：无边界时与单只发布闸的
    /// 累积/发布行为逐字相同（窗口合并＋精确全文）
    func testIntraSegmentAccumulationMatchesSingleGate() {
        var assembler = StreamSegmentAssembler()
        XCTAssertEqual(assembler.offer("一", at: 0), "一")
        XCTAssertNil(assembler.offer("二", at: 0.03))
        XCTAssertNil(assembler.offer("三", at: 0.06))
        XCTAssertEqual(assembler.currentPublished, "一")
        XCTAssertEqual(assembler.offer("四", at: 0.09), "一二三四")
        XCTAssertEqual(assembler.currentFullText, "一二三四")
        XCTAssertTrue(assembler.sealedSegments.isEmpty)
    }

    /// 新段首增量立即发布：封段后当前闸是新闸，上
    /// 一段的发布时间窗不许拖住新段首字
    func testNewSegmentFirstDeltaPublishesImmediately() {
        var assembler = StreamSegmentAssembler()
        XCTAssertEqual(assembler.offer("甲", at: 0), "甲")
        XCTAssertEqual(assembler.sealCurrentSegment(at: 0.01), "甲")
        // 距上一段发布仅 10ms（远未满 80ms 窗）：新段
        // 首增量仍立即发布，且快照不含上一段
        XCTAssertEqual(assembler.offer("乙", at: 0.02), "乙")
        XCTAssertEqual(assembler.currentPublished, "乙")
    }

    /// 空段不产出：工具先行（尚无正文）与并行工具
    /// 连发边界都无段可封、不产空段
    func testSealingEmptySegmentProducesNothing() {
        var assembler = StreamSegmentAssembler()
        XCTAssertNil(assembler.sealCurrentSegment(at: 0))
        XCTAssertEqual(assembler.offer("正文", at: 0.01), "正文")
        XCTAssertEqual(assembler.sealCurrentSegment(at: 0.02), "正文")
        // 紧接着的第二个边界（并行工具）：无段可封
        XCTAssertNil(assembler.sealCurrentSegment(at: 0.03))
        XCTAssertEqual(assembler.sealedSegments, ["正文"])
        XCTAssertEqual(assembler.fullSegments, ["正文"])
    }

    /// 三段链：A→工具→B→工具→C，封存序与全文序
    /// 恒按事件序
    func testThreeSegmentsKeepEventOrder() {
        var assembler = StreamSegmentAssembler()
        assembler.offer("A", at: 0)
        assembler.sealCurrentSegment(at: 0.01)
        assembler.offer("B", at: 0.02)
        assembler.sealCurrentSegment(at: 0.03)
        assembler.offer("C", at: 0.04)
        XCTAssertEqual(assembler.sealedSegments, ["A", "B"])
        XCTAssertEqual(assembler.fullSegments, ["A", "B", "C"])
        XCTAssertEqual(assembler.mergedFullText, "A\n\nB\n\nC")
    }

    /// 封段取精确全文：待发布残余（未满窗的尾巴增
    /// 量）一并入段，节流永不丢字、永不跨段漏字
    func testSealFlushesPendingTailExactly() {
        var assembler = StreamSegmentAssembler()
        assembler.offer("头", at: 0)
        XCTAssertNil(assembler.offer("尾", at: 0.02))
        XCTAssertEqual(assembler.sealCurrentSegment(at: 0.03), "头尾")
        assembler.offer("新段", at: 0.04)
        XCTAssertEqual(assembler.currentFullText, "新段")
        XCTAssertEqual(assembler.fullSegments, ["头尾", "新段"])
    }

    /// 巡查只推当前段尾巴：封存段定稿后 collectDue
    /// 不再改动它
    func testCollectDueOnlyPublishesCurrentSegment() {
        var assembler = StreamSegmentAssembler()
        assembler.offer("旧段", at: 0)
        assembler.sealCurrentSegment(at: 0.01)
        XCTAssertEqual(assembler.offer("新", at: 0.02), "新")
        XCTAssertNil(assembler.offer("尾", at: 0.04))
        XCTAssertNil(assembler.collectDue(at: 0.06))
        XCTAssertEqual(assembler.collectDue(at: 0.11), "新尾")
        XCTAssertEqual(assembler.sealedSegments, ["旧段"])
    }

    /// 恢复回填往返：落盘的段序装回后，封存段只
    /// 读、新段增量只拼进打开段
    func testRestoreRoundTripKeepsSegmentsApart() {
        var assembler = StreamSegmentAssembler()
        assembler.restore(
            sealed: ["第一段"], current: "第二段半截", at: 10
        )
        XCTAssertEqual(assembler.sealedSegments, ["第一段"])
        XCTAssertEqual(assembler.currentPublished, "第二段半截")
        assembler.offer("续", at: 10.01)
        XCTAssertEqual(
            assembler.fullSegments, ["第一段", "第二段半截续"]
        )
        XCTAssertEqual(
            assembler.mergedFullText, "第一段\n\n第二段半截续"
        )
    }

    /// 归零整器清空：封存列与当前段同清，新一轮从
    /// 无段起步
    func testResetClearsEverything() {
        var assembler = StreamSegmentAssembler()
        assembler.offer("A", at: 0)
        assembler.sealCurrentSegment(at: 0.01)
        assembler.offer("B", at: 0.02)
        assembler.reset()
        XCTAssertTrue(assembler.sealedSegments.isEmpty)
        XCTAssertFalse(assembler.hasCurrentContent)
        XCTAssertEqual(assembler.fullSegments, [])
        XCTAssertEqual(assembler.mergedFullText, "")
        XCTAssertEqual(assembler.offer("新轮", at: 1), "新轮")
    }
}
