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
    @AppStorage(QuickBar.key) private var quickEdit = true
    @AppStorage(LayersShown.key) private var layers = LayersShown.page
    @AppStorage(HomeLibrary.folderKey) private var folderPath = ""

    private var folder: URL { folderPath.isEmpty ? HomeLibrary.shared.folder : URL(fileURLWithPath: folderPath) }

    /// The folder whose documents the home window shows, and where new ones are saved.
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = folder
        panel.prompt = String(localized: "Choose")
        if panel.runModal() == .OK, let url = panel.url { HomeLibrary.shared.folder = url }
    }

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { Text($0.title).tag($0) }
            }
            Picker("Unit", selection: $unit) {
                ForEach(LengthUnit.allCases) { Text("\($0.title) (\($0.rawValue))").tag($0) }
            }
            .accessibilityIdentifier("unit")
            Picker("Layers panel shows", selection: $layers) {
                ForEach(LayersShown.allCases) { Text($0.title).tag($0) }
            }
            .accessibilityIdentifier("layers-shown")
            Toggle("Quick edit bar above the selection", isOn: $quickEdit)
            LabeledContent("Satz folder") {
                HStack {
                    Text(folder.path(percentEncoded: false).abbreviatingWithTilde)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(folder.path(percentEncoded: false))
                    Button("Choose…", action: chooseFolder)
                }
            }
            .accessibilityIdentifier("satz-folder")
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
        .onChange(of: appearance) { appearance.apply() }
    }
}
