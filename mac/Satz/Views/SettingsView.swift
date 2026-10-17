import AppKit
import SwiftUI

/// The look of the app, as the settings choose.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let key = "appearance"

    var id: Self { self }

    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }

    /// Makes the app look like this.
    func apply() {
        NSApp.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    static var current: Appearance {
        UserDefaults.standard.string(forKey: key).flatMap(Appearance.init) ?? .system
    }
}

/// ⌘,: the settings of this Mac; see `web/src/SettingsDialog.tsx`.
struct SettingsView: View {
    @AppStorage(Appearance.key) private var appearance = Appearance.system
    @AppStorage(Units.key) private var unit = LengthUnit.mm

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { Text($0.title).tag($0) }
            }
            Picker("Unit", selection: $unit) {
                ForEach(LengthUnit.allCases) { Text("\($0.title) (\($0.rawValue))").tag($0) }
            }
            .accessibilityIdentifier("unit")
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
        .onChange(of: appearance) { appearance.apply() }
    }
}
