import AppKit
import SwiftUI

private let panelWidth: CGFloat = 340
private let hPad: CGFloat = 16
private let sectionGap: CGFloat = 10
private let rowGap: CGFloat = 6
private let snapSpring = Animation.spring(response: 0.3, dampingFraction: 0.85)

/// Light haptic for discrete control changes (palette pick, etc.).
private func tapHaptic() {
    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
}

struct BarView: View {
    let model: ControlModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var discovery: WLEDDiscovery

    init(model: ControlModel) {
        self.model = model
        self.settings = model.settings
        self.discovery = model.discovery
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderRow(model: model)
                .padding(.horizontal, hPad)
                .padding(.top, 10)
                .padding(.bottom, 6)
            HairlineDivider()
            if hasAddableDiscoveries {
                AddDevicePanel(model: model)
                    .padding(.horizontal, hPad)
                    .padding(.vertical, 6)
                HairlineDivider()
            }
            LiveSection(model: model)
                .padding(.horizontal, hPad)
                .padding(.vertical, 6)
            HairlineDivider()
            LookMixSection(model: model)
                .padding(.horizontal, hPad)
                .padding(.vertical, 10)
            HairlineDivider()
            if !settings.settings.devices.isEmpty {
                DevicesSection(model: model)
                    .padding(.horizontal, hPad)
                    .padding(.vertical, 6)
                HairlineDivider()
            }
            StartupSection(model: model)
                .padding(.horizontal, hPad)
                .padding(.vertical, 4)
            HairlineDivider()
            Footer(model: model)
                .padding(.vertical, 2)
        }
        .frame(width: panelWidth, alignment: .leading)
    }

    private var hasAddableDiscoveries: Bool {
        discovery.discovered.contains { d in
            !settings.settings.devices.contains(where: { $0.ip == d.ip })
        }
    }
}

// MARK: - Header

private struct HeaderRow: View {
    let model: ControlModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var discovery: WLEDDiscovery

    init(model: ControlModel) {
        self.model = model
        self.settings = model.settings
        self.discovery = model.discovery
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Text("Pulsar")
                    .font(.title3.weight(.bold))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { settings.settings.enabled },
                    set: { model.setMasterEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.regular)
                .disabled(settings.status != .running)
            }
            HStack(spacing: 6) {
                StatusPill(model: model)
                DiscoveryPill(discovery: discovery, settings: settings)
                Spacer()
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
    }

    private var subtitle: String {
        let s = settings.settings
        return "\(Int(s.sampleRate)) Hz · \(s.fps) fps · \(s.bandCount) bands"
    }
}

// MARK: - Section scaffolding

/// Bold primary-coloured section label, matching the macOS Control Center
/// "Known Network" / "Other Networks" tier of header.
private struct SectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
    }
}

private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title)
            content
        }
    }
}

private struct HairlineDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(height: 0.5)
            .padding(.horizontal, hPad)
    }
}

/// Circular accent-tinted glyph badge used as a row leading icon — the
/// macOS Control Center "blue circle with white SF Symbol" treatment.
private struct IconBadge: View {
    let symbol: String
    var tint: Color = .accentColor
    var size: CGFloat = 22
    var body: some View {
        ZStack {
            Circle().fill(tint)
            Image(systemName: symbol)
                .font(.system(size: size * 0.50, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
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

// MARK: - Look + Mix

private struct LookMixSection: View {
    let model: ControlModel
    @ObservedObject var settings: SettingsStore
    init(model: ControlModel) {
        self.model = model
        self.settings = model.settings
    }

    var body: some View {
        Section(title: "Look") {
            HStack(spacing: 8) {
                Picker("", selection: Binding(
                    get: { settings.settings.effect },
                    set: { model.setMasterEffect($0) }
                )) {
                    SwiftUI.Section(header: Text("Reactive · needs audio")) {
                        ForEach(reactiveAvailable, id: \.self) { e in
                            Text(Mapper.pretty(e)).tag(e)
                        }
                    }
                    SwiftUI.Section(header: Text("Ambient · plays on silence")) {
                        ForEach(ambientAvailable, id: \.self) { e in
                            Text(Mapper.pretty(e)).tag(e)
                        }
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(settings.status != .running)
                .frame(maxWidth: .infinity)

                if Mapper.isAmbient(settings.settings.effect) {
                    KindBadge(text: "Ambient", tint: .purple)
                } else {
                    KindBadge(text: "Reactive", tint: .accentColor)
                }
            }

            HStack(spacing: 8) {
                ForEach(settings.settings.availablePalettes, id: \.self) { id in
                    CompactPaletteSwatch(
                        palette: Palette.by(id: id),
                        selected: settings.settings.palette == id
                    ) {
                        tapHaptic()
                        withAnimation(snapSpring) { model.setPalette(id) }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 4)

            ReactiveSliderRow(
                title: "Brightness",
                value: Double(settings.settings.brightness),
                range: 0...1,
                valueText: "\(Int(settings.settings.brightness * 100))%",
                onChange: { model.setBrightness(Float($0)) },
                enabled: settings.status == .running,
                reactive: settings.settings.brightnessReactive,
                aspect: settings.settings.brightnessAspect,
                onToggleReactive: { model.setBrightnessReactive(!settings.settings.brightnessReactive) },
                onSelectAspect: { model.setBrightnessAspect($0) },
                live: model.live
            )
            ReactiveSliderRow(
                title: "Speed",
                value: Double(settings.settings.speed),
                range: 0.1...2.0,
                valueText: String(format: "%0.2fx", settings.settings.speed),
                onChange: { model.setSpeed(Float($0)) },
                enabled: settings.status == .running,
                reactive: settings.settings.speedReactive,
                aspect: settings.settings.speedAspect,
                onToggleReactive: { model.setSpeedReactive(!settings.settings.speedReactive) },
                onSelectAspect: { model.setSpeedAspect($0) },
                live: model.live
            )
            ReactiveSliderRow(
                title: "Intensity",
                value: Double(settings.settings.intensity),
                range: 0.1...2.0,
                valueText: String(format: "%0.2fx", settings.settings.intensity),
                onChange: { model.setIntensity(Float($0)) },
                enabled: settings.status == .running,
                reactive: settings.settings.intensityReactive,
                aspect: settings.settings.intensityAspect,
                onToggleReactive: { model.setIntensityReactive(!settings.settings.intensityReactive) },
                onSelectAspect: { model.setIntensityAspect($0) },
                live: model.live
            )
        }
    }

    private var reactiveAvailable: [String] {
        settings.settings.availableEffects.filter { !Mapper.isAmbient($0) }
    }
    private var ambientAvailable: [String] {
        settings.settings.availableEffects.filter { Mapper.isAmbient($0) }
    }
}

private struct KindBadge: View {
    let text: String
    let tint: Color
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.18)))
    }
}

private struct CompactPaletteSwatch: View {
    let palette: Palette
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(LinearGradient(
                    gradient: Gradient(stops: palette.stops.map {
                        Gradient.Stop(
                            color: Color(red: Double($0.r), green: Double($0.g), blue: Double($0.b)),
                            location: CGFloat($0.pos)
                        )
                    }),
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 24, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.10),
                                      lineWidth: selected ? 2 : 0.5)
                )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(palette.name)
    }
}

/// Slider row that can optionally be driven by an audio aspect. Manual
/// mode behaves like a regular slider; reactive mode multiplies the
/// slider value by the live aspect signal so the slider acts as a cap.
/// A waveform pill on the left toggles reactivity; a gear on the right
/// opens an aspect picker popover.
private struct ReactiveSliderRow: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let valueText: String
    let onChange: (Double) -> Void
    let enabled: Bool
    let reactive: Bool
    let aspect: AudioAspect
    let onToggleReactive: () -> Void
    let onSelectAspect: (AudioAspect) -> Void
    @ObservedObject var live: LiveStore
    @State private var showAspectPopover: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.callout)
                .frame(width: 70, alignment: .leading)
            ReactivePill(active: reactive, aspect: aspect, live: live, action: onToggleReactive)
                .disabled(!enabled)
            Slider(value: Binding(
                get: { value },
                set: { v in
                    let snapped = range.contains(1.0) && abs(v - 1.0) < 0.04 ? 1.0 : v
                    onChange(snapped)
                }
            ), in: range)
            .disabled(!enabled)
            Button {
                showAspectPopover = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(reactive ? Color.accentColor : Color.secondary.opacity(0.55))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!enabled || !reactive)
            .popover(isPresented: $showAspectPopover, arrowEdge: .top) {
                AspectPopover(selected: aspect) { a in
                    onSelectAspect(a)
                    showAspectPopover = false
                }
            }
            Text(valueText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(reactive ? Color.secondary.opacity(0.55) : .secondary)
                .frame(width: 42, alignment: .trailing)
        }
        .frame(height: 26)
    }
}

/// Waveform-shaped toggle pill. Tints accent when active; the icon
/// scales gently with the current aspect signal so the user gets a
/// visual confirmation the slider is being driven by audio.
private struct ReactivePill: View {
    let active: Bool
    let aspect: AudioAspect
    @ObservedObject var live: LiveStore
    let action: () -> Void

    var body: some View {
        let signal = active ? live.frame.value(for: aspect) : 0
        let scale = 1.0 + 0.30 * Double(signal)
        Button(action: action) {
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(active ? Color.accentColor : Color.secondary.opacity(0.55))
                .scaleEffect(scale)
                .frame(width: 18, height: 18)
                .background(
                    Capsule().fill(active ? Color.accentColor.opacity(0.18) : Color.clear)
                )
                .contentShape(Rectangle())
                .animation(.easeOut(duration: 0.08), value: signal)
        }
        .buttonStyle(.plain)
        .help(active ? "Audio-driven (\(aspect.label))" : "Manual — tap to make reactive")
    }
}

/// Popover content for choosing which audio aspect drives a slider.
private struct AspectPopover: View {
    let selected: AudioAspect
    let onSelect: (AudioAspect) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Driven by")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)
            ForEach(AudioAspect.allCases, id: \.self) { a in
                Button { onSelect(a) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: a.symbol)
                            .frame(width: 18)
                            .foregroundStyle(a == selected ? Color.accentColor : .primary)
                        Text(a.label).font(.callout)
                        Spacer()
                        if a == selected {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer().frame(height: 6)
        }
        .frame(width: 170)
    }
}

private struct CompactSliderRow: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let valueText: String
    let onChange: (Double) -> Void
    let enabled: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.callout)
                .frame(width: 80, alignment: .leading)
            Slider(value: Binding(
                get: { value },
                set: { v in
                    let snapped = range.contains(1.0) && abs(v - 1.0) < 0.04 ? 1.0 : v
                    onChange(snapped)
                }
            ), in: range)
            .disabled(!enabled)
            Text(valueText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
        .frame(height: 26)
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
        Section(title: "Devices") {
            VStack(spacing: 0) {
                ForEach(Array(settings.settings.devices.enumerated()), id: \.element.id) { (idx, d) in
                    DeviceDisclosureRow(model: model, index: idx, dev: d)
                    if idx < settings.settings.devices.count - 1 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 0.5)
                            .padding(.leading, 32)
                    }
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
                    IconBadge(
                        symbol: "dot.radiowaves.left.and.right",
                        tint: device.enabled ? Color.accentColor : Color.secondary.opacity(0.5)
                    )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(device.name).font(.callout.weight(.semibold))
                        Text(detailLine(device))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { currentDevice.enabled },
                        set: { model.setDeviceEnabled(index: index, $0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(settings.status != .running)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                DeviceDetail(model: model, index: index, dev: device)
                    .padding(.leading, 32)
                    .padding(.bottom, 8)
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
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

            LabeledContent {
                Text(String(format: "%0.0f%%", device.minLoad * 100))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } label: {
                HStack(spacing: 4) {
                    Text("Min load")
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow.opacity(0.85))
                }
            }
            Slider(value: Binding(
                get: { Double(currentDevice.minLoad) },
                set: { model.setDeviceMinLoad(index: index, Float($0)) }
            ), in: 0...0.5)
            .disabled(settings.status != .running)
            Text("Floors every LED channel so the PSU stays above its low-load flicker threshold. 0 = off.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("Start at login").font(.callout)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { ctrl.startAtLogin },
                    set: { ctrl.setStartAtLogin($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .padding(.vertical, 4)
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
        HStack(spacing: 5) {
            Circle().fill(kind.dot).frame(width: 6, height: 6)
            Text(kind.label).font(.caption.weight(.medium))
                .foregroundStyle(kind.dot)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
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

private struct DiscoveryPill: View {
    @ObservedObject var discovery: WLEDDiscovery
    @ObservedObject var settings: SettingsStore

    private var addableCount: Int {
        discovery.discovered.filter { d in
            !settings.settings.devices.contains(where: { $0.ip == d.ip })
        }.count
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: addableCount > 0 ? "plus.circle.fill" : "antenna.radiowaves.left.and.right")
                .font(.caption2)
            Text(label)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(addableCount > 0 ? Color.accentColor : .secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
    }

    private var label: String {
        if addableCount > 0 { return "\(addableCount) new" }
        if discovery.discovered.isEmpty { return "Scanning" }
        return "\(settings.settings.devices.count) WLED"
    }
}

// MARK: - Footer

private struct Footer: View {
    let model: ControlModel
    var body: some View {
        VStack(spacing: 0) {
            LinkRow(title: "Edit Config…") {
                let p = NSString(string: "~/.config/pulsar/config.json").expandingTildeInPath
                NSWorkspace.shared.open(URL(fileURLWithPath: p))
            }
            LinkRow(title: "Show Log…") {
                let p = NSString(string: "~/.cache/pulsar.log").expandingTildeInPath
                NSWorkspace.shared.open(URL(fileURLWithPath: p))
            }
            LinkRow(title: "Reload Config", shortcut: "R") {
                model.reloadFromDisk()
            }
            LinkRow(title: "About Pulsar") {
                NSWorkspace.shared.open(URL(string: "https://github.com/Steven17D/pulsar")!)
            }
            LinkRow(title: "Quit Pulsar", shortcut: "Q") {
                model.quit()
            }
        }
    }
}

private struct LinkRow: View {
    let title: String
    var shortcut: String? = nil
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                if let s = shortcut {
                    Text("⌘\(s)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, hPad)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(hovered ? Color.primary.opacity(0.07) : Color.clear)
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
        Section(title: "New WLED") {
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
