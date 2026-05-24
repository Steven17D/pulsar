import AppKit
import Foundation
import SwiftUI

/// Seeds `ControlModel.shared` with deterministic data so the BarView can
/// be rendered without a Process Tap, TCC prompt, or real WLED on the
/// LAN. Two modes:
///   - `PULSAR_SHOWCASE=1`            → open BarView in a regular NSWindow.
///   - `PULSAR_SHOWCASE_RENDER=<dir>` → render PNG variants to <dir> and exit.
enum Showcase {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["PULSAR_SHOWCASE"] == "1"
            || ProcessInfo.processInfo.environment["PULSAR_SHOWCASE_RENDER"] != nil
    }

    private static var renderDir: String? {
        ProcessInfo.processInfo.environment["PULSAR_SHOWCASE_RENDER"]
    }

    @MainActor
    static func seed(_ model: ControlModel) {
        applyVariant(model, .init(effect: "spectrum", palette: "sunset"))
        if let dir = renderDir {
            DispatchQueue.main.async { renderAll(model: model, dir: dir) }
        } else {
            startSpectrumTimer(model)
            openWindow(model: model)
        }
    }

    private struct Variant {
        let effect: String
        let palette: String
        var brightness: Float = 0.85
        var speed: Float = 1.0
        var intensity: Float = 1.0
        var name: String { "\(effect)-\(palette)" }
    }

    @MainActor
    private static func applyVariant(_ model: ControlModel, _ v: Variant) {
        var s = Settings.empty
        s.enabled = true
        s.effect = v.effect
        s.palette = v.palette
        s.brightness = v.brightness
        s.speed = v.speed
        s.intensity = v.intensity
        s.fps = 60
        s.bandCount = 32
        s.sampleRate = 48000
        s.tccStatus = 0
        s.devices = [
            DeviceRuntime(
                name: "Desk", ip: "192.0.2.42", pixelCount: 237, rgbw: false,
                brightness: 1.0, enabled: true,
                segments: [
                    SegmentRuntime(start: 0, length: 119, reverse: false, mirror: false),
                    SegmentRuntime(start: 119, length: 118, reverse: true,  mirror: false),
                ]),
            DeviceRuntime(
                name: "Shelf", ip: "192.0.2.43", pixelCount: 144, rgbw: true,
                brightness: 0.7, enabled: true,
                segments: [
                    SegmentRuntime(start: 0, length: 144, reverse: false, mirror: false),
                ]),
        ]
        model.settings.settings = s
        model.settings.status = .running
        model.renderState.replace(
            enabled: s.enabled, effect: s.effect, paletteID: s.palette,
            brightness: s.brightness, speed: s.speed, intensity: s.intensity,
            brightnessReactive: s.brightnessReactive, brightnessAspect: s.brightnessAspect,
            speedReactive: s.speedReactive, speedAspect: s.speedAspect,
            intensityReactive: s.intensityReactive, intensityAspect: s.intensityAspect,
            devices: s.devices
        )
        model.live.frame = syntheticFrame()
    }

    @MainActor
    private static func renderAll(model: ControlModel, dir: String) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let variants: [Variant] = [
            .init(effect: "spectrum",   palette: "sunset"),
            .init(effect: "wavelength", palette: "ocean"),
            .init(effect: "beat_wave",  palette: "cyberpunk"),
            .init(effect: "ripple",     palette: "fire"),
        ]

        // Host BarView in an off-screen NSWindow so AppKit lays it out
        // and SwiftUI flushes its render tree. ImageRenderer alone
        // produces a blank canvas because BarView's @ObservedObject
        // tree needs a layout pass first.
        //
        // For PR shots we sit BarView on a vivid gradient backdrop with
        // `.ultraThinMaterial` so the README screenshot shows the same
        // translucency a user sees over their desktop wallpaper.
        // Pre-render the GitHub mock + a CIGaussianBlur'd copy per
        // palette. Compose them with the live BarView inside an
        // NSHostingController so Toggle/Slider rasterise correctly via
        // cacheDisplay (ImageRenderer alone draws them as yellow rects).
        let placeholder = NSImage(size: NSSize(width: 420, height: 800))
        let host = NSHostingController(rootView: ShowcaseFrame(
            model: model, palette: "sunset",
            sharpBackdrop: placeholder, blurredBackdrop: placeholder))
        let frame = NSRect(x: -2000, y: -2000, width: 420, height: 800)
        let win = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        win.contentViewController = host
        host.view.wantsLayer = true
        host.view.layer?.contentsScale = 2.0
        win.orderFront(nil)
        host.view.layoutSubtreeIfNeeded()

        func tick() {
            RunLoop.main.run(until: Date().addingTimeInterval(0.20))
        }

        var index = 0
        func next() {
            guard index < variants.count else {
                win.orderOut(nil)
                exit(0)
            }
            let v = variants[index]
            applyVariant(model, v)
            let backdrops = makeBackdrops(palette: v.palette)
                ?? (NSImage(size: NSSize(width: 420, height: 800)),
                    NSImage(size: NSSize(width: 420, height: 800)))
            host.rootView = ShowcaseFrame(
                model: model, palette: v.palette,
                sharpBackdrop: backdrops.0,
                blurredBackdrop: backdrops.1)
            tick()
            host.view.layoutSubtreeIfNeeded()
            tick()
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(v.name).png")
            if capture(view: host.view, to: url) {
                FileHandle.standardError.write(Data("wrote \(url.path)\n".utf8))
            } else {
                FileHandle.standardError.write(Data("FAILED \(url.path)\n".utf8))
            }
            index += 1
            DispatchQueue.main.async { next() }
        }
        DispatchQueue.main.async { next() }
    }

    @MainActor
    private static func capture(view: NSView, to url: URL) -> Bool {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do { try data.write(to: url); return true } catch { return false }
    }

    private static var window: NSWindow?

    @MainActor
    private static func openWindow(model: ControlModel) {
        NSApp.setActivationPolicy(.regular)
        let host = NSHostingController(rootView: BarView(model: model))
        host.view.frame = NSRect(x: 0, y: 0, width: 340, height: 720)
        let w = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 340, height: 720),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        w.title = "Pulsar"
        w.contentViewController = host
        w.isReleasedWhenClosed = false
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }

    private static func syntheticFrame(phase: Double = 0) -> LiveFrame {
        let n = 32
        var bins = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / Double(n - 1)
            let bass = exp(-pow((t - 0.05) / 0.18, 2))
            let mid  = 0.55 * exp(-pow((t - 0.42) / 0.22, 2))
            let air  = 0.35 * exp(-pow((t - 0.85) / 0.18, 2))
            let wob  = 0.08 * sin(phase * 1.7 + t * 9.0)
            bins[i] = Float(max(0.02, min(1.0, bass + mid + air + wob)))
        }
        let power: Float = 0.42 + Float(0.10 * sin(phase))
        return LiveFrame(spectrum: bins, power: power, bass: 0.6, treble: 0.4, beat: 0, lastFrameAgo: 0.016, aggregateAlive: true)
    }

    static func accent(_ palette: String) -> Color {
        switch palette {
        case "ocean":     return .init(red: 0.20, green: 0.55, blue: 0.95)
        case "cyberpunk": return .init(red: 0.75, green: 0.20, blue: 0.95)
        case "fire":      return .init(red: 0.95, green: 0.40, blue: 0.15)
        case "forest":    return .init(red: 0.30, green: 0.70, blue: 0.35)
        case "twilight":  return .init(red: 0.80, green: 0.35, blue: 0.65)
        default:          return .init(red: 0.95, green: 0.45, blue: 0.20)
        }
    }

    /// GitHub-ish mock page. Extracted so it can be pre-rendered to an
    /// NSImage via ImageRenderer, then blurred via CIGaussianBlur. We
    /// can't rely on SwiftUI's `.blur` inside `cacheDisplay(in:to:)`,
    /// and ImageRenderer alone can't render BarView (Toggle/Slider
    /// rasterise as placeholder rects). So: render the backdrop via
    /// ImageRenderer, the panel via cacheDisplay, composite as Images.
    struct FakeDesktop: View {
        let palette: String
        var body: some View {
            let accent = Showcase.accent(palette)
            ZStack(alignment: .topLeading) {
                Color(white: 0.05)

                Circle().fill(accent.opacity(0.55))
                    .frame(width: 380, height: 380)
                    .blur(radius: 90).offset(x: 240, y: -240)
                Circle().fill(accent.opacity(0.28))
                    .frame(width: 360, height: 360)
                    .blur(radius: 110).offset(x: -180, y: 380)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        Circle().fill(Color(red: 1.0, green: 0.36, blue: 0.30)).frame(width: 12, height: 12)
                        Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 12, height: 12)
                        Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.27)).frame(width: 12, height: 12)
                        Spacer()
                        Text("github.com / Steven17D / pulsar")
                            .font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.55))
                        Spacer().frame(width: 60)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)

                    HStack(spacing: 14) {
                        Image(systemName: "book.closed").font(.system(size: 16))
                            .foregroundStyle(Color.white.opacity(0.6))
                        Text("Steven17D").font(.system(size: 16)).foregroundStyle(accent)
                        Text("/").font(.system(size: 16)).foregroundStyle(Color.white.opacity(0.4))
                        Text("pulsar").font(.system(size: 16, weight: .bold)).foregroundStyle(accent)
                        Spacer()
                        Text("★").font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.7))
                        Text("2").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.white.opacity(0.7))
                    }
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)

                    HStack(spacing: 18) {
                        Group {
                            Text("Code"); Text("Issues"); Text("Pull requests")
                            Text("Actions"); Text("Projects")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.7))
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.bottom, 14)

                    Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
                        .padding(.bottom, 14)

                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(0..<6, id: \.self) { i in
                            HStack(spacing: 12) {
                                Circle().fill(Color.white.opacity(0.15))
                                    .frame(width: 22, height: 22)
                                VStack(alignment: .leading, spacing: 6) {
                                    Capsule().fill(Color.white.opacity(0.20))
                                        .frame(width: CGFloat(90 + (i * 47) % 90), height: 11)
                                    Capsule().fill(Color.white.opacity(0.10))
                                        .frame(width: CGFloat(140 + (i * 71) % 120), height: 9)
                                }
                                Spacer()
                                Text("2 years ago")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.white.opacity(0.4))
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    Spacer(minLength: 0)
                    HStack {
                        Spacer()
                        Text("Report repository")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.45))
                    }
                    .padding(16)
                }
            }
            .frame(width: 420, height: 800)
            .environment(\.colorScheme, .dark)
        }
    }

    @MainActor
    private static func makeBackdrops(palette: String) -> (NSImage, NSImage)? {
        let renderer = ImageRenderer(content: FakeDesktop(palette: palette))
        renderer.scale = 2.0
        guard let sharp = renderer.nsImage else { return nil }
        let blurred = applyBlur(sharp, radius: 30) ?? sharp
        return (sharp, blurred)
    }

    private static func applyBlur(_ image: NSImage, radius: Double) -> NSImage? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let cg = bitmap.cgImage else { return nil }
        // CIAffineClamp extends the image infinitely so CIGaussianBlur
        // doesn't fade out at the borders.
        let ci = CIImage(cgImage: cg).clampedToExtent()
        guard let blur = CIFilter(name: "CIGaussianBlur") else { return nil }
        blur.setValue(ci, forKey: kCIInputImageKey)
        blur.setValue(radius, forKey: kCIInputRadiusKey)
        guard let out = blur.outputImage else { return nil }
        let extent = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        let ctx = CIContext()
        guard let outCG = ctx.createCGImage(out, from: extent) else { return nil }
        return NSImage(cgImage: outCG, size: NSSize(width: extent.width / 2, height: extent.height / 2))
    }

    /// PR-shot wrapper. Pre-rendered backdrop images (sharp + blurred)
    /// avoid the offscreen-blur limitations of SwiftUI's `.blur` under
    /// `cacheDisplay(in:to:)`. The panel uses real `BarView` so Toggle
    /// / Slider controls render correctly via NSHostingController.
    struct ShowcaseFrame: View {
        let model: ControlModel
        let palette: String
        let sharpBackdrop: NSImage
        let blurredBackdrop: NSImage

        var body: some View {
            // Layout: 420×800 window. Panel is 340×720 at .padding(.top, 24)
            // and centred horizontally — so its top-left lives at
            // (40, 24). The blurred backdrop is the same NSImage as the
            // sharp one but offset (-40, -24) inside the panel clip so
            // its content lines up exactly with the sharp copy outside
            // the panel — the panel reads as a literal frosted window
            // over the same page.
            ZStack(alignment: .top) {
                Image(nsImage: sharpBackdrop)
                    .resizable()
                    .frame(width: 420, height: 800)

                ZStack {
                    Image(nsImage: blurredBackdrop)
                        .resizable()
                        .frame(width: 420, height: 800)
                        .offset(x: -40, y: -24)
                        .frame(width: 340, height: 720, alignment: .topLeading)
                        .clipped()
                        .overlay(Color.black.opacity(0.45))

                    BarView(model: model)
                        .frame(width: 340, height: 720)
                }
                .frame(width: 340, height: 720)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.55), radius: 24, x: 0, y: 8)
                .padding(.top, 24)
            }
            .frame(width: 420, height: 800)
            .environment(\.colorScheme, .dark)
        }
    }

    @MainActor
    private static func startSpectrumTimer(_ model: ControlModel) {
        var phase: Double = 0
        Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            phase += 0.08
            Task { @MainActor in
                model.live.frame = syntheticFrame(phase: phase)
            }
        }
    }
}
