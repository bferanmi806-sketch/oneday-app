import UIKit
import XCTest
@testable import OneDayApp

/// 【探针分支 probe/gen5-t4-detectors 专用，禁止合入任何线】
/// 包 5 T4 数据检测探针·单测层（筹备稿 §2.2-2 施工第一步实测）：
/// 本文件不断言产品行为、只采集证据——全部结果以 T4PROBE 前缀
/// print 到测试日志，报告 gen5-t4-probe-report-20261115.md 据
/// CI 日志逐行摘录。三层证据：
///  1. ENGINE：NSDataDetector（UITextView 探测的同一引擎）对
///     语料逐类扫描——命中形态与误报面。
///  2. LINK：与 makeUIView 逐行同构配置的 SelectableUITextView
///     在窗口内落定后，.link 属性显形枚举——哪类探测在真承载
///     里变成可点链接、URL 载荷是什么形态。
///  3. COPY：候选开集下选区/复制对命中段的影响（内容不被改写、
///     复制产物＝原文）。
@MainActor
final class Gen5T4DetectorProbeTests: XCTestCase {

    private var window: UIWindow!

    override func tearDown() async throws {
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        try await super.tearDown()
    }

    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
    }

    // MARK: - 1. 引擎层扫描

    func testEngineCorpusScan() throws {
        let typeMap: [(String, NSTextCheckingResult.CheckingType)] = [
            ("phoneNumber", .phoneNumber),
            ("link", .link),
            ("date", .date),
            ("address", .address),
        ]
        for entry in DetectorProbeCorpus.all {
            let ns = entry.text as NSString
            for (name, type) in typeMap {
                let detector = try NSDataDetector(types: type.rawValue)
                let matches = detector.matches(
                    in: entry.text,
                    range: NSRange(location: 0, length: ns.length)
                )
                if matches.isEmpty {
                    print("T4PROBE ENGINE|entry=\(entry.id)|type=\(name)|hits=0")
                }
                for m in matches {
                    let sub = ns.substring(with: m.range)
                    var extra = ""
                    if let date = m.date {
                        extra = "date=\(date)"
                    }
                    if let phone = m.phoneNumber {
                        extra = "phone=\(phone)"
                    }
                    if let url = m.url {
                        extra = "url=\(url.absoluteString)"
                    }
                    print("T4PROBE ENGINE|entry=\(entry.id)|type=\(name)|match=\"\(sub)\"|loc=\(m.range.location)|len=\(m.range.length)|\(extra)")
                }
            }
        }
    }

    // MARK: - 2. 文本视图链接显形

    /// 与 SelectableTextView.swift makeUIView 逐行同构的装配
    /// （探针注释锚点：isEditable/isSelectable/isScrollEnabled/
    /// TK2 构造/inset/padding 五项照抄，dataDetectorTypes 为变量）
    private func makeProbeTextView(
        detectorTypes: UIDataDetectorTypes?
    ) -> SelectableUITextView {
        let textView = SelectableUITextView(usingTextLayoutManager: true)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        if let detectorTypes {
            textView.dataDetectorTypes = detectorTypes
        }
        return textView
    }

    private func linkRuns(of textView: UITextView) -> [(String, String)] {
        guard let attributed = textView.attributedText else { return [] }
        var runs: [(String, String)] = []
        let full = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.link, in: full) { value, range, _ in
            guard let value else { return }
            let sub = attributed.attributedSubstring(from: range).string
            let payload: String
            if let url = value as? URL {
                payload = url.absoluteString
            } else {
                payload = "\(value)"
            }
            runs.append((sub, payload))
        }
        return runs
    }

    /// 等探测落定：轮询 .link 总数直至连续两次不变（上限约 5 秒）
    private func awaitDetection(of textView: UITextView) {
        var lastCount = -1
        for _ in 0..<10 {
            spinRunLoop(seconds: 0.5)
            textView.layoutIfNeeded()
            let count = linkRuns(of: textView).count
            if count == lastCount, count >= 0 {
                return
            }
            lastCount = count
        }
    }

    func testTextViewLinkManifestation() {
        let fresh = UITextView()
        print("T4PROBE DEFAULT|untouched UITextView.dataDetectorTypes rawValue=\(fresh.dataDetectorTypes.rawValue)")

        let sets: [(String, UIDataDetectorTypes?)] = [
            ("untouched", nil),
            ("off", []),
            ("candidate", [.phoneNumber, .link, .calendarEvent, .address]),
            ("all", .all),
        ]
        let entryIDs = [
            "phoneMixed", "linkBare", "email", "dateAbsZhText",
            "dateRelZh", "addrZhText", "addrCityText", "fpOrder",
            "fpNums", "mixedLong",
        ]
        let entries = DetectorProbeCorpus.all.filter { entryIDs.contains($0.id) }

        let host = UIViewController()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.frame = CGRect(x: 0, y: 0, width: 380, height: 1200)
        host.view.addSubview(stack)
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 1400))
        window.rootViewController = host
        window.makeKeyAndVisible()

        for (setName, set) in sets {
            for entry in entries {
                let textView = makeProbeTextView(detectorTypes: set)
                textView.attributedText = NSAttributedString(
                    string: entry.text,
                    attributes: [.font: UIFont.preferredFont(forTextStyle: .callout)]
                )
                stack.addArrangedSubview(textView)
                window.layoutIfNeeded()
                awaitDetection(of: textView)
                let runs = linkRuns(of: textView)
                let contentIntact = textView.attributedText?.string == entry.text
                print("T4PROBE LINK|set=\(setName)|entry=\(entry.id)|links=\(runs.count)|contentIntact=\(contentIntact)")
                for (sub, payload) in runs {
                    print("T4PROBE LINK|set=\(setName)|entry=\(entry.id)|match=\"\(sub)\"|payload=\"\(payload)\"")
                }
                stack.removeArrangedSubview(textView)
                textView.removeFromSuperview()
            }
        }
    }

    // MARK: - 3. 选区与复制（候选开集）

    func testSelectionAndCopyOverDetectedSpan() {
        let entry = DetectorProbeCorpus.all.first { $0.id == "mixedLong" }!
        let host = UIViewController()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        window.rootViewController = host
        window.makeKeyAndVisible()

        let textView = makeProbeTextView(
            detectorTypes: [.phoneNumber, .link, .calendarEvent, .address]
        )
        textView.frame = CGRect(x: 0, y: 0, width: 380, height: 400)
        textView.attributedText = NSAttributedString(
            string: entry.text,
            attributes: [.font: UIFont.preferredFont(forTextStyle: .callout)]
        )
        host.view.addSubview(textView)
        window.layoutIfNeeded()
        awaitDetection(of: textView)

        // 选中电话段（含命中链接属性）→ 选区成立、复制产物＝原文片段
        let ns = entry.text as NSString
        let phoneRange = ns.range(of: "13800138000")
        XCTAssertTrue(phoneRange.location != NSNotFound)
        textView.selectedRange = phoneRange
        print("T4PROBE COPY|selectedRangeAfterSet=\(textView.selectedRange)|target=\(phoneRange)")
        UIPasteboard.general.string = "PROBE-SENTINEL"
        textView.copy(nil)
        let pasted = UIPasteboard.general.string ?? "<nil>"
        print("T4PROBE COPY|phoneSpanPaste=\"\(pasted)\"|equalsRaw=\(pasted == "13800138000")")

        // 全选复制 → 与原文逐字一致（探测不改写内容本体）
        textView.selectedRange = NSRange(location: 0, length: ns.length)
        textView.copy(nil)
        let pastedAll = UIPasteboard.general.string ?? "<nil>"
        print("T4PROBE COPY|fullPasteEqualsOriginal=\(pastedAll == entry.text)")

        // 命中段与普通段的选区可扩展性：从电话段起扩选到行尾
        var extended = phoneRange
        extended.length = ns.length - phoneRange.location
        textView.selectedRange = extended
        print("T4PROBE COPY|extendedSelection=\(textView.selectedRange)|equalsSet=\(textView.selectedRange == extended)")
    }
}
