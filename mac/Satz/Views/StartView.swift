import SatzCore
import SwiftUI

/// The window that starts a document: a page format, its orientation and pages, or an
/// example; see `web/src/Start.tsx`.
struct StartView: View {
    static let id = "start"

    @Environment(\.newDocument) private var newDocument
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage(Units.key) private var lengthUnit = LengthUnit.mm
    @AppStorage("startFormat") private var format = "A5"
    @AppStorage("startLandscape") private var landscape = false
    @AppStorage("startPages") private var pages = 8
    @AppStorage("startFacing") private var facing = true
    @AppStorage("startWidth") private var customWidth = Units.mm(148)
    @AppStorage("startHeight") private var customHeight = Units.mm(210)
    @State private var failure: String?
    @State private var recents: [URL] = []

    static let custom = "Custom"
    private var names: [String] { PageFormat.all.map(\.name) + [Self.custom] }

    /// The portrait size in pt of the format `name`.
    private func portrait(_ name: String) -> (Double, Double) {
        PageFormat.size(name, landscape: false) ?? (min(customWidth, customHeight), max(customWidth, customHeight))
    }

    /// The size of the format `name` in the chosen orientation.
    private func size(_ name: String) -> (width: Double, height: Double) {
        if name == Self.custom {
            let (w, h) = (customWidth, customHeight)
            return landscape == (w < h) ? (h, w) : (w, h)
        }
        let (w, h) = portrait(name)
        return landscape ? (h, w) : (w, h)
    }

    var body: some View {
        HStack(spacing: 0) {
            main
            Divider()
            examples
        }
        .frame(width: 780, height: 500)
        .alert("Could not open the example", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
        } message: {
            Text(failure ?? "")
        }
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Document")
                .font(.system(size: 28, weight: .semibold, design: .serif))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(names, id: \.self) { name in tile(name) }
            }
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
                let step = [.leftArrow: -1, .rightArrow: 1, .upArrow: -4, .downArrow: 4][press.key] ?? 0
                let i = (names.firstIndex(of: format) ?? 0) + step
                format = names[min(max(i, 0), names.count - 1)]
                return .handled
            }
            .accessibilityIdentifier("formats")
            HStack(spacing: 12) {
                Picker("Orientation", selection: $landscape) {
                    Label("Portrait", systemImage: "rectangle.portrait").tag(false)
                    Label("Landscape", systemImage: "rectangle").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                if format == Self.custom {
                    let s = size(Self.custom)
                    NumberField(label: "W", help: "Width", value: s.width, range: 1...Double.infinity) { v in
                        if landscape == (customWidth < customHeight) { customHeight = v } else { customWidth = v }
                    }
                    NumberField(label: "H", help: "Height", value: s.height, range: 1...Double.infinity) { v in
                        if landscape == (customWidth < customHeight) { customWidth = v } else { customHeight = v }
                    }
                }
            }
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    NumberField(label: "Pages", value: Double(pages), unit: .plain, integer: true, range: 1...999) { pages = Int($0) }
                        .frame(width: 100)
                }
                Toggle("Facing pages", isOn: Binding(get: { pages > 1 && facing }, set: { facing = $0 }))
                    .disabled(pages < 2)
            }
            Spacer()
            HStack {
                Button {
                    NSDocumentController.shared.openDocument(nil)
                } label: {
                    Label("Open File…", systemImage: "folder")
                }
                Spacer()
                Button("Create", action: create)
                    .keyboardShortcut(.defaultAction)
                    .help("\(format), \(String(localized: "\(pages) pages"))")
                    .accessibilityIdentifier("create")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func tile(_ name: String) -> some View {
        let (w, h) = size(name)
        let k = 64 / Units.mm(594)
        let chosen = format == name
        let label = name == Self.custom ? String(localized: "Custom") : name
        return Button {
            format = name
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    if name == Self.custom {
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                            .frame(width: 34, height: 44)
                            .overlay(Image(systemName: "plus").font(.caption))
                    } else {
                        // Paper is white in either appearance.
                        Rectangle()
                            .fill(.white)
                            .frame(width: min(w * k, 64), height: min(h * k, 64))
                            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                    }
                }
                .frame(width: 66, height: 66)
                Text(label).font(.system(size: 15, weight: .medium, design: .serif))
                Text("\(dimension(w)) × \(dimension(h))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(chosen ? AnyShapeStyle(SwiftUI.Color.accentColor.opacity(0.18)) : AnyShapeStyle(.quaternary.opacity(0.35))))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(chosen ? SwiftUI.Color.accentColor : .secondary.opacity(0.25), lineWidth: chosen ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("format-\(name)")
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .help("\(label), \(Units.format(w)) × \(Units.format(h))")
        // A double click makes the document at once.
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            format = name
            create()
        })
    }

    /// A length without its unit, the way the tiles show it.
    private func dimension(_ pt: Double) -> String {
        (pt / lengthUnit.pt).formatted(.number.precision(.fractionLength(0...1)))
    }

    /// The documents opened last, then the examples.
    private var examples: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if !recents.isEmpty {
                    Text("Recent").font(.system(size: Theme.small, weight: .semibold)).foregroundStyle(.secondary)
                    ForEach(recents, id: \.self) { url in
                        Button {
                            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
                        } label: {
                            RecentRow(url: url)
                        }
                        .buttonStyle(.plain)
                        .help(url.path)
                        .accessibilityIdentifier("recent-\(url.lastPathComponent)")
                    }
                    Divider().padding(.vertical, 8)
                }
                Text("Examples").font(.system(size: Theme.small, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(Example.all) { e in
                    Button {
                        open(e)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.title).font(.system(size: 13, weight: .medium, design: .serif))
                            Text(e.text).font(.system(size: Theme.small)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("example-\(e.id)")
                }
            }
            .padding(20)
        }
        .frame(width: 250)
        .frame(maxHeight: .infinity)
        .background(.background.secondary)
        .onAppear(perform: readRecents)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in readRecents() }
    }

    private func readRecents() {
        recents = Array(NSDocumentController.shared.recentDocumentURLs.prefix(4))
    }

    private func create() {
        let (w, h) = size(format)
        let data = Engine.blank(width: w, height: h, pages: pages, facing: pages > 1 && facing).save()
        newDocument { SatzDocument(data: data) }
        dismissWindow(id: Self.id)
    }

    private func open(_ e: Example) {
        do {
            let data = try e.data()
            newDocument { SatzDocument(data: data) }
            dismissWindow(id: Self.id)
        } catch {
            failure = String(localized: "\(e.title) does not open: \(error.localizedDescription). Create a new document instead.")
        }
    }
}

/// A document to start from, bundled with the app.
struct Example: Identifiable {
    let id: String
    let title: String
    let text: String

    static let all = [
        Example(id: "booklet", title: String(localized: "Satz booklet"), text: String(localized: "A5, 8 pages, master pages")),
        Example(id: "poster", title: String(localized: "Poster"), text: String(localized: "A2, 1 page, CMYK with a spot colour")),
        Example(id: "sample", title: String(localized: "Sample"), text: String(localized: "A5, 1 page with shapes and text")),
    ]

    /// The bytes of the example's `.satz` file.
    func data() throws -> Data {
        if id == "sample" { return Engine.sample().save() }
        guard let url = Bundle.main.url(forResource: id, withExtension: "satz") else { throw CocoaError(.fileNoSuchFile) }
        return try Data(contentsOf: url)
    }
}

/// A document opened lately: a picture of its first page, its name and when it changed.
private struct RecentRow: View {
    let url: URL

    var body: some View {
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        HStack(spacing: 10) {
            PagePicture(url: url).frame(width: 30, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(url.deletingPathExtension().lastPathComponent).font(.system(size: 13, weight: .medium)).lineLimit(1)
                if let date {
                    Text(date, format: .relative(presentation: .named)).font(.system(size: Theme.small)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
