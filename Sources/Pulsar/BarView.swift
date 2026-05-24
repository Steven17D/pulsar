import AppKit
import SwiftUI

private enum Tab: String, CaseIterable, Hashable {
    case overview, office, tv

    var label: String {
        switch self {
        case .overview: return "Overview"
        case .office:   return "Office"
        case .tv:       return "TV"
        }
    }
}

struct BarView: View {
    let model: ControlModel
    @ObservedObject var settings: SettingsStore
    @State private var tab: Tab = .overview

    init(model: ControlModel) {
        self.model = model
        self.settings = model.settings
    }

    var body: some View {
        VStack(spacing: 0) {
            tabsHeader

            VStack(alignment: .leading, spacing: 14) {
                switch tab {
                case .overview:
                    OverviewSection(model: model)
                case .office:
                    if let d = device(index: 0) { DeviceSection(model: model, index: 0, dev: d) }
                case .tv:
                    if let d = device(index: 1) { DeviceSection(model: model, index: 1, dev: d) }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
            Footer(model: model)
        }
        .frame(width: 340)
    }

    private var tabsHeader: some View {
        let tabs = tabsAvailable
        return HStack(spacing: 6) {
            ForEach(tabs, id: \.self) { t in
                Button { tab = t } label: {
                    Text(t.label)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(tab == t ? Color.accentColor.opacity(0.85) : Color.gray.opacity(0.15))
                        )
                        .foregroundColor(tab == t ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var tabsAvailable: [Tab] {
        var t: [Tab] = [.overview]
        let n = settings.settings.devices.count
        if n > 0 { t.append(.office) }
        if n > 1 { t.append(.tv) }
        return t
    }

    private func device(index: Int) -> DeviceRuntime? {
        let devs = settings.settings.devices
        return devs.indices.contains(index) ? devs[index] : nil
    }
}

private struct OverviewSection: View {
    let model: ControlModel
    @ObservedObject var settings: SettingsStore

    init(model: ControlModel) {
        self.model = model
        self.settings = model.settings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pulsar").font(.system(size: 14, weight: .semibold))
                    Text(updatedLine)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                StatusPill(model: model)
            }

            SectionLabel("Live")
            SpectrumStripView(model: model).frame(height: 48)
            HStack(spacing: 8) {
                Text("Power").font(.system(size: 11)).foregroundColor(.secondary).frame(width: 50, alignment: .leading)
                PowerBarView(live: model.live)
                PowerNumber(live: model.live)
            }

            SectionLabel("Master")
            HStack {
                Text(settings.settings.enabled ? "On" : "Off").font(.system(size: 12))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { settings.settings.enabled },
                    set: { model.setMasterEnabled($0) }
                ))
                .labelsHidden().toggleStyle(.switch)
                .disabled(settings.status != .running)
            }

            SectionLabel("Effect")
            Picker("", selection: Binding(
                get: { settings.settings.effect },
                set: { model.setMasterEffect($0) }
            )) {
                ForEach(settings.settings.availableEffects, id: \.self) { e in
                    Text(Mapper.pretty(e)).tag(e)
                }
            }
            .labelsHidden().pickerStyle(.menu)
            .disabled(settings.status != .running)

            SectionLabel("Palette")
            HStack(spacing: 6) {
                ForEach(settings.settings.availablePalettes, id: \.self) { id in
                    PaletteSwatch(
                        palette: Palette.by(id: id),
                        selected: settings.settings.palette == id
                    ) { model.setPalette(id) }
                }
            }

            SectionLabel("Speed")
            HStack(spacing: 8) {
                Slider(value: Binding(
                    get: { Double(settings.settings.speed) },
                    set: { v in
                        // Soft detent at 1.0x — within ±0.04 the slider
                        // snaps to exactly the default so it's easy to
                        // dial back to a known-good state without
                        // overshooting.
                        let snapped = abs(v - 1.0) < 0.04 ? 1.0 : v
                        model.setSpeed(Float(snapped))
                    }
                ), in: 0.1...2.0)
                .disabled(settings.status != .running)
                Text(String(format: "%0.2fx", settings.settings.speed))
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 44, alignment: .trailing)
                    .onTapGesture { model.setSpeed(1.0) }
            }

            SectionLabel("Intensity")
            HStack(spacing: 8) {
                Slider(value: Binding(
                    get: { Double(settings.settings.intensity) },
                    set: { v in
                        let snapped = abs(v - 1.0) < 0.04 ? 1.0 : v
                        model.setIntensity(Float(snapped))
                    }
                ), in: 0.1...2.0)
                .disabled(settings.status != .running)
                Text(String(format: "%0.2fx", settings.settings.intensity))
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 44, alignment: .trailing)
                    .onTapGesture { model.setIntensity(1.0) }
            }

            if !settings.settings.devices.isEmpty {
                SectionLabel("Devices")
                ForEach(Array(settings.settings.devices.enumerated()), id: \.element.id) { (idx, d) in
                    DeviceRow(model: model, index: idx, dev: d)
                }
            }
        }
    }

    private var updatedLine: String {
        let s = settings.settings
        return "\(Int(s.sampleRate)) Hz · \(s.fps) fps · \(s.bandCount) bands"
    }
}

private struct DeviceRow: View {
    let model: ControlModel
    let index: Int
    let dev: DeviceRuntime
    @ObservedObject var settings: SettingsStore

    init(model: ControlModel, index: Int, dev: DeviceRuntime) {
        self.model = model
        self.index = index
        self.dev = dev
        self.settings = model.settings
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(dev.enabled ? Color.green : Color.gray.opacity(0.4)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(dev.name).font(.system(size: 12, weight: .medium))
                Text("\(dev.ip) · \(dev.pixelCount) \(dev.rgbw ? "RGBW" : "RGB") · \(dev.segments.count) seg")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { dev.enabled },
                set: { model.setDeviceEnabled(index: index, $0) }
            ))
            .labelsHidden().toggleStyle(.switch)
            .disabled(settings.status != .running)
        }
    }
}

private struct DeviceSection: View {
    let model: ControlModel
    let index: Int
    let dev: DeviceRuntime
    @ObservedObject var settings: SettingsStore

    init(model: ControlModel, index: Int, dev: DeviceRuntime) {
        self.model = model
        self.index = index
        self.dev = dev
        self.settings = model.settings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dev.name).font(.system(size: 14, weight: .semibold))
                    Text("\(dev.ip) · \(dev.pixelCount) \(dev.rgbw ? "RGBW" : "RGB") · \(dev.segments.count) seg")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                StatusPill(model: model)
            }

            SectionLabel("Enabled")
            HStack {
                Text(dev.enabled ? "On" : "Off").font(.system(size: 12))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { dev.enabled },
                    set: { model.setDeviceEnabled(index: index, $0) }
                ))
                .labelsHidden().toggleStyle(.switch)
                .disabled(settings.status != .running)
            }

            HStack {
                SectionLabel("Segments")
                Spacer()
                Button {
                    Task { await model.refreshSegmentsFromWLED(deviceIndex: index) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain).foregroundColor(.accentColor)
            }
            ForEach(Array(dev.segments.enumerated()), id: \.element.id) { (segIdx, seg) in
                SegmentRow(model: model, deviceIndex: index, segmentIndex: segIdx, seg: seg)
            }

            SectionLabel("Brightness")
            HStack(spacing: 8) {
                Slider(value: Binding(
                    get: { Double(dev.brightness) },
                    set: { model.setDeviceBrightness(index: index, Float($0)) }
                ), in: 0...1)
                .disabled(settings.status != .running)
                Text(String(format: "%0.0f%%", dev.brightness * 100))
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 42, alignment: .trailing)
            }

            Button {
                if let url = URL(string: "http://\(dev.ip)/") { NSWorkspace.shared.open(url) }
            } label: {
                Label("Open Web UI…", systemImage: "globe")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
        }
    }
}

private struct PaletteSwatch: View {
    let palette: Palette
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottom) {
                LinearGradient(
                    gradient: Gradient(stops: palette.stops.map {
                        Gradient.Stop(color: Color(red: Double($0.r), green: Double($0.g), blue: Double($0.b)), location: CGFloat($0.pos))
                    }),
                    startPoint: .leading, endPoint: .trailing
                )
                Text(palette.name)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.6), radius: 1)
                    .padding(.bottom, 2)
            }
            .frame(height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SegmentRow: View {
    let model: ControlModel
    let deviceIndex: Int
    let segmentIndex: Int
    let seg: SegmentRuntime
    @ObservedObject var settings: SettingsStore

    init(model: ControlModel, deviceIndex: Int, segmentIndex: Int, seg: SegmentRuntime) {
        self.model = model
        self.deviceIndex = deviceIndex
        self.segmentIndex = segmentIndex
        self.seg = seg
        self.settings = model.settings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Seg \(segmentIndex + 1)")
                    .font(.system(size: 12, weight: .medium))
                Text("[\(seg.start) … \(seg.start + seg.length - 1)] · \(seg.length)px")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
            }
            HStack(spacing: 12) {
                Toggle(isOn: Binding(
                    get: { seg.reverse },
                    set: { model.setSegmentReverse(deviceIndex: deviceIndex, segmentIndex: segmentIndex, $0) }
                )) {
                    Text("Reverse").font(.system(size: 11))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(settings.status != .running)

                Toggle(isOn: Binding(
                    get: { seg.mirror },
                    set: { model.setSegmentMirror(deviceIndex: deviceIndex, segmentIndex: segmentIndex, $0) }
                )) {
                    Text("Mirror").font(.system(size: 11))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(settings.status != .running)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct StatusPill: View {
    @ObservedObject var live: LiveStore
    @ObservedObject var settings: SettingsStore

    init(model: ControlModel) {
        self.live = model.live
        self.settings = model.settings
    }

    var body: some View {
        let txt = statusText
        return HStack(spacing: 6) {
            Circle().fill(color(for: txt)).frame(width: 8, height: 8)
            Text(txt).font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.18)))
    }

    private var statusText: String {
        switch settings.status {
        case .starting:      return "Starting…"
        case .stopped:       return "Stopped"
        case .tccDenied:     return "TCC Denied"
        case .aggregateLost: return "Audio Lost"
        case .running:
            let f = live.frame
            if !f.aggregateAlive { return "Audio Lost" }
            if !settings.settings.enabled { return "Paused" }
            if f.power < 0.001 { return "Silent" }
            return "Running"
        }
    }

    private func color(for t: String) -> Color {
        switch t {
        case "Running":   return .green
        case "Silent":    return .yellow
        case "Paused":    return .gray
        case "Starting…": return .gray
        default:          return .red
        }
    }
}

private struct SpectrumStripView: View {
    @ObservedObject var live: LiveStore
    @ObservedObject var settings: SettingsStore

    init(model: ControlModel) {
        self.live = model.live
        self.settings = model.settings
    }

    var body: some View {
        SpectrumStrip(values: live.frame.spectrum, palette: Palette.by(id: settings.settings.palette))
            // Disable SwiftUI's implicit animations between frames — at
            // 60 Hz they queue and stutter. We want each frame to land
            // verbatim, not transition smoothly toward the next.
            .animation(nil, value: live.frame.spectrum)
    }
}

private struct PowerBarView: View {
    @ObservedObject var live: LiveStore
    var body: some View {
        PowerBar(value: max(0, min(1, live.frame.power * 4)))
            .animation(nil, value: live.frame.power)
    }
}

private struct PowerNumber: View {
    @ObservedObject var live: LiveStore
    var body: some View {
        Text(String(format: "%0.2f", live.frame.power))
            .font(.system(size: 11, design: .monospaced))
            .frame(width: 42, alignment: .trailing)
            .animation(nil, value: live.frame.power)
    }
}

private struct Footer: View {
    let model: ControlModel
    var body: some View {
        VStack(spacing: 0) {
            ActionRow(icon: "square.and.pencil", title: "Edit Config…") {
                let p = NSString(string: "~/.config/pulsar/config.json").expandingTildeInPath
                NSWorkspace.shared.open(URL(fileURLWithPath: p))
            }
            ActionRow(icon: "doc.text.magnifyingglass", title: "Show Log…") {
                let p = NSString(string: "~/.cache/pulsar.log").expandingTildeInPath
                NSWorkspace.shared.open(URL(fileURLWithPath: p))
            }
            ActionRow(icon: "arrow.clockwise", title: "Reload Config", shortcut: "R") {
                model.reloadFromDisk()
            }
            Divider()
            ActionRow(icon: "info.circle", title: "About Pulsar") {
                NSWorkspace.shared.open(URL(string: "https://kno.wled.ge/")!)
            }
            ActionRow(icon: "power", title: "Quit", shortcut: "Q") {
                model.quit()
            }
        }
    }
}

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .tracking(0.5)
    }
}

private struct ActionRow: View {
    let icon: String
    let title: String
    var shortcut: String? = nil
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).frame(width: 16)
                Text(title).font(.system(size: 13))
                Spacer()
                if let s = shortcut {
                    Text("⌘\(s)").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(hovered ? Color.accentColor.opacity(0.18) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct PowerBar: View {
    let value: Float
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.18))
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [.green, .yellow, .red], startPoint: .leading, endPoint: .trailing))
                    .frame(width: CGFloat(max(0.001, value)) * geo.size.width)
            }
        }
        .frame(height: 8)
    }
}

private struct SpectrumStrip: View {
    let values: [Float]
    let palette: Palette

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Faint baseline so the visualiser is visibly grounded
                // even when nothing is playing.
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)
                    .frame(maxWidth: .infinity, alignment: .bottom)

                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0..<max(1, values.count), id: \.self) { i in
                        let v = i < values.count ? values[i] : 0
                        // No more 2% floor — bars collapse to zero when
                        // silent so the baseline reads as the only line.
                        let clamped = CGFloat(max(0, min(1, v)))
                        bar(for: i, height: max(1.5, geo.size.height * clamped))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    @ViewBuilder private func bar(for i: Int, height: CGFloat) -> some View {
        let f = values.count <= 1 ? Float(0) : Float(i) / Float(values.count - 1)
        // Skip the deepest palette stops — they're near-black and read
        // as invisible on the dark panel background. Map [0,1] into the
        // brighter half-and-a-bit of the palette, then floor every
        // channel so even the "darkest" colour has visible saturation.
        let visualF = 0.28 + 0.72 * f
        let raw = palette.sample(at: visualF)
        let r = Double(min(1.0, raw.r * 1.15 + 0.06))
        let g = Double(min(1.0, raw.g * 1.15 + 0.06))
        let b = Double(min(1.0, raw.b * 1.15 + 0.06))
        let base = Color(red: r, green: g, blue: b)
        RoundedRectangle(cornerRadius: 1.5)
            .fill(LinearGradient(
                colors: [base.opacity(0.75), base],
                startPoint: .top, endPoint: .bottom
            ))
            .frame(height: height)
    }
}
