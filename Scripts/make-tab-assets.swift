import AppKit
import CoreGraphics
import ObjectiveC.runtime

// §382 B1 资产生成器 v3：CoreGlyphs 矢量母版（CoreUI 插值路径，
// Light 字重 / 24pt）→ 底栏五枚模板图 PDF。
// 标定：以 NSImage 24pt light 活渲染为真值——先按墨迹框尺寸比
// 做逐轴缩放校正（吸收 AppKit 对符号的对齐框缩放），再按墨迹
// 框原点做平移对齐（映射系数实测探针求得），像素差验收。

_ = dlopen("/System/Library/PrivateFrameworks/CoreUI.framework/CoreUI", RTLD_NOW)

func imp<T>(_ obj: AnyObject, _ sel: String, as _: T.Type) -> T? {
    let selector = NSSelectorFromString(sel)
    guard let m = class_getInstanceMethod(type(of: obj), selector) else { return nil }
    return unsafeBitCast(method_getImplementation(m), to: T.self)
}
func clsImp<T>(_ cls: AnyClass, _ sel: String, as _: T.Type) -> T? {
    let selector = NSSelectorFromString(sel)
    guard let m = class_getClassMethod(cls, selector) else { return nil }
    return unsafeBitCast(method_getImplementation(m), to: T.self)
}

typealias InitURLFn = @convention(c) (AnyObject, Selector, NSURL, UnsafeRawPointer?) -> AnyObject?
typealias GlyphFn = @convention(c) (AnyObject, Selector, NSString, CGFloat, Int, Int, Int, Int, CGFloat, NSString?) -> AnyObject?
typealias PathFn = @convention(c) (AnyObject, Selector) -> Unmanaged<CGPath>?

let catalogCls = NSClassFromString("CUICatalog")!
let carURL = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/SFSymbols.framework/Versions/A/Resources/CoreGlyphs.bundle/Contents/Resources/Assets.car")
let allocFn = clsImp(catalogCls, "alloc", as: (@convention(c) (AnyClass, Selector) -> AnyObject).self)!
let rawAlloc = allocFn(catalogCls, NSSelectorFromString("alloc"))
let catalog = imp(rawAlloc, "initWithURL:error:", as: InitURLFn.self)!(rawAlloc, NSSelectorFromString("initWithURL:error:"), carURL as NSURL, nil)!
let glyphSelName = "namedVectorGlyphWithName:scaleFactor:deviceIdiom:layoutDirection:glyphSize:glyphWeight:glyphPointSize:appearanceName:"
let glyphFn = imp(catalog, glyphSelName, as: GlyphFn.self)!
let glyphSel = NSSelectorFromString(glyphSelName)

func glyphPath(name: String, direction: Int) -> CGPath? {
    guard let g = glyphFn(catalog, glyphSel, name as NSString, 1.0, 0, direction, 0, 3, 24.0, nil),
          let pfn = imp(g, "CGPath", as: PathFn.self) else { return nil }
    return pfn(g, NSSelectorFromString("CGPath"))?.takeUnretainedValue()
}

let S = 10
struct InkMap {
    var w: Int, h: Int
    var ink: [Bool]
    func stats() -> (density: Double, minX: Int, minY: Int, maxX: Int, maxY: Int) {
        var n = 0, minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h { for x in 0..<w where ink[y * w + x] {
            n += 1
            if x < minX { minX = x }; if x > maxX { maxX = x }
            if y < minY { minY = y }; if y > maxY { maxY = y }
        } }
        return (Double(n) / Double(w * h), minX, minY, maxX, maxY)
    }
}

func truthMap(symbol: String, frame: CGSize) -> InkMap {
    let base = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!
    let img = base.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 24, weight: .light)) ?? base
    let w = Int(frame.width * Double(S)), h = Int(frame.height * Double(S))
    let bmp = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bmp.size = frame
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bmp)
    NSColor.black.set()
    img.draw(in: NSRect(origin: .zero, size: frame))
    NSGraphicsContext.restoreGraphicsState()
    var ink = [Bool](repeating: false, count: w * h)
    for y in 0..<h { for x in 0..<w {
        if let c = bmp.colorAt(x: x, y: y), c.alphaComponent > 0.5 { ink[y * w + x] = true }
    } }
    return InkMap(w: w, h: h, ink: ink)
}

func pathMap(frame: CGSize, path: CGPath, tx: Double, ty: Double) -> InkMap {
    let w = Int(frame.width * Double(S)), h = Int(frame.height * Double(S))
    let cs = CGColorSpaceCreateDeviceGray()
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    ctx.setFillColor(gray: 1, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.scaleBy(x: CGFloat(S), y: CGFloat(S))
    ctx.setFillColor(gray: 0, alpha: 1)
    ctx.translateBy(x: tx, y: ty)
    ctx.addPath(path)
    ctx.fillPath()
    ctx.flush()
    let data = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h)
    var ink = [Bool](repeating: false, count: w * h)
    // CGContext 缓冲 row 0 = 底部（y-up 原点），真值 colorAt row 0 = 顶部：
    // 翻行统一到顶原点口径，否则标定会把字形竖直镜位（v2/v3 实证）。
    for y in 0..<h { for x in 0..<w {
        ink[(h - 1 - y) * w + x] = data[y * w + x] < 127
    } }
    return InkMap(w: w, h: h, ink: ink)
}

// 在给定 path 上求平移：探针法测映射系数后一步到位，再迭代一轮修正
func solveTranslation(frame: CGSize, path: CGPath, truth: InkMap) -> (tx: Double, ty: Double, map: InkMap) {
    let ts = truth.stats()
    var tx = 0.0, ty = 0.0
    var map = pathMap(frame: frame, path: path, tx: tx, ty: ty)
    for _ in 0..<3 {
        let s0 = map.stats()
        let rx = pathMap(frame: frame, path: path, tx: tx + 2, ty: ty)
        let ry = pathMap(frame: frame, path: path, tx: tx, ty: ty + 2)
        let mxPx = Double(rx.stats().minX - s0.minX) / 2.0
        let myPx = Double(ry.stats().minY - s0.minY) / 2.0
        if mxPx == 0 || myPx == 0 { break }
        tx += Double(ts.minX - s0.minX) / mxPx
        ty += Double(ts.minY - s0.minY) / myPx
        map = pathMap(frame: frame, path: path, tx: tx, ty: ty)
        let s = map.stats()
        if abs(s.minX - ts.minX) <= 1 && abs(s.minY - ts.minY) <= 1 { break }
    }
    return (tx, ty, map)
}

struct Job { let symbol: String; let catalog: String; let asset: String; let dirs: [Int] }
let jobs = [
    Job(symbol: "message", catalog: "message", asset: "tab.chat", dirs: [0]),
    Job(symbol: "doc.text", catalog: "text.document", asset: "tab.feed", dirs: [0]),
    Job(symbol: "lightbulb", catalog: "lightbulb", asset: "tab.ideas", dirs: [0]),
    Job(symbol: "checklist", catalog: "checklist", asset: "tab.goals", dirs: [4, 5]),
    Job(symbol: "tray", catalog: "tray", asset: "tab.files", dirs: [0]),
]

let outDir = "/Users/yangminjie/build/tab-assets-out"
try! FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
var fail = false

for job in jobs {
    let base = NSImage(systemSymbolName: job.symbol, accessibilityDescription: nil)!
    let img = base.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 24, weight: .light)) ?? base
    let frame = img.size
    let truth = truthMap(symbol: job.symbol, frame: frame)
    let ts = truth.stats()
    guard ts.maxX >= 0 else { print("\(job.asset): TRUTH EMPTY"); fail = true; continue }

    var best: (path: CGPath, dir: Int, tx: Double, ty: Double, map: InkMap, sx: Double, sy: Double, diffPct: Double)? = nil
    for dir in job.dirs {
        guard let rawPath = glyphPath(name: job.catalog, direction: dir) else { continue }
        // 逐轴缩放校正：先在原点栅格测 path 墨迹框尺寸（平移不影响尺寸）
        let probe = pathMap(frame: frame, path: rawPath, tx: 0, ty: 0)
        let p0 = probe.stats()
        if p0.maxX < 0 { continue }
        let pathInkW = Double(p0.maxX - p0.minX + 1), pathInkH = Double(p0.maxY - p0.minY + 1)
        let truthInkW = Double(ts.maxX - ts.minX + 1), truthInkH = Double(ts.maxY - ts.minY + 1)
        let sx = truthInkW / pathInkW, sy = truthInkH / pathInkH
        var t = CGAffineTransform(scaleX: sx, y: sy)
        let scaled = rawPath.copy(using: &t)!
        let (tx, ty, map) = solveTranslation(frame: frame, path: scaled, truth: truth)
        var diff = 0
        for i in 0..<(truth.w * truth.h) where truth.ink[i] != map.ink[i] { diff += 1 }
        let diffPct = Double(diff) / Double(truth.w * truth.h) * 100
        print("\(job.asset): dir=\(dir) sx=\(String(format: "%.4f", sx)) sy=\(String(format: "%.4f", sy)) tx=\(String(format: "%.2f", tx)) ty=\(String(format: "%.2f", ty)) diff=\(String(format: "%.2f", diffPct))%")
        if best == nil || diffPct < best!.diffPct { best = (scaled, dir, tx, ty, map, sx, sy, diffPct) }
    }
    guard let b = best else { print("\(job.asset): NO PATH"); fail = true; continue }
    let ps = b.map.stats()
    print("\(job.asset): CHOSEN dir=\(b.dir) frame=\(frame) truthDensity=\(String(format: "%.4f", ts.density)) placedDensity=\(String(format: "%.4f", ps.density)) truthInk=(\(ts.minX),\(ts.minY))-(\(ts.maxX),\(ts.maxY)) placedInk=(\(ps.minX),\(ps.minY))-(\(ps.maxX),\(ps.maxY)) pixelDiff=\(String(format: "%.2f", b.diffPct))%")

    let data = NSMutableData()
    let consumer = CGDataConsumer(data: data as CFMutableData)!
    var mediaBox = CGRect(origin: .zero, size: frame)
    let pctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)!
    pctx.beginPDFPage(nil)
    pctx.setFillColor(gray: 0, alpha: 1)
    pctx.translateBy(x: b.tx, y: b.ty)
    pctx.addPath(b.path)
    pctx.fillPath()
    pctx.endPDFPage()
    pctx.closePDF()
    let pdfStr = String(data: data as Data, encoding: .isoLatin1) ?? ""
    print("\(job.asset): PDF bytes=\(data.length) hasImage=\(pdfStr.contains("/Image"))")
    try! (data as Data).write(to: URL(fileURLWithPath: "\(outDir)/\(job.asset).pdf"))
}
print(fail ? "DONE_WITH_FAILURES" : "DONE")
