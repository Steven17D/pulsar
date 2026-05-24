#!/usr/bin/env swift
// Regenerates wled-tap/AppIcon.icns from scratch. The icon is checked
// into the repo as a binary blob so the home-manager activation can
// install it without an extra build step; this script exists so the
// design (5 EQ bars in palette gradients + glow dots on a deep-purple
// squircle) can be tweaked and the .icns rebuilt deterministically.
//
// Usage from this directory:
//   swift gen-icon.swift && mv /tmp/wled-tap.icns AppIcon.icns

import AppKit
import CoreGraphics
import Foundation

let outDir = "/tmp/wled-tap-iconset"
try? FileManager.default.removeItem(atPath: outDir)
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func draw(size: Int) -> Data {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    let S = CGFloat(size)
    let rect = CGRect(x: 0, y: 0, width: S, height: S)
    let cornerR = S * 0.2237
    let bgPath = CGPath(roundedRect: rect, cornerWidth: cornerR, cornerHeight: cornerR, transform: nil)

    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    let bg = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 0.16, green: 0.04, blue: 0.28, alpha: 1),
        CGColor(red: 0.02, green: 0.01, blue: 0.06, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg,
        start: CGPoint(x: 0, y: S),
        end:   CGPoint(x: S, y: 0),
        options: [])

    let vignette = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 0, green: 0, blue: 0, alpha: 0.0),
        CGColor(red: 0, green: 0, blue: 0, alpha: 0.45),
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(vignette,
        startCenter: CGPoint(x: S/2, y: S * 0.15), startRadius: 0,
        endCenter:   CGPoint(x: S/2, y: S * 0.15), endRadius: S * 0.85,
        options: [])

    let palettes: [[CGColor]] = [
        [CGColor(red: 0.6, green: 0.05, blue: 0.4, alpha: 1),
         CGColor(red: 1.0, green: 0.95, blue: 0.6, alpha: 1)],
        [CGColor(red: 0.0, green: 0.20, blue: 0.65, alpha: 1),
         CGColor(red: 0.4, green: 0.95, blue: 1.00, alpha: 1)],
        [CGColor(red: 0.05, green: 0.40, blue: 0.15, alpha: 1),
         CGColor(red: 1.0,  green: 0.95, blue: 0.40, alpha: 1)],
        [CGColor(red: 0.9, green: 0.05, blue: 0.70, alpha: 1),
         CGColor(red: 0.5, green: 1.00, blue: 1.00, alpha: 1)],
        [CGColor(red: 0.6, green: 0.0,  blue: 0.0, alpha: 1),
         CGColor(red: 1.0, green: 1.0,  blue: 0.85, alpha: 1)],
    ]
    let heights: [CGFloat] = [0.40, 0.65, 0.82, 0.55, 0.34]

    let nBars = 5
    let barW = S * 0.105
    let spacing = S * 0.04
    let totalW = barW * CGFloat(nBars) + spacing * CGFloat(nBars - 1)
    let startX = (S - totalW) / 2
    let baseY = S * 0.18
    let maxBarH = S * 0.58

    for i in 0..<nBars {
        let h = maxBarH * heights[i]
        let x = startX + CGFloat(i) * (barW + spacing)
        let barRect = CGRect(x: x, y: baseY, width: barW, height: h)
        let r = barW * 0.35
        let barPath = CGPath(roundedRect: barRect, cornerWidth: r, cornerHeight: r, transform: nil)

        ctx.saveGState()
        ctx.addPath(barPath)
        ctx.clip()
        let pg = CGGradient(colorsSpace: cs, colors: palettes[i] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(pg,
            start: CGPoint(x: 0, y: baseY),
            end:   CGPoint(x: 0, y: baseY + h),
            options: [])
        ctx.restoreGState()

        let dotR = barW * 0.55
        let dotY = baseY + h + S * 0.045
        let dotRect = CGRect(
            x: x + (barW - dotR) / 2,
            y: dotY,
            width: dotR, height: dotR
        )
        let topColor = palettes[i].last!
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: S * 0.04, color: topColor)
        ctx.setFillColor(topColor)
        ctx.fillEllipse(in: dotRect)
        ctx.restoreGState()
    }

    let gloss = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.10),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gloss,
        start: CGPoint(x: 0, y: S),
        end:   CGPoint(x: 0, y: S * 0.55),
        options: [])

    ctx.restoreGState()

    let img = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: img)
    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(Int, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]
for (size, name) in sizes {
    let data = draw(size: size)
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}

// Wrap iconset → .icns via the system tool.
let isetDest = "/tmp/wled-tap.iconset"
try? FileManager.default.removeItem(atPath: isetDest)
try FileManager.default.moveItem(atPath: outDir, toPath: isetDest)
let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments = ["-c", "icns", isetDest, "-o", "/tmp/wled-tap.icns"]
try task.run()
task.waitUntilExit()
print("/tmp/wled-tap.icns")
