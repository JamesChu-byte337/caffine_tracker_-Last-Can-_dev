import AppKit
import CoreGraphics

// Usage: process_logo <input.jpg> <icon-out.png> <goose-out.png>
let args = CommandLine.arguments
let input = NSImage(contentsOfFile: args[1])!
var rect = CGRect(origin: .zero, size: input.size)
let source = input.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
let w = source.width, h = source.height

func rgbaContext(_ width: Int, _ height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func writePNG(_ image: CGImage, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

// Pixels
let ctx = rgbaContext(w, h)
ctx.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
let buffer = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
func px(_ x: Int, _ y: Int) -> (Int, Int, Int) {
    let i = (y * w + x) * 4
    return (Int(buffer[i]), Int(buffer[i + 1]), Int(buffer[i + 2]))
}
let bg = px(5, 5)
print("background sample:", bg, "border sample:", px(512, 250))

// 1. App icon: crop square around the sticker so it fills more of the icon; opaque, 1024×1024.
let cropSide = 880
let crop = source.cropping(to: CGRect(x: (w - cropSide) / 2 + 3, y: (h - cropSide) / 2, width: cropSide, height: cropSide))!
let iconCtx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 1024 * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
iconCtx.interpolationQuality = .high
iconCtx.draw(crop, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
writePNG(iconCtx.makeImage()!, args[2])

// 2. Transparent goose: flood-fill the grey background (and its soft shadow) from the edges.
// The sticker's white border is brighter than the background, so the fill stops there.
func isBackground(_ c: (Int, Int, Int)) -> Bool {
    let maxC = max(c.0, c.1, c.2), minC = min(c.0, c.1, c.2)
    return maxC - minC < 14 && maxC < 243 && maxC > 150
}
var visited = [Bool](repeating: false, count: w * h)
var stack: [(Int, Int)] = []
for x in 0..<w { stack.append((x, 0)); stack.append((x, h - 1)) }
for y in 0..<h { stack.append((0, y)); stack.append((w - 1, y)) }
while let (x, y) = stack.popLast() {
    guard x >= 0, y >= 0, x < w, y < h, !visited[y * w + x], isBackground(px(x, y)) else { continue }
    visited[y * w + x] = true
    stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
}
var minX = w, minY = h, maxX = 0, maxY = 0
for y in 0..<h {
    for x in 0..<w {
        let i = (y * w + x) * 4
        if visited[y * w + x] {
            buffer[i] = 0; buffer[i + 1] = 0; buffer[i + 2] = 0; buffer[i + 3] = 0
        } else {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
}
// Soften the cut edge: half-transparent for kept pixels touching removed ones.
for y in 1..<(h - 1) {
    for x in 1..<(w - 1) where !visited[y * w + x] {
        if visited[y * w + x + 1] || visited[y * w + x - 1] || visited[(y + 1) * w + x] || visited[(y - 1) * w + x] {
            let i = (y * w + x) * 4
            for k in 0..<4 { buffer[i + k] = UInt8(Int(buffer[i + k]) / 2) }
        }
    }
}
print("goose bounds:", minX, minY, maxX, maxY)
let cut = ctx.makeImage()!.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))!
writePNG(cut, args[3])
