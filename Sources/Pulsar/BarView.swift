import AppKit
import SwiftUI

private let panelWidth: CGFloat = 340
private let hPad: CGFloat = 12
private let sectionGap: CGFloat = 10
private let rowGap: CGFloat = 6
private let cardCorner: CGFloat = 8
private let snapSpring = Animation.spring(response: 0.3, dampingFraction: 0.85)

/// Light haptic for discrete control changes (palette pick, etc.).
private func tapHaptic() {
    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
}

struct BarView: View {
    let model: ControlModel
    @ObservedObject var settings: SettingsStore

    init(model: ControlModel) {
        self.model = model
        self.settings = model.settings
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: sectionGap) {
                    HeaderRow(model: model)
                    AddDevicePanel(model: model)
                    LiveSection(model: model)
                    MasterSection(model: model)
                    EffectSection(model: model)
                    PaletteSection(model: model)
                    SlidersSection(model: model)
                    if !settings.settings.devices.isEmpty {
                        DevicesSection(model: model)
                    }
                    StartupSection(model: model)
                    Footer(model: model)
                }
                .padding(.horizontal, hPad)
                .padding(.vertical, hPad)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: panelWidth, height: 620)
        .background(.regularMaterial)
    }
}

// MARK: - Header

private struct HeaderRow: View {
    let model: ControlModel
    @ObservedObject var settings: SettingsStore

    init(model: ControlModel) {
        self.model = model
        self.settings = model.settings
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pulsar").font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            StatusPill(model: model)
        }
    }

    private var subtitle: String {
        let s = settings.settings
        return "\(Int(s.sampleRate)) Hz · \(s.fps) fps · \(s.bandCount) bands"
    }
}

// MARK: - Section scaffolding

/// Native-feeling section header. Subheadline weight, secondary colour,
/// no all-caps. Pairs with `SectionCard` for grouped content.
private struct SectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
    }
}

/// Inset card surface for grouped controls. Mimics GroupBox material
/// but lets us own padding so vertical rhythm stays on the 8pt grid.
private struct SectionCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: rowGap) {
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}

private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title)
            SectionCard { content }
        }
    }
}

// MARK: - Live

private struct LiveSection: View {
    let model: ControlModel
    var body: some View {
        Section(title: "Live") {
            SpectrumStripView(model: model)
                .frame(height: 56)
            HStack(spacing: 10) {
                Text("Power")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
                PowerBarView(model: model)
                PowerNumber(model: model)
            }
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
        SpectrumStrip(values: live.frame.spectrum,
                      palette: Palette.by(id: settings.settings.palette))
            .animation(nil, value: live.frame.spectrum)
    }
}

private struct SpectrumStrip: View {
    let values: [Float]
    let palette: Palette

    var body: some View {
        GeometryReader { geo in
            let mainH = geo.size.height * 0.78
            let reflectH = geo.size.height - mainH - 1
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0..<max(1, values.count), id: \.self) { i in
                        let v = i < values.count ? values[i] : 0
                        let h = max(1.5, mainH * CGFloat(max(0, min(1, v))))
                        bar(for: i, height: h)
                    }
                }
                .frame(height: mainH, alignment: .bottom)

                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)

                HStack(alignment: .top, spacing: 2) {
                    ForEach(0..<max(1, values.count), id: \.self) { i in
                        let v = i < values.count ? values[i] : 0
                        let h = max(1, reflectH * CGFloat(max(0, min(1, v))))
                        bar(for: i, height: h)
                            .opacity(0.3)
                            .scaleEffect(y: -1, anchor: .center)
                    }
                }
                .frame(height: reflectH, alignment: .top)
                .mask(
                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            }
        }
    }

    @ViewBuilder private func bar(for i: Int, height: CGFloat) -> some View {
        let f = values.count <= 1 ? Float(0) : Float(i) / Float(values.count - 1)
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

private struct PowerBarView: View {
    @ObservedObject var live: LiveStore
    init(model: ControlModel) { self.live = model.live }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(2, CGFloat(min(1, live.frame.power * 4)) * geo.size.width))
            }
        }
        .frame(height: 6)
        .animation(nil, value: live.frame.power)
    }
}

private struct PowerNumber: View {
    @ObservedObject var live: LiveStore
    init(model: ControlModel) { self.live = model.live }
    var body: some View {
        Text(String(format: "%0.2f", live.frame.power))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 36, alignment: .trailing)
            .animation(nil, value: live.frame.power)
    }
}

// MARK: - Master

private struct MasterSection: View {
    let model: ControlModel
    @ObservedObject var settings: SettingsStore
    init(model: ControlModel) {
        self.model = model
        self.settings = model.settings
    }

    var body: some View {
        Section(title: "Master") {
            LabeledContent {
                Toggle("", isOn: Binding(
                    get: { settings.settings.enabled },
                    set: { model.setMasterEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(settings.status != .running)
            } label: {
                Text(settings.settings.enabled ? "On" : "Off")
                    .font(.body)
            }
        }
    }
}

// MARK: - Effect

private struct EffectSection: View {
    let model: ControlModel
    @ObservedObject var settings: SettingsStore
    init(model: ControlModel) {
        self.model = model
        self.settings = model.settings
    }

    var body: some View {
        Section(title: "Effect") {
            HStack(spacing: 8) {
                paletteSwatchPreview
                Picker("", selection: Binding(
                    get: { settings.settings.effect },
                    set: { model.setMasterEffect($0) }
                )) {
                    ForEach(settings.settings.availableEffects, id: \.self) { e in
                        Text(Mapper.pretty(e)).tag(e)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(settings.status != .running)
            }
        }
    }

    private var paletteSwatchPreview: some View {
        let palette = Palette.by(id: settings.settings.palette)
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(LinearGradient(
                gradient: Gradient(stops: palette.stops.map {
                    Gradient.Stop(
                        color: Color(red: Double($0.r), green: Double($0.g), blue: Double($0.b)),
                        location: CGFloat($0.pos)
                    )
                }),
                startPoint: .leading, endPoint: .trailing
            ))
            .frame(width: 22, height: 22)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
            )
    }
}

// MARK: - Palette

private struct PaletteSection: View {
    let model: ControlModel
    @ObservedObject var settings: SettingsStore
    init(model: ControlModel) {
        self.model = model
        self.settings = model.settings
    }

    var body: some View {
        Section(title: "Palette") {
            HStack(alignment: .top, spacing: 8) {
                ForEach(settings.settings.availablePalettes, id: \.self) { id in
                    PaletteSwatch(
                        palette: Palette.by(id: id),
                        selected: settings.settings.palette == id
                    ) {
                        tapHaptic()
                        withAnimation(snapSpring) { model.setPalette(id) }
                    }
                }
            }
        }
    }
}

private struct PaletteSwatch: View {
    let palette: Palette
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(
                        gradient: Gradient(stops: palette.stops.map {
                            Gradient.Stop(
                                color: Color(red: Double($0.r), green: Double($0.g), blue: Double($0.b)),
                                location: CGFloat($0.pos)
                            )
                        }),
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 44, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0)
                            .padding(-3)
                    )
                    .shadow(color: selected ? Color.accentColor.opacity(0.35) : .clear,
                            radius: selected ? 5 : 0)
                Text(palette.name)
                    .font(.caption2)
                    .foregroundStyle(selected ? Color.primary : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sliders

private struct SlidersSection: View {
    let model: ControlModel
    @ObservedObject var settings: SettingsStore
    init(model: ControlModel) {
        self.model = model
        self.settings = model.settings
    }

    var body: some View {
        Section(title: "Mix") {
            DetentSliderRow(
                title: "Speed",
                value: Double(settings.settings.speed),
                onChange: { model.setSpeed(Float($0)) },
                enabled: settings.status == .running
            )
            DetentSliderRow(
                title: "Intensity",
                value: Double(settings.settings.intensity),
                onChange: { model.setIntensity(Float($0)) },
                enabled: settings.status == .running
            )
        }
    }
}

/// Slider row with a soft detent at 1.0×, a tick mark on the track to
/// signal the default, and a "Default" hint that appears at the detent.
private struct DetentSliderRow: View {
    let title: String
    let value: Double
    let onChange: (Double) -> Void
    let enabled: Bool

    private var isDefault: Bool { abs(value - 1.0) < 0.001 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.body)
                Spacer()
                Text(String(format: "%0.2fx", value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .onTapGesture {
                        tapHaptic()
                        onChange(1.0)
                    }
            }
            ZStack(alignment: .leading) {
                Slider(value: Binding(
                    get: { value },
                    set: { v in
                        let snapped = abs(v - 1.0) < 0.04 ? 1.0 : v
                        onChange(snapped)
                    }
                ), in: 0.1...2.0)
                .disabled(!enabled)

                GeometryReader { geo in
                    let frac = (1.0 - 0.1) / (2.0 - 0.1)
                    Rectangle()
                        .fill(Color.primary.opacity(0.25))
                        .frame(width: 1, height: 6)
                        .offset(x: geo.size.width * CGFloat(frac), y: geo.size.height / 2 - 3)
                }
                .allowsHitTesting(false)
            }
            .frame(height: 22)
            Text(isDefault ? "Default" : " ")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

// MARK: - Devices

private struct DevicesSection: View {
    let model: ControlModel
    @ObservedObject var settings: SettingsStore
    init(model: ControlModel) {
        self.model = model
        self.settings = model.settings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Devices")
            VStack(spacing: 6) {
                ForEach(Array(settings.settings.devices.enumerated()), id: \.element.id) { (idx, d) in
                    DeviceDisclosureRow(model: model, index: idx, dev: d)
                }
            }
        }
    }
}

private struct DeviceDisclosureRow: View {
    let model: ControlModel
    let index: Int
    let dev: DeviceRuntime
    @ObservedObject var settings: SettingsStore
    @State private var expanded: Bool = false

    init(model: ControlModel, index: Int, dev: DeviceRuntime) {
        self.model = model
        self.index = index
        self.dev = dev
        self.settings = model.settings
    }

    var body: some View {
        let device = currentDevice
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(snapSpring) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Circle()
                        .fill(device.enabled ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(device.name).font(.body)
                        Text(detailLine(device))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { currentDevice.enabled },
                        set: { model.setDeviceEnabled(index: index, $0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(settings.status != .running)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                DeviceDetail(model: model, index: index, dev: device)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    private var currentDevice: DeviceRuntime {
        settings.settings.devices[safe: index] ?? dev
    }

    private func detailLine(_ device: DeviceRuntime) -> String {
        "\(device.ip) · \(device.pixelCount) \(device.rgbw ? "RGBW" : "RGB") · \(device.segments.count) seg"
    }
}

private struct DeviceDetail: View {
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
        let device = currentDevice
        VStack(alignment: .leading, spacing: rowGap) {
            Divider()

            Picker("", selection: Binding(
                get: { currentDevice.rgbw },
                set: { model.setDeviceRGBW(index: index, $0) }
            )) {
                Text("RGB").tag(false)
                Text("RGBW").tag(true)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)

            LabeledContent {
                Text(String(format: "%0.0f%%", device.brightness * 100))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } label: {
                Text("Brightness")
            }
            Slider(value: Binding(
                get: { Double(currentDevice.brightness) },
                set: { model.setDeviceBrightness(index: index, Float($0)) }
            ), in: 0...1)
            .disabled(settings.status != .running)

            HStack {
                SectionHeader("Segments")
                Spacer()
                Button {
                    Task { await model.refreshSegmentsFromWLED(deviceIndex: index) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }

            ForEach(Array(device.segments.enumerated()), id: \.element.id) { (segIdx, seg) in
                SegmentRow(model: model, deviceIndex: index, segmentIndex: segIdx, seg: seg)
            }

            HStack {
                Button {
                    if let url = URL(string: "http://\(device.ip)/") { NSWorkspace.shared.open(url) }
                } label: {
                    Label("Open Web UI…", systemImage: "globe")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                Spacer()
                Button(role: .destructive) {
                    model.removeDevice(index: index)
                } label: {
                    Label("Remove", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
            .padding(.top, 4)
        }
    }

    private var currentDevice: DeviceRuntime {
        settings.settings.devices[safe: index] ?? dev
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
        let segment = currentSegment
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Seg \(segmentIndex + 1)").font(.caption.weight(.medium))
                Text("[\(segment.start) … \(segment.start + segment.length - 1)] · \(segment.length)px")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack(spacing: 12) {
                Toggle(isOn: Binding(
                    get: { currentSegment.reverse },
                    set: { model.setSegmentReverse(deviceIndex: deviceIndex, segmentIndex: segmentIndex, $0) }
                )) {
                    Text("Reverse").font(.caption)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(settings.status != .running)

                Toggle(isOn: Binding(
                    get: { currentSegment.mirror },
                    set: { model.setSegmentMirror(deviceIndex: deviceIndex, segmentIndex: segmentIndex, $0) }
                )) {
                    Text("Mirror").font(.caption)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(settings.status != .running)
            }
        }
        .padding(.vertical, 2)
    }

    private var currentSegment: SegmentRuntime {
        settings.settings.devices[safe: deviceIndex]?.segments[safe: segmentIndex] ?? seg
    }
}

// MARK: - Startup

private struct StartupSection: View {
    let model: ControlModel
    @ObservedObject var ctrl: ControlModel

    init(model: ControlModel) {
        self.model = model
        self.ctrl = model
    }

    var body: some View {
        Section(title: "Startup") {
            HStack {
                Text("Start at login")
                Spacer()
                Toggle("", isOn: Binding(
                    get: { ctrl.startAtLogin },
                    set: { ctrl.setStartAtLogin($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            if let notice = ctrl.startupNotice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Status pill

private struct StatusPill: View {
    @ObservedObject var live: LiveStore
    @ObservedObject var settings: SettingsStore

    init(model: ControlModel) {
        self.live = model.live
        self.settings = model.settings
    }

    var body: some View {
        let kind = statusKind
        HStack(spacing: 6) {
            Circle().fill(kind.dot).frame(width: 6, height: 6)
            Text(kind.label).font(.caption.weight(.medium))
                .foregroundStyle(kind.dot)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(kind.dot.opacity(0.15)))
    }

    private enum Kind {
        case running, silent, paused, warming, problem
        var label: String {
            switch self {
            case .running: return "Running"
            case .silent:  return "Silent"
            case .paused:  return "Paused"
            case .warming: return "Starting…"
            case .problem: return "Audio Lost"
            }
        }
        var dot: Color {
            switch self {
            case .running: return .green
            case .silent:  return .yellow
            case .paused:  return .secondary
            case .warming: return .secondary
            case .problem: return .red
            }
        }
    }

    private var statusKind: Kind {
        switch settings.status {
        case .starting:      return .warming
        case .stopped:       return .problem
        case .tccDenied:     return .problem
        case .aggregateLost: return .problem
        case .running:
            let f = live.frame
            if !f.aggregateAlive { return .problem }
            if !settings.settings.enabled { return .paused }
            if f.power < 0.001 { return .silent }
            return .running
        }
    }
}

// MARK: - Footer

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
            ActionRow(icon: "info.circle", title: "About Pulsar") {
                NSWorkspace.shared.open(URL(string: "https://github.com/Steven17D/pulsar")!)
            }
            Divider().padding(.vertical, 2)
            ActionRow(icon: "power", title: "Quit", shortcut: "Q") {
                model.quit()
            }
        }
        .padding(.vertical, 4)
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
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.caption)
                    .frame(width: 14)
                    .foregroundStyle(.secondary)
                Text(title).font(.callout)
                Spacer()
                if let s = shortcut {
                    Text("⌘\(s)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, hPad)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovered ? Color.accentColor.opacity(0.18) : Color.clear)
                    .padding(.horizontal, 6)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - Add Device

private struct AddDevicePanel: View {
    let model: ControlModel

    @ObservedObject var discovery: WLEDDiscovery
    @ObservedObject var settings: SettingsStore

    @State private var elapsed: Double = 0

    init(model: ControlModel) {
        self.model = model
        self.discovery = model.discovery
        self.settings = model.settings
    }

    var body: some View {
        Section(title: "Discovery") {
            discoveredList
            .onAppear {
                discovery.start()
                elapsed = 0
            }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                elapsed += 1
            }
        }
    }

    private var addableDiscoveries: [DiscoveredWLED] {
        discovery.discovered.filter { d in
            !settings.settings.devices.contains(where: { $0.ip == d.ip })
        }
    }

    @ViewBuilder private var discoveredList: some View {
        VStack(spacing: 6) {
            if addableDiscoveries.isEmpty {
                waitingRow
            } else {
                ForEach(addableDiscoveries) { d in
                    discoveredRow(d)
                }
            }
        }
    }

    private var waitingRow: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 1) {
                Text(elapsed > 5 ? "Waiting for WLED" : "Scanning")
                    .font(.body)
                Text(waitingDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private var waitingDetail: String {
        if discovery.discovered.isEmpty {
            return "Turn on a WLED device nearby"
        }
        return "Discovered devices are already added"
    }

    private func discoveredRow(_ d: DiscoveredWLED) -> some View {
        Button { add(d) } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(d.serviceName).font(.body)
                    Text(detailLine(d))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func detailLine(_ d: DiscoveredWLED) -> String {
        var parts: [String] = [d.ip]
        if let n = d.pixelCount { parts.append("\(n) px") }
        if let w = d.rgbw { parts.append(w ? "RGBW" : "RGB") }
        if let s = d.segmentCount { parts.append("\(s) seg") }
        return parts.joined(separator: " · ")
    }

    private func add(_ d: DiscoveredWLED) {
        model.addDevice(
            name: d.serviceName,
            ip: d.ip,
            pixelCount: d.pixelCount ?? 0 > 0 ? (d.pixelCount ?? 1) : 1,
            rgbw: d.rgbw ?? false
        )
    }
}
