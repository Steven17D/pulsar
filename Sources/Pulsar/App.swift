import AppKit
import Combine
import SwiftUI

@MainActor
private final class AppController: ObservableObject {
    let model: ControlModel
    @Published var menubarSymbol: String = "waveform"
    private var cancellables = Set<AnyCancellable>()

    init() {
        self.model = ControlModel.shared
        if Showcase.isEnabled {
            Showcase.seed(model)
        } else {
            model.boot()
        }
        model.settings.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.recompute() }
        }.store(in: &cancellables)
        recompute()
    }

    private func recompute() {
        let s = model.settings.settings
        let alive = model.settings.aggregateAlive
        let new: String
        switch model.settings.status {
        case .starting, .stopped:         new = "waveform"
        case .tccDenied, .aggregateLost:  new = "exclamationmark.triangle"
        case .running:
            if !alive { new = "exclamationmark.triangle" }
            else if !s.enabled { new = "waveform.slash" }
            else { new = "waveform" }
        }
        if new != menubarSymbol { menubarSymbol = new }
    }
}

@main
struct PulsarApp: App {
    @StateObject private var controller = AppController()

    var body: some Scene {
        MenuBarExtra {
            BarView(model: controller.model)
        } label: {
            Image(systemName: controller.menubarSymbol)
        }
        .menuBarExtraStyle(.window)
    }
}
