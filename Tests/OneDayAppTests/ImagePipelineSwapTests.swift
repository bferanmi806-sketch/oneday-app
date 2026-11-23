import Nuke
import OneDayCore
import UIKit
import XCTest
@testable import OneDayApp

/// §418（#23 图片管线换底）钉测：
/// ① 构造器键等价差分——同 (path,mtime,tier) 输入新
///    键恒同、任一分量变新键必变（与旧 RemoteImageKey
///    的划分同构），且路由 URL 嵌旧键原文；
/// ② DataLoader 四路分发——变体（登记通道优先／桥口
///    径缺席时回落原图）／原图／海报／本地合成键，含
///    鉴权通道不串线断言（原图路不许碰变体通道、海
///    报路不许碰原图通道、无登记必失败不许猜）。
final class ImagePipelineSwapTests: XCTestCase {

    // MARK: - 夹具

    /// 1×1 PNG（解码必成）
    private func pngData() -> Data {
        Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC"
            + "AAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII="
        )!
    }

    private final class CallBox: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var renditionKinds: [String] = []
        private(set) var originalCalls = 0

        func noteRendition(_ kind: String) {
            lock.lock()
            renditionKinds.append(kind)
            lock.unlock()
        }

        func noteOriginal() {
            lock.lock()
            originalCalls += 1
            lock.unlock()
        }
    }

    /// 每测一条新管线（无磁盘层、内存层独立），防串话
    private func makePipeline() -> ImagePipeline {
        var configuration = ImagePipeline.Configuration(
            dataLoader: HermesImageDataLoader.shared)
        configuration.dataCache = nil
        return ImagePipeline(configuration: configuration)
    }

    private func uniquePath() -> String {
        "/vault/swap-\(UUID().uuidString).jpg"
    }

    // MARK: - ① 键等价差分

    func testFactoryKeyPartitionMatchesLegacyKey() {
        let pipeline = OneDayImagePipelines.remote
        let path = "/vault/a b.jpg"
        let base = RemoteImageRequestFactory.tierRequest(
            path: path, mtime: 100, tier: .thumb)
        let baseKey = pipeline.cache.makeDataCacheKey(
            for: base)

        // 同输入恒同键
        let again = RemoteImageRequestFactory.tierRequest(
            path: path, mtime: 100, tier: .thumb)
        XCTAssertEqual(
            pipeline.cache.makeDataCacheKey(for: again),
            baseKey)

        // 任一分量变 → 键必变
        let otherPath = RemoteImageRequestFactory.tierRequest(
            path: "/vault/other.jpg", mtime: 100, tier: .thumb)
        XCTAssertNotEqual(
            pipeline.cache.makeDataCacheKey(for: otherPath),
            baseKey)
        let otherMtime = RemoteImageRequestFactory.tierRequest(
            path: path, mtime: 101, tier: .thumb)
        XCTAssertNotEqual(
            pipeline.cache.makeDataCacheKey(for: otherMtime),
            baseKey)
        let otherTier = RemoteImageRequestFactory.tierRequest(
            path: path, mtime: 100, tier: .viewer)
        XCTAssertNotEqual(
            pipeline.cache.makeDataCacheKey(for: otherTier),
            baseKey)
        let original = RemoteImageRequestFactory.tierRequest(
            path: path, mtime: 100, tier: .original)
        XCTAssertNotEqual(
            pipeline.cache.makeDataCacheKey(for: original),
            baseKey)

        // 路由 URL 嵌旧键原文（等价性的字面证据）
        XCTAssertTrue(
            base.url?.absoluteString.contains(
                RemoteImageKey.make(
                    path: path, mtime: 100, tier: .thumb))
                ?? false)
        XCTAssertTrue(
            original.url?.absoluteString.contains(
                RemoteImageKey.make(
                    path: path, mtime: 100, tier: .original))
                ?? false)
    }

    func testFactoryRouteParsingRoundTrip() {
        let path = "/vault/dir/pic one.jpg"
        let rendition = RemoteImageRequestFactory
            .renditionRequest(path: path, mtime: 7, tier: .detail)
        XCTAssertEqual(
            RemoteImageRequestFactory.route(
                for: rendition.url!),
            .rendition(path: path, width: 2048))
        let original = RemoteImageRequestFactory
            .originalRequest(path: path, mtime: 7)
        XCTAssertEqual(
            RemoteImageRequestFactory.route(
                for: original.url!),
            .original(path: path))
        let poster = RemoteImageRequestFactory
            .posterRequest(path: path, mtime: 7, pixelCap: 360)
        XCTAssertEqual(
            RemoteImageRequestFactory.route(
                for: poster.url!),
            .poster(path: path))
        // 公开 URL 不是路由
        XCTAssertNil(
            RemoteImageRequestFactory.route(
                for: URL(string: "https://example.com/a.jpg")!))
        // 本地键往返
        let entryID = UUID()
        let local = RemoteImageRequestFactory.localRequest(
            entryID: entryID, index: 2, byteCount: 42)
        XCTAssertEqual(
            RemoteImageRequestFactory.localKey(for: local.url!),
            RemoteImageRequestFactory.localKey(
                entryID: entryID, index: 2, byteCount: 42))
    }

    func testPublicRequestPassesURLThrough() {
        let url = URL(string: "https://example.com/feed/x.jpg")!
        let request = RemoteImageRequestFactory.publicRequest(
            url: url, longEdgeCap: 1200)
        XCTAssertEqual(request.url, url)
        XCTAssertFalse(request.processors.isEmpty)
    }

    // MARK: - ② 四路分发

    func testRenditionPrefersRegisteredRenditionChannel()
        async throws {
        let path = uniquePath()
        let box = CallBox()
        let data = pngData()
        HermesImageRouting.shared.register(
            path: path, config: nil,
            originalLoader: {
                box.noteOriginal()
                return data
            },
            renditionLoader: { kind in
                box.noteRendition(kind)
                return data
            })
        let pipeline = makePipeline()
        let image = try await pipeline.image(
            for: RemoteImageRequestFactory.renditionRequest(
                path: path, mtime: 3, tier: .thumb))
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertEqual(box.renditionKinds, ["image"])
        XCTAssertEqual(box.originalCalls, 0)
    }

    func testRenditionFallsBackToOriginalChannel()
        async throws {
        let path = uniquePath()
        let box = CallBox()
        let data = pngData()
        HermesImageRouting.shared.register(
            path: path, config: nil,
            originalLoader: {
                box.noteOriginal()
                return data
            },
            renditionLoader: { kind in
                box.noteRendition(kind)
                return nil
            })
        let pipeline = makePipeline()
        _ = try await pipeline.image(
            for: RemoteImageRequestFactory.renditionRequest(
                path: path, mtime: 3, tier: .viewer))
        XCTAssertEqual(box.renditionKinds, ["image"])
        XCTAssertEqual(box.originalCalls, 1)
    }

    func testOriginalRouteNeverTouchesRenditionChannel()
        async throws {
        let path = uniquePath()
        let box = CallBox()
        let data = pngData()
        HermesImageRouting.shared.register(
            path: path, config: nil,
            originalLoader: {
                box.noteOriginal()
                return data
            },
            renditionLoader: { kind in
                box.noteRendition(kind)
                return data
            })
        let pipeline = makePipeline()
        _ = try await pipeline.image(
            for: RemoteImageRequestFactory.originalRequest(
                path: path, mtime: 3))
        XCTAssertEqual(box.originalCalls, 1)
        XCTAssertTrue(box.renditionKinds.isEmpty)
    }

    func testPosterRouteUsesPosterKindAndNoOriginal()
        async throws {
        let path = uniquePath()
        let box = CallBox()
        let data = pngData()
        HermesImageRouting.shared.register(
            path: path, config: nil,
            originalLoader: {
                box.noteOriginal()
                return data
            },
            renditionLoader: { kind in
                box.noteRendition(kind)
                return data
            })
        let pipeline = makePipeline()
        _ = try await pipeline.image(
            for: RemoteImageRequestFactory.posterRequest(
                path: path, mtime: 3, pixelCap: 360))
        XCTAssertEqual(box.renditionKinds, ["poster"])
        XCTAssertEqual(box.originalCalls, 0)
    }

    func testUnregisteredRoutedPathFailsWithoutGuessing()
        async {
        let path = uniquePath()
        let pipeline = makePipeline()
        do {
            _ = try await pipeline.image(
                for: RemoteImageRequestFactory.renditionRequest(
                    path: path, mtime: 3, tier: .thumb))
            XCTFail("无登记的鉴权路由不许猜通道、必须失败")
        } catch {
            // 预期失败
        }
    }

    func testLocalDataRouteResolvesInjectedData() async throws {
        let entryID = UUID()
        let data = pngData()
        let key = RemoteImageRequestFactory.localKey(
            entryID: entryID, index: 0,
            byteCount: data.count)
        LocalImageDataRegistry.shared.register(
            key: key, data: data)
        let pipeline = makePipeline()
        let image = try await pipeline.image(
            for: RemoteImageRequestFactory.localRequest(
                entryID: entryID, index: 0,
                byteCount: data.count))
        XCTAssertGreaterThan(image.size.width, 0)
    }

    func testLocalDataRouteFailsWhenNotInjected() async {
        let pipeline = makePipeline()
        do {
            _ = try await pipeline.image(
                for: RemoteImageRequestFactory.localRequest(
                    entryID: UUID(), index: 0, byteCount: 9))
            XCTFail("未注入的本地键必须失败")
        } catch {
            // 预期失败
        }
    }
}
