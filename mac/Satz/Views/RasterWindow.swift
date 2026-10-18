import AppKit
import SatzCore
import SwiftUI

/// Saved rasters: those that come with Satz, after the raster generator's templates, and
/// the user's own, which hold for every document.
enum RasterTemplates {
    static let key = "rasterTemplates"

    struct Template: Codable, Identifiable, Equatable {
        var name: String
        var spec: RasterGrid.Spec
        var id: String { name }
    }

    static var bundled: [Template] {
        func t(_ name: String.LocalizationValue, _ change: (inout RasterGrid.Spec) -> Void) -> Template {
            var s = RasterGrid.Spec()
            change(&s)
            return Template(name: String(localized: name), spec: s)
        }
        func margins(_ s: inout RasterGrid.Spec, _ t: Double, _ r: Double, _ b: Double, _ l: Double) {
            (s.marginTop, s.marginRight, s.marginBottom, s.marginLeft) = (t, r, b, l)
        }
        return [
            t("Millimetre Paper") { s in
                s.kind = .mm; margins(&s, 0, 0, 0, 0); s.thickness = 0.2
            },
            t("Bullet Journal") { s in
                s.kind = .dots; margins(&s, 10, 10, 10, 10); s.dotSpacing = 5; s.dotSize = 0.6
            },
            t("Isometric") { s in
                s.kind = .iso; margins(&s, 10, 10, 10, 20); s.isoSpacing = 5; s.thickness = 0.15; s.punch = .four
            },
            t("Music Staves") { s in
                s.kind = .music; margins(&s, 12, 12, 12, 12); s.musicLineGap = 2.5; s.musicSystemGap = 14; s.thickness = 0.3
            },
            t("Exercise Book Class 2") { s in
                s.kind = .ruled; margins(&s, 15, 12, 15, 25); s.ruledClass = 2; s.thickness = 0.35; s.punch = .four
            },
            t("Sketch Paper (5 mm)") { s in
                s.kind = .lines; margins(&s, 8, 8, 8, 8); s.hSpacing = 5; s.vSpacing = 5; s.thickness = 0.15
            },
            t("Squares 5 mm") { s in
                s.kind = .squares; margins(&s, 10, 10, 10, 25); s.hSpacing = 5; s.vSpacing = 5; s.emphasize = 5; s.thickness = 0.2; s.punch = .four
            },
            t("Logarithmic Paper") { s in
                s.kind = .log; margins(&s, 15, 15, 15, 15); s.logDecadesX = 3; s.logDecadesY = 3; s.thickness = 0.2
            },
            t("Hex Map") { s in
                s.kind = .hex; margins(&s, 10, 10, 10, 10); s.hexSize = 10; s.thickness = 0.3
            },
            t("Polar Coordinates") { s in
                s.kind = .polar; margins(&s, 10, 10, 10, 10); s.polarStep = 10; s.polarRays = 36; s.thickness = 0.2
            },
            t("Lined Paper with Punch Holes") { s in
                s.kind = .lines; margins(&s, 12, 12, 12, 25); s.hSpacing = 8; s.vSpacing = 8; s.punch = .four
            },
            t("Engineering (Axis Colours)") { s in
                s.kind = .mm; margins(&s, 10, 10, 10, 10); s.thickness = 0.18; s.axisColors = true; s.colorH = "#CC3333"; s.colorV = "#1A1A1A"
            },
        ]
    }

    static var own: [Template] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
            return (try? JSONDecoder().decode([Template].self, from: data)) ?? []
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }

    /// Saves `spec` as `name`, over a template of that name.
    static func save(_ name: String, _ spec: RasterGrid.Spec) {
        var all = own
        if let i = all.firstIndex(where: { $0.name == name }) { all[i].spec = spec } else { all.append(Template(name: name, spec: spec)) }
        own = all
    }

    static func rename(_ name: String, to new: String) {
        guard !new.isEmpty, !own.contains(where: { $0.name == new }) else { return }
        own = own.map { $0.name == name ? Template(name: new, spec: $0.spec) : $0 }
    }

    static func delete(_ name: String) {
        own = own.filter { $0.name != name }
    }
}

/// View ▸ Raster…: makes a raster for the pages, with a live preview of the current page
/// over it; after raster.brosemedien.de.
struct RasterWindow: View {
    @Bindable var editor: Editor
    @State private var spec = RasterGrid.Spec()
    @State private var target = Editor.RasterTarget.page
    @State private var own = RasterTemplates.own
    @State private var naming: String?
    @State private var renaming: (from: String, to: String)?
    @State private var chosen: String?

    var body: some View {
        VStack(spacing: 0) {
            templates
            Divider()
            HStack(spacing: 0) {
                RasterSettings(editor: editor, spec: $spec)
                    .frame(width: 300)
                Divider()
                RasterPreview(editor: editor, spec: spec)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: Theme.pasteboard))
            }
            Divider()
            footer
        }
        .frame(width: 900, height: 680)
        .onAppear {
            if let current = editor.currentRaster {
                spec = current
                if !current.name.isEmpty { chosen = current.name }
            } else if let margin = editor.page?.grids.first?.margin, margin > 0 {
                // The margin of the page's layout grid.
                let mm = margin / Units.ptPerMM
                (spec.marginTop, spec.marginRight, spec.marginBottom, spec.marginLeft) = (mm, mm, mm, mm)
            }
        }
        .alert("Save Raster as Template", isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Name", text: Binding(get: { naming ?? "" }, set: { naming = $0 }))
            Button("Save") {
                if let name = naming?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                    spec.name = name
                    RasterTemplates.save(name, spec)
                    own = RasterTemplates.own
                    chosen = name
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Template", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: Binding(get: { renaming?.to ?? "" }, set: { renaming?.to = $0 }))
            Button("Rename") {
                if let r = renaming {
                    RasterTemplates.rename(r.from, to: r.to.trimmingCharacters(in: .whitespaces))
                    own = RasterTemplates.own
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var templates: some View {
        HStack(spacing: 10) {
            TextField("Name", text: $spec.name, prompt: Text(chosen ?? String(localized: "Raster")))
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .help("Name of the raster")
                .accessibilityIdentifier("raster-window-name")
            Spacer()
            Menu {
                Section("Templates") {
                    ForEach(RasterTemplates.bundled) { t in
                        Button(t.name) { load(t) }
                    }
                }
                if !own.isEmpty {
                    Section("My Templates") {
                        ForEach(own) { t in
                            Menu(t.name) {
                                Button("Load") { load(t) }
                                Button("Replace with Current Settings") {
                                    RasterTemplates.save(t.name, spec)
                                    own = RasterTemplates.own
                                }
                                Button("Rename…") { renaming = (t.name, t.name) }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    RasterTemplates.delete(t.name)
                                    own = RasterTemplates.own
                                }
                            }
                        }
                    }
                }
            } label: {
                Text(chosen ?? String(localized: "Template"))
            }
            .fixedSize()
            .accessibilityIdentifier("raster-templates")
            Button("Save as Template…") { naming = chosen ?? "" }
                .accessibilityIdentifier("raster-save")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func load(_ t: RasterTemplates.Template) {
        var s = t.spec
        s.name = t.name
        spec = s
        chosen = t.name
    }

    /// The spec with the name of its template, or Raster.
    private var named: RasterGrid.Spec {
        var s = spec
        if s.name.isEmpty { s.name = chosen ?? String(localized: "Raster") }
        return s
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Picker("Apply to", selection: $target) {
                ForEach(Editor.RasterTarget.allCases) { t in
                    Text(t.title).tag(t)
                }
            }
            .fixedSize()
            .accessibilityIdentifier("raster-target")
            Button("Remove Raster") {
                editor.removeRaster(from: target)
            }
            .disabled(!editor.hasRaster(target))
            Spacer()
            Button("Cancel") { editor.showsRaster = false }
                .keyboardShortcut(.cancelAction)
            Button("Place as Layer") {
                editor.applyRaster(named, to: target)
                editor.showsRaster = false
            }
            .help("Puts the raster on the page as a locked layer, which prints")
            .accessibilityIdentifier("raster-layer")
            Button("Add to Layout Grids") {
                editor.addRasterGrid(named, to: target)
                editor.showsRaster = false
            }
            .keyboardShortcut(.defaultAction)
            .help("Shows the raster with the layout grids, ⇧G; it does not print")
            .accessibilityIdentifier("raster-apply")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// The settings of a raster in the sections of the raster generator.
private struct RasterSettings: View {
    let editor: Editor
    @Binding var spec: RasterGrid.Spec

    /// A length in mm, shown in the unit of the settings.
    private func mm(_ label: String, _ path: WritableKeyPath<RasterGrid.Spec, Double>, _ range: ClosedRange<Double> = 0...1000, help: LocalizedStringKey? = nil) -> some View {
        NumberField(label: label, help: help, value: spec[keyPath: path] * Units.ptPerMM, range: range.lowerBound * Units.ptPerMM ... range.upperBound * Units.ptPerMM) {
            spec[keyPath: path] = $0 / Units.ptPerMM
        }
    }

    private func number(_ label: String, _ path: WritableKeyPath<RasterGrid.Spec, Double>, _ range: ClosedRange<Double>, unit: NumberField.Unit = .plain, help: LocalizedStringKey? = nil) -> some View {
        NumberField(label: label, help: help, value: spec[keyPath: path], unit: unit, range: range) { spec[keyPath: path] = $0 }
    }

    private func count(_ label: String, _ path: WritableKeyPath<RasterGrid.Spec, Int>, _ range: ClosedRange<Double>, help: LocalizedStringKey? = nil) -> some View {
        NumberField(label: label, help: help, value: Double(spec[keyPath: path]), unit: .plain, integer: true, range: range) { spec[keyPath: path] = Int($0) }
    }

    private func color(_ label: LocalizedStringKey, _ path: WritableKeyPath<RasterGrid.Spec, String>) -> some View {
        let rgb = ColorMath.parseHex(spec[keyPath: path]) ?? 0
        return HStack {
            Text(label)
            Spacer()
            ColorWell(label: label, color: .rgb(rgb << 8 | 0xff), mode: .rgb, scope: .empty) { c in
                spec[keyPath: path] = "#" + ColorMath.hex(ColorMath.rgb(c, .empty))
            }
        }
    }

    private static func name(_ k: RasterGrid.Kind) -> LocalizedStringKey {
        switch k {
        case .lines: "Line Raster"
        case .dots: "Dots"
        case .squares: "Squares"
        case .mm: "Millimetre Paper"
        case .iso: "Isometric (60°)"
        case .hex: "Hexagonal"
        case .polar: "Polar / Radial"
        case .music: "Music Staves"
        case .ruled: "Handwriting Ruling"
        case .log: "Logarithmic"
        }
    }

    var body: some View {
        Panel {
            PanelSection("Raster Type") {
                Picker("Type", selection: $spec.kind) {
                    ForEach(RasterGrid.Kind.allCases, id: \.self) { Text(Self.name($0)).tag($0) }
                }
                .accessibilityIdentifier("raster-kind")
            }
            PanelSection("Margins") {
                Grid(horizontalSpacing: 8, verticalSpacing: 6) {
                    GridRow {
                        mm("↑", \.marginTop, help: "Top margin")
                        mm("→", \.marginRight, help: "Right margin")
                    }
                    GridRow {
                        mm("↓", \.marginBottom, help: "Bottom margin")
                        mm("←", \.marginLeft, help: "Left margin")
                    }
                }
            }
            PanelSection("Grid Lines") {
                kindFields
                Grid(horizontalSpacing: 8, verticalSpacing: 6) {
                    GridRow {
                        mm("Weight", \.thickness, 0.05...5, help: "Line weight")
                        count("Every", \.emphasize, 0...100, help: "Emphasize every n-th line")
                    }
                }
                color("Line colour", \.color)
                Toggle("Separate axis colours", isOn: $spec.axisColors).toggleStyle(.panel)
                if spec.axisColors {
                    color("Horizontal", \.colorH)
                    color("Vertical", \.colorV)
                }
                Picker("Line style", selection: $spec.style) {
                    Text("Continuous").tag(RasterGrid.Style.solid)
                    Text("Dashed").tag(RasterGrid.Style.dashed)
                    Text("Dotted").tag(RasterGrid.Style.dotted)
                }
            }
            PanelSection("Secondary Raster") {
                Toggle("Second layer", isOn: $spec.secondary).toggleStyle(.panel)
                if spec.secondary {
                    Picker("Type", selection: $spec.secondaryKind) {
                        ForEach([RasterGrid.Kind.dots, .lines, .squares], id: \.self) { Text(Self.name($0)).tag($0) }
                    }
                    Grid(horizontalSpacing: 8, verticalSpacing: 6) {
                        GridRow {
                            mm("Spacing", \.secondarySpacing, 1...100)
                            mm("Weight", \.secondaryThickness, 0.05...5, help: "Line weight")
                        }
                    }
                    color("Colour", \.secondaryColor)
                }
            }
            PanelSection("Rotation & Curvature") {
                HStack(spacing: 8) {
                    Text("Rotation")
                    // No `step`: on macOS it draws a tick mark per degree under the track.
                    Slider(value: Binding(get: { spec.rotation }, set: { spec.rotation = $0.rounded() }), in: -90...90)
                        .labelsHidden()
                        .controlSize(.small)
                    NumberField(label: "∠", help: "Rotation", value: spec.rotation, unit: .degrees, range: -90...90) {
                        spec.rotation = $0
                    }
                    .frame(width: 64)
                }
                Picker("Apply to", selection: $spec.rotationTarget) {
                    Text("Everything").tag(RasterGrid.Target.all)
                    Text("Horizontal only").tag(RasterGrid.Target.horizontal)
                    Text("Vertical only").tag(RasterGrid.Target.vertical)
                }
                Picker("Curvature", selection: $spec.curve) {
                    Text("Off").tag(RasterGrid.Curve.none)
                    Text("Wave").tag(RasterGrid.Curve.wave)
                    Text("Arc").tag(RasterGrid.Curve.arc)
                }
                if spec.curve != .none {
                    Grid(horizontalSpacing: 8, verticalSpacing: 6) {
                        GridRow {
                            mm("Amplitude", \.curveAmplitude, 0...50)
                            number("Frequency", \.curveFrequency, 0.1...10)
                        }
                    }
                }
            }
            PanelSection("Punch Holes") {
                Picker("Marking", selection: $spec.punch) {
                    Text("Off").tag(RasterGrid.Punch.none)
                    Text("2 holes (DIN A4)").tag(RasterGrid.Punch.two)
                    Text("4 holes (DIN A4)").tag(RasterGrid.Punch.four)
                    Text("Spiral binding").tag(RasterGrid.Punch.spiral)
                }
                .accessibilityIdentifier("raster-punch")
                Text("Marks the holes at the spine.").font(.caption).foregroundStyle(.secondary)
            }
            PanelSection("Header") {
                Toggle("Show header", isOn: $spec.header).toggleStyle(.panel)
                    .accessibilityIdentifier("raster-header")
                if spec.header {
                    TextField("Text", text: $spec.headerText)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("raster-header-text")
                    Picker("Position", selection: $spec.headerPosition) {
                        Text("Top left").tag(RasterGrid.Position.topLeft)
                        Text("Top centre").tag(RasterGrid.Position.topCenter)
                        Text("Top right").tag(RasterGrid.Position.topRight)
                        Text("Bottom left").tag(RasterGrid.Position.bottomLeft)
                        Text("Bottom centre").tag(RasterGrid.Position.bottomCenter)
                        Text("Bottom right").tag(RasterGrid.Position.bottomRight)
                    }
                    number("Size", \.headerSize, 6...48, unit: .points, help: "Font size")
                    FontMenu(editor: editor, value: spec.headerFont) { spec.headerFont = $0 }
                    Toggle("Date at the right edge", isOn: $spec.headerDate).toggleStyle(.panel)
                }
            }
        }
    }

    /// The spacings of the chosen type.
    @ViewBuilder
    private var kindFields: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 6) {
            switch spec.kind {
            case .lines, .squares:
                GridRow {
                    mm("↕", \.hSpacing, 0.5...200, help: "Horizontal spacing")
                    mm("↔", \.vSpacing, 0.5...200, help: "Vertical spacing")
                }
            case .dots:
                GridRow {
                    mm("Spacing", \.dotSpacing, 1...100, help: "Dot spacing")
                    mm("Size", \.dotSize, 0.1...10, help: "Dot size")
                }
            case .iso:
                GridRow { mm("Spacing", \.isoSpacing, 1...100, help: "Line spacing") }
            case .hex:
                GridRow { mm("Size", \.hexSize, 2...100, help: "Hexagon size, centre to corner") }
            case .polar:
                GridRow {
                    mm("Rings", \.polarStep, 1...100, help: "Ring spacing")
                    count("Rays", \.polarRays, 0...360, help: "Number of rays")
                }
            case .music:
                GridRow {
                    mm("Line gap", \.musicLineGap, 1...20, help: "Line spacing")
                    mm("Staff gap", \.musicSystemGap, 2...50, help: "Staff spacing")
                }
            case .ruled:
                GridRow {
                    Picker("Ruling", selection: $spec.ruledClass) {
                        Text("Class 1").tag(1)
                        Text("Class 2").tag(2)
                        Text("Class 3").tag(3)
                        Text("Class 4 / single line").tag(4)
                    }
                    .gridCellColumns(2)
                }
                GridRow { number("Scaling", \.ruledScale, 0.5...3) }
            case .log:
                GridRow {
                    count("X", \.logDecadesX, 1...6, help: "Decades horizontally")
                    count("Y", \.logDecadesY, 1...6, help: "Decades vertically")
                }
            case .mm:
                EmptyView()
            }
        }
    }
}

/// The current page with the raster under its layers, as it will look.
private struct RasterPreview: View {
    let editor: Editor
    let spec: RasterGrid.Spec

    var body: some View {
        GeometryReader { geo in
            if let page = editor.page, let image = picture(page, fit: geo.size) {
                Image(decorative: image, scale: 2)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(24)
        .accessibilityIdentifier("raster-preview")
    }

    /// FNV-1a of a layer id, the item key of its display-list ops.
    private static func key(_ id: String) -> UInt32 {
        id.utf8.reduce(0x811c_9dc5 as UInt32) { ($0 ^ UInt32($1)) &* 0x0100_0193 }
    }

    private func picture(_ page: Page, fit size: CGSize) -> CGImage? {
        guard page.width > 0, page.height > 0, size.width > 0, size.height > 0 else { return nil }
        let scale = min(size.width / page.width, size.height / page.height) * 2
        let rect = CGRect(x: 0, y: 0, width: page.width, height: page.height)
        let w = Int((rect.width * scale).rounded(.up)), h = Int((rect.height * scale).rounded(.up))
        guard let ctx = Raster.context(rect: rect, scale: scale, width: w, height: h) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(rect)
        draw(page, in: ctx)
        // The page without the raster it has now.
        let old = Set(page.children.filter { $0.raster != nil }.map { Self.key($0.id) })
        var ops = (try? DisplayList.decode(editor.engine.displayList(page: page.id))) ?? []
        if !old.isEmpty {
            var out: [DisplayList.Op] = []
            var depth = 0
            for op in ops {
                if depth > 0 {
                    if case .beginItem = op { depth += 1 } else if case .endItem = op { depth -= 1 }
                    continue
                }
                if case .beginItem(let item, _) = op, old.contains(item) {
                    depth = 1
                    continue
                }
                out.append(op)
            }
            ops = out
        }
        editor.scenes.painter.draw(ops, in: ctx)
        return ctx.makeImage()
    }

    private func draw(_ page: Page, in ctx: CGContext) {
        var sheet = Sheet(page, x: 0)
        sheet.raster = spec
        if let area = sheet.rasterArea { RasterPainter.draw(spec, in: area, mirrored: sheet.mirrored, ctx) }
    }
}
