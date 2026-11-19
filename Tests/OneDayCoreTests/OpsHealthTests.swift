import XCTest
@testable import OneDayCore

/// 体检面映射层钉测（H1-a，台账 158）：fixture 全部
/// 按 H1-0 探活实测形态冻结——doctor 正常轮（10 组
/// 32✓/4⚠）、doctor 崩尾轮（Directory Structure 读
/// memories 文件 PermissionError、exit 1、无总结）、
/// security-audit 三漏洞轮（HIGH/MODERATE/LOW 各一、
/// 均有修复版）。解析口径改一寸，这里先红。
final class OpsHealthTests: XCTestCase {

    // MARK: - DTO 解码（探活冻结形状）

    func testSpawnResponseDecodes() throws {
        let json = #"{"ok": true, "pid": 1234, "name": "doctor"}"#
        let decoded = try JSONDecoder().decode(
            OpsSpawnResponse.self, from: Data(json.utf8)
        )
        XCTAssertTrue(decoded.ok)
        XCTAssertEqual(decoded.pid, 1234)
        XCTAssertEqual(decoded.name, "doctor")
        XCTAssertNil(decoded.archive)
    }

    func testActionStatusDecodesExitCode() throws {
        let running = #"{"name": "doctor", "running": true, "exit_code": null, "pid": 7, "lines": ["a"]}"#
        let decodedRunning = try JSONDecoder().decode(
            OpsActionStatus.self, from: Data(running.utf8)
        )
        XCTAssertTrue(decodedRunning.running)
        XCTAssertNil(decodedRunning.exitCode)
        XCTAssertEqual(decodedRunning.lines, ["a"])

        let done = #"{"name": "doctor", "running": false, "exit_code": 1, "pid": null, "lines": []}"#
        let decodedDone = try JSONDecoder().decode(
            OpsActionStatus.self, from: Data(done.utf8)
        )
        XCTAssertEqual(decodedDone.exitCode, 1)
    }

    // MARK: - 日志切片（多方共享、按 started 标记切本轮）

    private let sharedLog = [
        "=== doctor started ===",
        "◆ Security Advisories",
        "✓ 旧轮次条目",
        "=== doctor started ===",
        "◆ Python Environment",
        "✓ 本轮条目",
    ]

    func testSliceTakesLastRunOnly() {
        XCTAssertEqual(
            OpsActionLog.slice(lines: sharedLog, actionName: "doctor"),
            ["◆ Python Environment", "✓ 本轮条目"]
        )
        XCTAssertEqual(
            OpsActionLog.markerCount(lines: sharedLog, actionName: "doctor"),
            2
        )
        XCTAssertEqual(
            OpsActionLog.sliceAfterMarker(
                lines: sharedLog, actionName: "doctor", ordinal: 1
            ),
            ["◆ Python Environment", "✓ 本轮条目"]
        )
        // 别的动作的标记不算数
        XCTAssertNil(
            OpsActionLog.slice(
                lines: sharedLog, actionName: "security-audit"
            )
        )
    }

    func testSliceWithoutMarkerIsNil() {
        XCTAssertNil(
            OpsActionLog.slice(
                lines: ["◆ Python Environment", "✓ 条目"],
                actionName: "doctor"
            )
        )
        XCTAssertNil(
            OpsActionLog.sliceAfterMarker(
                lines: sharedLog, actionName: "doctor", ordinal: 2
            )
        )
    }

    // MARK: - doctor 正常轮（探活形态：10 组 32✓/4⚠，exit 0）

    /// 按（分组，通过数，注意数）生成探活同构日志
    private func doctorLines(
        _ spec: [(String, Int, Int)]
    ) -> [String] {
        var lines: [String] = []
        for (title, pass, warn) in spec {
            lines.append("◆ \(title)")
            for i in 0..<pass {
                lines.append("✓ \(title) 检查项 \(i + 1)")
            }
            for i in 0..<warn {
                lines.append("⚠ \(title) 注意项 \(i + 1)")
            }
        }
        return lines
    }

    private let normalSpec: [(String, Int, Int)] = [
        ("Security Advisories", 3, 1),
        ("MCP Server Security", 3, 0),
        ("Python Environment", 5, 1),
        ("SSL / CA Certificates", 2, 0),
        ("Required Packages", 6, 0),
        ("Configuration Files", 4, 1),
        ("xAI Model Retirement", 1, 0),
        ("Session Reset", 2, 0),
        ("Auth Providers", 3, 1),
        ("Directory Structure", 3, 0),
    ]

    func testDoctorNormalRunMapsToAttention() {
        var lines = doctorLines(normalSpec)
        // 第一条 ⚠ 项下挂一条 → 明细，须归到该项名下
        let warnIndex = lines.firstIndex { $0.hasPrefix("⚠") }!
        lines.insert("→ 细节原文一行", at: warnIndex + 1)

        let run = DoctorLogParser.parse(lines: lines, exitCode: 0)
        XCTAssertEqual(run.sections.count, 10)
        XCTAssertEqual(run.passCount, 32)
        XCTAssertEqual(run.warnCount, 4)
        XCTAssertEqual(run.failCount, 0)
        XCTAssertFalse(run.crashed)
        XCTAssertEqual(run.verdict, .attention)
        XCTAssertEqual(run.headline, "自检有 4 项要注意")
        XCTAssertNil(run.incompleteReason)
        // 分组人话名与明细归属
        XCTAssertEqual(run.sections[0].displayTitle, "安全公告")
        XCTAssertEqual(run.sections[9].displayTitle, "目录结构")
        let firstWarn = run.sections[0].items.first { $0.level == .warn }
        XCTAssertEqual(firstWarn?.details, ["细节原文一行"])
    }

    func testDoctorAllPassMapsToOK() {
        let lines = doctorLines([("Python Environment", 2, 0)])
        let run = DoctorLogParser.parse(lines: lines, exitCode: 0)
        XCTAssertEqual(run.verdict, .ok)
        XCTAssertEqual(run.headline, "自检通过，2 项都正常")
    }

    func testDoctorFailItemMapsToProblem() {
        let lines = [
            "◆ Configuration Files",
            "✓ 配置可读",
            "✗ 关键配置缺失",
        ]
        let run = DoctorLogParser.parse(lines: lines, exitCode: 0)
        XCTAssertEqual(run.verdict, .problem)
        XCTAssertEqual(run.headline, "自检发现 1 项异常")
    }

    // MARK: - doctor 崩尾轮（探活现役常态：exit 1＋Traceback）

    private let crashLines = [
        "◆ Security Advisories",
        "✓ 没有未处理的安全公告",
        "◆ Directory Structure",
        "✓ 数据目录存在",
        "Traceback (most recent call last):",
        "  File \"/opt/hermes/doctor.py\", line 412, in check_directory_structure",
        "    content = path.read_text()",
        "PermissionError: [Errno 13] Permission denied: '/opt/data/memories/MEMORY.md'",
    ]

    func testDoctorCrashTailMapsToIncompleteNotProblem() {
        let run = DoctorLogParser.parse(lines: crashLines, exitCode: 1)
        XCTAssertTrue(run.crashed)
        XCTAssertEqual(run.verdict, .incomplete)
        XCTAssertEqual(run.headline, "自检没跑完")
        XCTAssertEqual(run.passCount, 2)
        XCTAssertEqual(
            run.crashErrorLine,
            "PermissionError: [Errno 13] Permission denied: '/opt/data/memories/MEMORY.md'"
        )
        // 人话原因：点名停在「目录结构」、是权限问题、
        // 这一项不作数——不许合成「发现异常」
        let reason = run.incompleteReason ?? ""
        XCTAssertTrue(reason.contains("目录结构"), reason)
        XCTAssertTrue(reason.contains("权限不对"), reason)
        XCTAssertTrue(reason.contains("不作数"), reason)
    }

    func testDoctorExitNonZeroWithoutTracebackStillIncomplete() {
        // exit≠0 的唯一已观测成因是检查器自身没跑完，
        // 无 Traceback 也不许当正常结论收
        let lines = doctorLines([("Python Environment", 2, 0)])
        let run = DoctorLogParser.parse(lines: lines, exitCode: 1)
        XCTAssertEqual(run.verdict, .incomplete)
        XCTAssertNotNil(run.incompleteReason)
    }

    // MARK: - security-audit（探活形态：3 漏洞/156 组件，exit 0）

    private let auditLines = [
        "Found 3 known vulnerability finding(s) across 156 component(s)",
        "HIGH oauthlib==3.2.2 GHSA-8r88-6cj9-9fh5 Improper verification of signature fixed in: 3.2.3",
        "MODERATE opentelemetry-api==1.28.0 GHSA-4m3j-7v9p-2qx8 Sensitive data exposure fixed in: 1.29.0",
        "LOW tornado==6.4.1 GHSA-9w2r-5h6k-3m7n CRLF injection fixed in: 6.4.2",
    ]

    func testAuditThreeFindingsMapToProblem() {
        let run = SecurityAuditLogParser.parse(
            lines: auditLines, exitCode: 0
        )
        XCTAssertEqual(run.totalFindings, 3)
        XCTAssertEqual(run.componentCount, 156)
        XCTAssertEqual(run.findings.count, 3)
        XCTAssertEqual(run.count(of: .high), 1)
        XCTAssertEqual(run.count(of: .moderate), 1)
        XCTAssertEqual(run.count(of: .low), 1)
        XCTAssertEqual(run.verdict, .problem)
        XCTAssertTrue(run.headline.contains("发现 3 个已知漏洞"))
        XCTAssertTrue(run.headline.contains("高危 1"))
        XCTAssertTrue(run.headline.contains("都有修复版本"))
        let first = run.findings[0]
        XCTAssertEqual(first.packageName, "oauthlib")
        XCTAssertEqual(first.installedVersion, "3.2.2")
        XCTAssertEqual(first.fixedIn, "3.2.3")
        XCTAssertEqual(first.ghsa, "GHSA-8r88-6cj9-9fh5")
    }

    func testAuditZeroFindingsMapsToOK() {
        let lines = [
            "Found 0 known vulnerability finding(s) across 156 component(s)"
        ]
        let run = SecurityAuditLogParser.parse(lines: lines, exitCode: 0)
        XCTAssertEqual(run.totalFindings, 0)
        XCTAssertEqual(run.verdict, .ok)
        XCTAssertTrue(run.headline.contains("没有已知漏洞"))
    }

    func testAuditModerateOnlyMapsToAttention() {
        let lines = [
            "Found 1 known vulnerability finding(s) across 156 component(s)",
            "MODERATE opentelemetry-api==1.28.0 GHSA-4m3j-7v9p-2qx8 Sensitive data exposure fixed in: 1.29.0",
        ]
        let run = SecurityAuditLogParser.parse(lines: lines, exitCode: 0)
        XCTAssertEqual(run.verdict, .attention)
    }

    func testAuditExitNonZeroMapsToIncomplete() {
        let run = SecurityAuditLogParser.parse(
            lines: auditLines, exitCode: 1
        )
        XCTAssertEqual(run.verdict, .incomplete)
        XCTAssertEqual(run.headline, "安全审计没跑完")
    }

    // MARK: - 总判定合成与留痕往返

    func testSummarySynthesis() {
        let attention = HealthCheckSummary(
            date: Date(), serverBase: "https://example.test",
            doctor: HealthGroupSummary(
                verdict: .attention, headline: "自检有 4 项要注意",
                passCount: 32, warnCount: 4, failCount: 0
            ),
            audit: HealthGroupSummary(
                verdict: .ok, headline: "安全审计通过",
                findingCount: 0, highCount: 0
            )
        )
        XCTAssertEqual(attention.overall, .attention)
        XCTAssertEqual(attention.headline, "能用，但有 4 项要注意")

        let problem = HealthCheckSummary(
            date: Date(), serverBase: "https://example.test",
            doctor: HealthGroupSummary(
                verdict: .ok, headline: "自检通过",
                passCount: 36, warnCount: 0, failCount: 0
            ),
            audit: HealthGroupSummary(
                verdict: .problem, headline: "发现 3 个已知漏洞",
                findingCount: 3, highCount: 1
            )
        )
        XCTAssertEqual(problem.overall, .problem)
        XCTAssertEqual(problem.headline, "发现 1 项异常，建议处理")

        let incomplete = HealthCheckSummary(
            date: Date(), serverBase: "https://example.test",
            doctor: HealthGroupSummary(
                verdict: .incomplete, headline: "自检没跑完"
            ),
            audit: HealthGroupSummary(
                verdict: .ok, headline: "安全审计通过",
                findingCount: 0, highCount: 0
            )
        )
        XCTAssertEqual(incomplete.overall, .incomplete)
        XCTAssertEqual(incomplete.headline, "体检没跑完，结论不完整")

        let ok = HealthCheckSummary(
            date: Date(), serverBase: "https://example.test",
            doctor: HealthGroupSummary(
                verdict: .ok, headline: "自检通过",
                passCount: 36, warnCount: 0, failCount: 0
            ),
            audit: HealthGroupSummary(
                verdict: .ok, headline: "安全审计通过",
                findingCount: 0, highCount: 0
            )
        )
        XCTAssertEqual(ok.overall, .ok)
        XCTAssertEqual(ok.headline, "体检通过，没有发现问题")
    }

    func testSummaryCodableRoundTrip() throws {
        let summary = HealthCheckSummary(
            date: Date(timeIntervalSince1970: 1_763_000_000),
            serverBase: "https://example.test",
            doctor: HealthGroupSummary(
                verdict: .attention, headline: "自检有 4 项要注意",
                passCount: 32, warnCount: 4, failCount: 0
            ),
            audit: nil
        )
        let data = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(
            HealthCheckSummary.self, from: data
        )
        XCTAssertEqual(decoded, summary)
        // 留痕只存摘要：编码产物里不许出现原始日志字样
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("Traceback"))
        XCTAssertFalse(text.contains("lines"))
    }
}
