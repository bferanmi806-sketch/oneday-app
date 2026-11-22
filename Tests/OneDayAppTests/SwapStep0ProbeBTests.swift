import UIKit
import XCTest

/// 换引擎施工图步骤 0 · 探针 B（步骤 3 开工门）：单 section＋
/// 逐 item 组高布局 spike。对照现行 section-per-row 构造
/// （§329 makeSection 的等值镜像），在测试装配里复刻 §329
/// 成环条件——可见区行高在布局 pass 之间被替换（临界估高
/// →量测确高、带方差注入）＋连续小步滚动——验新构造是否
/// 同样收敛：布局提供者调用有界、停滚后 contentSize 稳态
/// 逐值不动、逐行几何与现行构造逐值等价。
/// 边界（诚实）：本 spike 用纯 UIView cell 隔离「布局构造」
/// 单一变量（两构造的 item/group 尺寸均为 .absolute、无
/// 自适应回推通道）；托管内容与布局的相互作用由生产链
/// §329 压测组在步骤 3 验收时把守，不在本 spike 射程内。
@MainActor
final class SwapStep0ProbeBTests: XCTestCase {

    // §329 几何单源（与 makeSection 逐值同）
    private let topPad: CGFloat = 16
    private let bottomPad: CGFloat = 8
    private let rowSpacing: CGFloat = 24
    private let hPad: CGFloat = 20
    private let viewW: CGFloat = 402
    private let viewH: CGFloat = 874

    private var window: UIWindow!

    override func tearDown() {
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    /// 高度账（spike 内以行序代行键——步骤 3 的按键存取
    /// 是数据层改造，本 spike 只验布局构造读账形态）
    private final class HeightBook {
        var fed: [CGFloat] = []
        var truth: [CGFloat] = []
        var providerCalls = 0
        var groupsBuilt = 0
    }

    private enum Construction {
        case sectionPerRow
        case singleSectionEstimated
        case singleSectionAbsoluteSum
    }

    private final class SpikeDS: NSObject,
        UICollectionViewDataSource
    {
        var singleSection = false
        var rowCount = 0
        func numberOfSections(
            in collectionView: UICollectionView
        ) -> Int {
            singleSection ? 1 : rowCount
        }
        func collectionView(
            _ collectionView: UICollectionView,
            numberOfItemsInSection section: Int
        ) -> Int {
            singleSection ? rowCount : 1
        }
        func collectionView(
            _ collectionView: UICollectionView,
            cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            let cell = collectionView
                .dequeueReusableCell(
                    withReuseIdentifier: "cell",
                    for: indexPath
                )
            let row = singleSection
                ? indexPath.item : indexPath.section
            cell.contentView.backgroundColor =
                row % 2 == 0
                ? .systemGray5 : .systemGray4
            return cell
        }
    }

    private func makeLayout(
        _ construction: Construction,
        book: HeightBook
    ) -> UICollectionViewCompositionalLayout {
        let topPad = self.topPad
        let bottomPad = self.bottomPad
        let rowSpacing = self.rowSpacing
        let hPad = self.hPad
        return UICollectionViewCompositionalLayout {
            sectionIndex, _ in
            book.providerCalls += 1
            let n = book.fed.count
            switch construction {
            case .sectionPerRow:
                // makeSection 等值镜像
                let h = sectionIndex < n
                    ? book.fed[sectionIndex] : 120
                let itemSize = NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .absolute(max(0, h))
                )
                let item = NSCollectionLayoutItem(
                    layoutSize: itemSize
                )
                let groupSize = NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .absolute(max(0, h))
                )
                let group = NSCollectionLayoutGroup
                    .horizontal(
                        layoutSize: groupSize,
                        subitems: [item]
                    )
                let section = NSCollectionLayoutSection(
                    group: group
                )
                section.contentInsets =
                    NSDirectionalEdgeInsets(
                        top: sectionIndex == 0
                            ? topPad : 0,
                        leading: hPad,
                        bottom: sectionIndex >= n - 1
                            ? bottomPad : rowSpacing,
                        trailing: hPad
                    )
                return section
            case .singleSectionEstimated,
                 .singleSectionAbsoluteSum:
                // 单 section：逐 item 一组（组高 .absolute
                // 消费高度账），组距由根组 interItemSpacing
                // 承担（与现行 section 底 inset 逐值等价）
                var itemGroups: [NSCollectionLayoutGroup] =
                    []
                itemGroups.reserveCapacity(n)
                for i in 0..<n {
                    let h = max(0, book.fed[i])
                    let itemSize =
                        NSCollectionLayoutSize(
                            widthDimension:
                                .fractionalWidth(1),
                            heightDimension: .absolute(h)
                        )
                    let item = NSCollectionLayoutItem(
                        layoutSize: itemSize
                    )
                    let gSize = NSCollectionLayoutSize(
                        widthDimension:
                            .fractionalWidth(1),
                        heightDimension: .absolute(h)
                    )
                    itemGroups.append(
                        NSCollectionLayoutGroup.horizontal(
                            layoutSize: gSize,
                            subitems: [item]
                        )
                    )
                    book.groupsBuilt += 1
                }
                let sumH = book.fed.reduce(0, +)
                    + rowSpacing * CGFloat(max(0, n - 1))
                let rootHeight: NSCollectionLayoutDimension
                switch construction {
                case .singleSectionEstimated:
                    // 故意粗估（44/行）：强制框架在首
                    // pass 后修正根组高——成环条件之一
                    rootHeight = .estimated(
                        44 * CGFloat(max(1, n))
                    )
                default:
                    rootHeight = .absolute(sumH)
                }
                let rootSize = NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: rootHeight
                )
                let root = NSCollectionLayoutGroup
                    .vertical(
                        layoutSize: rootSize,
                        subitems: itemGroups
                    )
                root.interItemSpacing = .fixed(rowSpacing)
                let section = NSCollectionLayoutSection(
                    group: root
                )
                section.contentInsets =
                    NSDirectionalEdgeInsets(
                        top: topPad, leading: hPad,
                        bottom: bottomPad, trailing: hPad
                    )
                return section
            }
        }
    }

    private func mount(
        _ construction: Construction,
        book: HeightBook,
        ds: SpikeDS
    ) -> UICollectionView {
        let vc = UIViewController()
        let cv = UICollectionView(
            frame: CGRect(
                x: 0, y: 0, width: viewW, height: viewH
            ),
            collectionViewLayout: makeLayout(
                construction, book: book
            )
        )
        cv.backgroundColor = .clear
        cv.contentInsetAdjustmentBehavior = .never
        cv.register(
            UICollectionViewCell.self,
            forCellWithReuseIdentifier: "cell"
        )
        cv.dataSource = ds
        vc.view.addSubview(cv)
        window = UIWindow(frame: CGRect(
            x: 0, y: 0, width: viewW, height: viewH
        ))
        window.rootViewController = vc
        window.makeKeyAndVisible()
        cv.layoutIfNeeded()
        return cv
    }

    private struct ScenarioResult {
        var expectedContentH: CGFloat = 0
        var finalContentH: CGFloat = 0
        var settleStable = false
        var geometryOK = false
        var geometryMismatch = ""
        var providerCalls = 0
        var groupsBuilt = 0
        var invalidations = 0
        var layoutPasses = 0
        var elapsedMs: Double = 0
    }

    /// 场景：临界估高喂入 → 连续小步滚动（步间把可见区
    /// 行替换为量测确高＝pass 间方差注入）→ 全量确高 →
    /// 稳态采样＋逐行几何对账
    private func runScenario(
        _ construction: Construction, rowCount: Int
    ) -> ScenarioResult {
        let book = HeightBook()
        let pattern: [CGFloat] = [
            52, 300, 68, 188, 44, 256, 92, 148,
        ]
        for i in 0..<rowCount {
            let base = pattern[i % pattern.count]
            let jitter = CGFloat((i * 37) % 53)
            book.truth.append(
                min(340, max(40, base + jitter))
            )
        }
        book.fed = book.truth.map {
            max(36, ($0 * 0.72).rounded())
        }
        let ds = SpikeDS()
        ds.singleSection =
            construction != .sectionPerRow
        ds.rowCount = rowCount
        let cv = mount(construction, book: book, ds: ds)

        var result = ScenarioResult()
        let t0 = CFAbsoluteTimeGetCurrent()
        var invalidations = 0
        var passes = 0

        // 前缀和（按当前 fed 帧定位可见行）
        func prefixTops() -> [CGFloat] {
            var tops: [CGFloat] = []
            var y = topPad
            for h in book.fed {
                tops.append(y)
                y += h + rowSpacing
            }
            return tops
        }
        func revealMeasure(
            around offset: CGFloat
        ) {
            let tops = prefixTops()
            var changed = false
            for i in 0..<rowCount {
                let top = tops[i]
                let bottom = top + book.fed[i]
                if bottom > offset - 200,
                   top < offset + viewH + 200,
                   book.fed[i] != book.truth[i] {
                    book.fed[i] = book.truth[i]
                    changed = true
                }
            }
            if changed {
                cv.collectionViewLayout.invalidateLayout()
                invalidations += 1
            }
        }
        func scrollPass(toBottom: Bool) {
            var guardSteps = 0
            while guardSteps < 3000 {
                guardSteps += 1
                let maxOffset = max(
                    0, cv.contentSize.height - viewH
                )
                let current = cv.contentOffset.y
                let done = toBottom
                    ? current >= maxOffset - 0.5
                    : current <= 0.5
                if done { break }
                let next = toBottom
                    ? min(maxOffset, current + 60)
                    : max(0, current - 60)
                cv.contentOffset = CGPoint(
                    x: 0, y: next
                )
                cv.layoutIfNeeded()
                passes += 1
                RunLoop.main.run(
                    until: Date()
                        .addingTimeInterval(0.002)
                )
                if guardSteps % 3 == 0 {
                    revealMeasure(around: next)
                }
            }
        }
        scrollPass(toBottom: true)
        scrollPass(toBottom: false)
        // 全量确高落定
        var anyLeft = false
        for i in 0..<rowCount
        where book.fed[i] != book.truth[i] {
            book.fed[i] = book.truth[i]
            anyLeft = true
        }
        if anyLeft {
            cv.collectionViewLayout.invalidateLayout()
            invalidations += 1
        }
        cv.contentOffset = .zero
        cv.layoutIfNeeded()
        passes += 1

        // 稳态采样：连续三采样（contentSize＋提供者
        // 计数）不变才算收敛
        var samples: [(CGFloat, Int)] = []
        for _ in 0..<5 {
            cv.layoutIfNeeded()
            samples.append((
                cv.contentSize.height,
                book.providerCalls
            ))
            RunLoop.main.run(
                until: Date().addingTimeInterval(0.01)
            )
        }
        let tail = Array(samples.suffix(3))
        result.settleStable =
            tail.allSatisfy { $0 == tail[0] }
        result.finalContentH = cv.contentSize.height
        result.expectedContentH = topPad
            + book.truth.reduce(0, +)
            + rowSpacing * CGFloat(rowCount - 1)
            + bottomPad

        // 逐行几何对账
        var expectedY = topPad
        var firstMismatch = ""
        for i in 0..<rowCount {
            let ip = ds.singleSection
                ? IndexPath(item: i, section: 0)
                : IndexPath(item: 0, section: i)
            guard let attrs = cv.collectionViewLayout
                .layoutAttributesForItem(at: ip)
            else {
                firstMismatch = "row \(i) 无布局属性"
                break
            }
            let f = attrs.frame
            if abs(f.minY - expectedY) > 0.6
                || abs(f.height - book.truth[i]) > 0.6
                || abs(f.minX - hPad) > 0.6
                || abs(f.width - (viewW - hPad * 2)) > 0.6
            {
                firstMismatch =
                    "row \(i) frame=\(f) 期望 y=\(expectedY)"
                    + " h=\(book.truth[i])"
                break
            }
            expectedY += book.truth[i] + rowSpacing
        }
        result.geometryOK = firstMismatch.isEmpty
        result.geometryMismatch = firstMismatch
        result.providerCalls = book.providerCalls
        result.groupsBuilt = book.groupsBuilt
        result.invalidations = invalidations
        result.layoutPasses = passes
        result.elapsedMs =
            (CFAbsoluteTimeGetCurrent() - t0) * 1_000
        return result
    }

    private func report(
        _ name: String, _ r: ScenarioResult
    ) {
        print(String(
            format: "PROBEB|%@|contentH=%.2f|expected=%.2f"
                + "|contentDelta=%+.2f|settleStable=%@"
                + "|geometryOK=%@|mismatch=%@"
                + "|providerCalls=%d|groupsBuilt=%d"
                + "|invalidations=%d|scrollPasses=%d"
                + "|elapsedMs=%.0f",
            name, r.finalContentH, r.expectedContentH,
            r.finalContentH - r.expectedContentH,
            r.settleStable ? "yes" : "no",
            r.geometryOK ? "yes" : "no",
            r.geometryMismatch,
            r.providerCalls, r.groupsBuilt,
            r.invalidations, r.layoutPasses, r.elapsedMs
        ))
    }

    func testProbeBSectionPerRowControl() {
        let r = runScenario(.sectionPerRow, rowCount: 120)
        report("A-sectionPerRow", r)
        XCTAssertTrue(
            r.settleStable, "对照构造停滚后须稳态收敛"
        )
        XCTAssertTrue(
            r.geometryOK,
            "对照构造几何须逐值合：\(r.geometryMismatch)"
        )
        XCTAssertEqual(
            r.finalContentH, r.expectedContentH,
            accuracy: 0.6
        )
    }

    func testProbeBSingleSectionEstimated() {
        let r = runScenario(
            .singleSectionEstimated, rowCount: 120
        )
        report("B-singleSection-estimated", r)
        XCTAssertTrue(
            r.settleStable, "新构造（估算根高）停滚后须稳态收敛"
        )
        XCTAssertTrue(
            r.geometryOK,
            "新构造几何须与对照逐值等价：\(r.geometryMismatch)"
        )
        XCTAssertEqual(
            r.finalContentH, r.expectedContentH,
            accuracy: 0.6
        )
    }

    func testProbeBSingleSectionAbsoluteSum() {
        let r = runScenario(
            .singleSectionAbsoluteSum, rowCount: 120
        )
        report("B-singleSection-absoluteSum", r)
        XCTAssertTrue(
            r.settleStable, "新构造（确值根高）停滚后须稳态收敛"
        )
        XCTAssertTrue(
            r.geometryOK,
            "新构造几何须与对照逐值等价：\(r.geometryMismatch)"
        )
        XCTAssertEqual(
            r.finalContentH, r.expectedContentH,
            accuracy: 0.6
        )
    }

    // MARK: - 提供者成本（N=600，每次失效的重建代价）

    func testProbeBProviderCost() {
        for construction in [
            Construction.sectionPerRow,
            .singleSectionAbsoluteSum,
        ] {
            let n = 600
            let book = HeightBook()
            let pattern: [CGFloat] = [
                52, 300, 68, 188, 44, 256, 92, 148,
            ]
            for i in 0..<n {
                let h = min(
                    340,
                    max(
                        40,
                        pattern[i % pattern.count]
                            + CGFloat((i * 37) % 53)
                    )
                )
                book.truth.append(h)
            }
            book.fed = book.truth
            let ds = SpikeDS()
            ds.singleSection =
                construction != .sectionPerRow
            ds.rowCount = n
            let cv = mount(
                construction, book: book, ds: ds
            )
            var samples: [Double] = []
            var callDeltas: [Int] = []
            for _ in 0..<5 {
                let callsBefore = book.providerCalls
                cv.collectionViewLayout.invalidateLayout()
                let t0 = CFAbsoluteTimeGetCurrent()
                cv.layoutIfNeeded()
                samples.append(
                    (CFAbsoluteTimeGetCurrent() - t0)
                        * 1_000
                )
                callDeltas.append(
                    book.providerCalls - callsBefore
                )
            }
            let sorted = samples.sorted()
            let name = construction == .sectionPerRow
                ? "A-sectionPerRow" : "B-singleSection"
            print(String(
                format: "PROBEB|cost|%@|n=%d"
                    + "|layoutPassMedianMs=%.2f"
                    + "|providerCallsPerPass=%d",
                name, n, sorted[sorted.count / 2],
                callDeltas[callDeltas.count / 2]
            ))
            window?.rootViewController = nil
            window?.isHidden = true
            window = nil
        }
    }
}
