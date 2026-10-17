import SatzCore
import SwiftUI

extension Issue {
    /// Errors stop a clean print; the rest are warnings.
    var isError: Bool { [.overset, .missingFont, .shortOfBleed, .ink].contains(problem) }
}

/// The right panel while the preflight is open: what may print wrong, the separations
/// and ink coverage of a CMYK document, and the export.
struct Preflight: View {
    let editor: Editor

    var body: some View {
        let s = editor.snapshot
        let issues = s.preflight.sorted { $0.isError && !$1.isError }
        let errors = issues.filter(\.isError).count
        Panel {
            PanelSection {
                if issues.isEmpty {
                    Label("No issues. The document is ready for print.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    ForEach(issues, id: \.self) { i in
                        IssueRow(editor: editor, issue: i)
                    }
                }
            } header: {
                HStack {
                    Text("Issues")
                    Spacer()
                    if !issues.isEmpty {
                        Text(verbatim: "\(String(localized: "\(errors) errors")), \(String(localized: "\(issues.count - errors) warnings"))")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if s.colorMode == .cmyk {
                InksSections(editor: editor)
            }
            ExportSection(editor: editor, errors: errors)
        }
        .accessibilityIdentifier("preflight")
    }
}

private struct IssueRow: View {
    let editor: Editor
    let issue: Issue

    var body: some View {
        Button {
            editor.show(issue)
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: issue.isError ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(issue.isError ? .red : .orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text(problem).fontWeight(.medium)
                    Text(issue.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(place).font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 1)
        .background(editor.selection.contains(issue.layer) ? SwiftUI.Color.accentColor.opacity(0.15) : .clear)
        .accessibilityIdentifier("issue-\(issue.problem.rawValue)")
    }

    private var problem: String {
        switch issue.problem {
        case .missingFont: String(localized: "Missing font \(issue.font ?? "")")
        case .overset: String(localized: "Overset text · \(editor.oversetWords(of: issue.layer)) words left")
        case .shortOfBleed: String(localized: "Short of the bleed")
        case .lowPpi: String(localized: "Image at \(Int((issue.ppi ?? 0).rounded())) ppi")
        case .gamut: String(localized: "Colour outside the gamut")
        case .ink: String(localized: "\(Int((issue.ink ?? 0).rounded())) % ink")
        case .nearTrim: String(localized: "\(Units.format(issue.distance ?? 0)) from the trim")
        case .rgb: String(localized: "RGB colour")
        }
    }

    /// The page or master the issue is on.
    private var place: String {
        let s = editor.snapshot
        if let n = s.pages.firstIndex(where: { $0.id == issue.page }) { return String(localized: "Page \(n + 1)") }
        return s.masters.first { $0.id == issue.page }?.name ?? ""
    }
}

/// The proof, separations and ink coverage of a CMYK document.
private struct InksSections: View {
    @Bindable var editor: Editor

    var body: some View {
        let s = editor.snapshot
        let p = editor.previewed
        PanelSection("Proof") {
            Text("Simulates print, \(s.profile ?? "FOGRA51")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Mark colours outside the gamut", isOn: $editor.inks.gamut)
        }
        PanelSection("Separations") {
            let plates: [(String, SwiftUI.Color)] = [
                (String(localized: "Cyan"), .cyan), (String(localized: "Magenta"), .pink),
                (String(localized: "Yellow"), .yellow), (String(localized: "Black"), .primary),
            ]
            let spots = p?.spots ?? s.swatches.filter(\.spot).map(\.name)
            let rows = plates + spots.map { ($0, SwiftUI.Color.gray) }
            ForEach(rows.indices, id: \.self) { bit in
                row(bit: bit, name: rows[bit].0, color: rows[bit].1)
            }
        }
        PanelSection("Ink coverage") {
            NumberField(label: "Limit", help: "Ink limit", value: s.inkLimit, unit: .percent, integer: true, range: 200...400) {
                editor.apply(.setDocument(["inkLimit": .number($0)]))
            }
            Toggle("Mark above limit", isOn: $editor.inks.over)
            LabeledContent("Highest") {
                let highest = p?.highest ?? 0
                Text(p == nil ? "–" : "\(Int(highest.rounded())) %")
                    .foregroundStyle(Double(highest) > s.inkLimit + 0.5 ? .red : .primary)
                    .monospacedDigit()
            }
            LabeledContent("Under pointer") {
                Text(editor.pointerInk.map { "\($0) %" } ?? "—")
                    .monospacedDigit()
                    .help(editor.pointerInk == nil ? "Point at a colour" : "")
            }
        }
    }

    private func row(bit: Int, name: String, color: SwiftUI.Color) -> some View {
        let on = Binding(get: { editor.inks.shows(bit) }, set: { _ in editor.inks.on ^= 1 << UInt32(bit) })
        let max = editor.previewed.flatMap { bit < $0.max.count ? $0.max[bit] : nil }
        return Toggle(isOn: on) {
            HStack {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(name)
                Spacer()
                Text(max.map { "max \(Int($0.rounded())) %" } ?? "–")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .toggleStyle(.checkbox)
        .accessibilityIdentifier("plate-\(name)")
    }
}

private struct ExportSection: View {
    let editor: Editor
    let errors: Int
    @AppStorage("exportFormat") private var format: Export.Format = .pdf
    @State private var range = ""

    var body: some View {
        let s = editor.snapshot
        let chosen = Export.pages(range, count: s.pages.count)
        PanelSection("Export") {
            Picker("Format", selection: $format) {
                ForEach(Export.Format.allCases) { f in Text(Editor.name(of: f)).tag(f) }
            }
            if !format.perPage {
                Picker("Preset", selection: Binding(get: { s.preset }, set: { editor.apply(.setDocument(["preset": .string($0.rawValue)])) })) {
                    Text("PDF/X-4, print").tag(Preset.x4)
                    Text(s.colorMode == .rgb ? "PDF/X-1a, print, CMYK documents only" : "PDF/X-1a, print")
                        .tag(Preset.x1a)
                        .selectionDisabled(s.colorMode == .rgb)
                    Text("PDF, screen").tag(Preset.screen)
                }
                let screen = s.preset == .screen
                Toggle("Crop marks", isOn: Binding(get: { s.cropMarks && !screen }, set: { editor.apply(.setDocument(["cropMarks": .bool($0)])) }))
                    .disabled(screen)
                Toggle("Include \(Units.format(s.pages.first?.bleed ?? 0)) bleed", isOn: Binding(get: { s.includeBleed && !screen }, set: { editor.apply(.setDocument(["includeBleed": .bool($0)])) }))
                    .disabled(screen)
                Picker("Images", selection: Binding(get: { s.imagePpi }, set: { editor.apply(.setDocument(["imagePpi": .number($0)])) })) {
                    ForEach(Array(Set([0, 72, 150, 300, s.imagePpi])).sorted(), id: \.self) { v in
                        Text(v == 0 ? String(localized: "Keep") : "\(Int(v)) ppi").tag(v)
                    }
                }
                .help("Image resolution")
                Picker("JPEG quality", selection: Binding(get: { s.jpegQuality }, set: { editor.apply(.setDocument(["jpegQuality": .number(Double($0))])) })) {
                    ForEach(Array(Set([0, 90, 75, s.jpegQuality])).sorted(), id: \.self) { v in
                        Text(v == 0 ? String(localized: "Lossless") : "\(v) %").tag(v)
                    }
                }
            }
            TextField("Pages", text: $range, prompt: Text("All"))
                .accessibilityIdentifier("export-pages")
            if chosen == nil {
                Text(s.pages.count > 1 ? "Pages 1–\(s.pages.count), e.g. 1-3, 5" : "Only page 1")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if format.perPage {
                NumberField(label: "Resolution", value: s.rasterPpi, unit: .plain, integer: true, range: 72...1200) {
                    editor.apply(.setDocument(["rasterPpi": .number($0)]))
                }
            }
            HStack {
                if editor.exporting { ProgressView().controlSize(.small) }
                Spacer()
                Button {
                    if let chosen { editor.export(format, indices: chosen) }
                } label: {
                    Text(editor.exporting ? String(localized: "Exporting…")
                        : errors > 0 ? String(localized: "Export with \(errors) errors")
                        : String(localized: "Export \(Editor.name(of: format))"))
                }
                .buttonStyle(.borderedProminent)
                .tint(errors > 0 ? .red : .accentColor)
                .disabled(editor.exporting || chosen == nil)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("export")
            }
        }
    }
}
