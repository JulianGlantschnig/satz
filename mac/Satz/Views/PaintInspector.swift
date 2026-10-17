import SatzCore
import SwiftUI

/// Fills, strokes, effects and how a layer blends; see `web/src/Paints.tsx` and
/// `web/src/Properties.tsx`.
struct PaintSections: View {
    let editor: Editor
    let nodes: [Node]

    private var mode: ColorMode { editor.snapshot.colorMode }
    private var scope: Scope { Scope(editor.snapshot, modes: nodes.count == 1 ? nodes[0].activeModes : [:]) }

    /// Sets `props` on every selected layer as one undo step.
    func set(_ props: [String: JSON]) {
        editor.batch {
            for n in nodes { editor.apply(.set(id: n.id, props)) }
        }
    }

    private func encode(_ v: some Encodable) -> JSON { (try? JSON(encoding: v)) ?? .null }

    var body: some View {
        let one = nodes.count == 1 ? nodes[0] : nil
        if let one, one.kind == .shape, let shape = one.shape, [.ellipse, .polygon, .star].contains(shape) {
            ShapeSection(node: one, set: set)
        }
        LayerSection(editor: editor, nodes: nodes, set: set)
        if nodes.allSatisfy({ $0.kind != .group }) {
            let fills = same(nodes) { $0.fills }
            PaintList(
                title: "Fill", paints: fills, mode: mode, scope: scope, editor: editor,
                added: .solid(ColorMath.neutral(nodes.allSatisfy { $0.kind == .text } ? "black" : "gray", mode)),
                ppi: one?.ppi, images: editor.snapshot.images
            ) { set(["fills": encode($0)]) }
            if mode == .cmyk, !(fills ?? []).isEmpty {
                Toggle("Overprint fill", isOn: Binding(get: { same(nodes) { $0.overprintFill } ?? false }, set: { set(["overprintFill": .bool($0)]) }))
            }
            StrokeSection(editor: editor, nodes: nodes, mode: mode, scope: scope, set: set)
        }
        EffectList(effects: same(nodes) { $0.effects }, mode: mode, scope: scope) { set(["effects": encode($0)]) }
        WrapSection(nodes: nodes, set: set)
    }
}

/// Points of polygons and stars, the inner radius of stars, and the arc of ellipses.
private struct ShapeSection: View {
    let node: Node
    let set: ([String: JSON]) -> Void

    var body: some View {
        Section("Shape") {
            Grid(horizontalSpacing: 8, verticalSpacing: 6) {
                if node.shape == .polygon || node.shape == .star {
                    GridRow {
                        NumberField(label: "Points", value: node.count.map(Double.init), unit: .plain, integer: true, range: 3...60) { set(["count": .number($0)]) }
                        if node.shape == .star {
                            NumberField(label: "Inner", help: "Inner radius", value: (node.ratio ?? 0) * 100, unit: .percent, range: 1...100) { set(["ratio": .number($0 / 100)]) }
                        }
                    }
                }
                if node.shape == .ellipse {
                    GridRow {
                        NumberField(label: "Start", help: "Arc start", value: node.start, unit: .degrees) {
                            set(["start": .number(($0.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360))])
                        }
                        NumberField(label: "Sweep", help: "Arc sweep", value: (node.sweep ?? 1) * 360, unit: .degrees, range: 0...360) { set(["sweep": .number($0 / 360)]) }
                    }
                    GridRow {
                        NumberField(label: "Inner", help: "Inner radius", value: (node.inner ?? 0) * 100, unit: .percent, range: 0...100) { set(["inner": .number($0 / 100)]) }
                    }
                }
            }
        }
    }
}

/// Opacity, blend mode and mask of the layers.
private struct LayerSection: View {
    let editor: Editor
    let nodes: [Node]
    let set: ([String: JSON]) -> Void

    static let blends: [(Blend, LocalizedStringKey)] = [
        (.normal, "Normal"), (.darken, "Darken"), (.multiply, "Multiply"), (.colorBurn, "Colour Burn"),
        (.lighten, "Lighten"), (.screen, "Screen"), (.colorDodge, "Colour Dodge"),
        (.overlay, "Overlay"), (.softLight, "Soft Light"), (.hardLight, "Hard Light"),
        (.difference, "Difference"), (.exclusion, "Exclusion"),
        (.hue, "Hue"), (.saturation, "Saturation"), (.color, "Colour"), (.luminosity, "Luminosity"),
    ]

    var body: some View {
        let one = nodes.count == 1 ? nodes[0] : nil
        Section("Layer") {
            if let one, one.kind == .frame {
                ModePickers(editor: editor, id: one.id, own: one.modes, inherited: editor.nodes[one.id]?.parent?.activeModes ?? editor.nodes[one.id]?.page?.modes ?? [:])
            }
            HStack {
                if let one {
                    VariableBinding(editor: editor, id: one.id, prop: "opacity", title: "Opacity", value: one.opacity * 100) {
                        NumberField(label: "α", help: "Opacity", value: one.opacity * 100, unit: .percent, range: 0...100) { set(["opacity": .number($0 / 100)]) }
                    }
                } else {
                    NumberField(label: "α", help: "Opacity", value: same(nodes) { $0.opacity * 100 }, unit: .percent, range: 0...100) { set(["opacity": .number($0 / 100)]) }
                }
                Picker("Blend mode", selection: Binding(get: { same(nodes) { $0.blend } ?? .normal }, set: { set(["blend": .string($0.rawValue)]) })) {
                    ForEach(Array(Self.blends.enumerated()), id: \.offset) { i, b in
                        if [1, 4, 7, 10, 12].contains(i) { Divider() }
                        Text(b.1).tag(b.0)
                    }
                }
                .labelsHidden()
            }
            Button(one?.mask == true ? "Release Mask" : "Use as Mask") {
                if let one { set(["mask": .bool(!one.mask)]) } else { editor.mask() }
            }
        }
    }
}

/// A list of fills or strokes, topmost first: solid colours, gradients and images.
struct PaintList: View {
    static let dragPrefix = "satz-paint:"
    let title: LocalizedStringKey
    /// Nil when the selected layers differ.
    let paints: [Fill]?
    let mode: ColorMode
    let scope: Scope
    var editor: Editor?
    let added: Fill
    var ppi: Double?
    var images: [String: String] = [:]
    let onChange: ([Fill]) -> Void

    var body: some View {
        Section {
            if let paints {
                ForEach(paints.indices.reversed(), id: \.self) { i in
                    HStack(spacing: 4) {
                        // A paint dragged by its handle onto another takes its place in the stack.
                        Image(systemName: "line.3.horizontal")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .help("Drag to reorder")
                            .draggable("\(Self.dragPrefix)\(i)")
                        PaintRow(paint: paints[i], title: title, mode: mode, scope: scope, editor: editor, ppi: ppi, images: images) { next in
                            var list = paints
                            if let next { list[i] = next } else { list.remove(at: i) }
                            onChange(list)
                        }
                    }
                    .dropDestination(for: String.self) { items, _ in
                        guard let from = items.first.flatMap({ Int($0.dropFirst(Self.dragPrefix.count)) }), items.first?.hasPrefix(Self.dragPrefix) == true, paints.indices.contains(from), from != i else { return false }
                        var list = paints
                        let moved = list.remove(at: from)
                        list.insert(moved, at: i)
                        onChange(list)
                        return true
                    }
                }
            } else {
                Text("Mixed · + replaces all").foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text(title)
                Spacer()
                Button { onChange((paints ?? []) + [added]) } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("Add")
            }
        }
    }
}

private struct PaintRow: View {
    let paint: Fill
    let title: LocalizedStringKey
    let mode: ColorMode
    let scope: Scope
    var editor: Editor?
    var ppi: Double?
    var images: [String: String]
    /// The paint changed, or nil when it goes.
    let set: (Fill?) -> Void

    var body: some View {
        let p = paint
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                switch p.type {
                case .image:
                    Image(systemName: "photo")
                    Text(imageText).lineLimit(1).foregroundStyle(.secondary)
                case .solid:
                    ColorWell(label: title, color: p.color, mode: mode, scope: scope, editor: editor) { c in
                        var q = p
                        q.color = c
                        set(q)
                    }
                    switch p.color {
                    case .swatch(let id, let tint, let alpha):
                        let swatch = scope.swatches.first { $0.id == id }
                        Text(swatch?.name ?? String(localized: "Missing swatch")).lineLimit(1)
                        NumberField(label: swatch?.spot == true ? "Tint" : "α", value: (swatch?.spot == true ? tint : alpha) * 100, unit: .percent, range: 0...100) { v in
                            var q = p
                            q.color = swatch?.spot == true ? .swatch(id, tint: v / 100, alpha: alpha) : .swatch(id, tint: tint, alpha: v / 100)
                            set(q)
                        }
                    case .variable(let id, _):
                        Image(systemName: "drop")
                        Text(scope.variables.first { $0.id == id }?.name ?? String(localized: "Missing variable")).lineLimit(1)
                    default:
                        typePicker
                        NumberField(label: "α", help: "Opacity", value: p.color.alpha * 100, unit: .percent, range: 0...100) { v in
                            var q = p
                            q.color = p.color.with(alpha: v / 100)
                            set(q)
                        }
                    }
                case .linear, .radial:
                    GradientChip(paint: p, scope: scope)
                    typePicker
                }
                Spacer(minLength: 0)
                Button {
                    var q = p
                    q.visible.toggle()
                    set(q)
                } label: { Image(systemName: p.visible ? "eye" : "eye.slash") }
                    .buttonStyle(.borderless)
                    .help(p.visible ? "Hide" : "Show")
                Button { set(nil) } label: { Image(systemName: "minus") }
                    .buttonStyle(.borderless)
                    .help("Remove")
            }
            .opacity(p.visible ? 1 : 0.5)
            if p.type == .linear || p.type == .radial {
                stops
            }
        }
    }

    private var imageText: String {
        var t = String(localized: "Image")
        if let ppi { t += " · \(Int(ppi.rounded())) ppi" }
        if let space = p.image.flatMap({ images[$0] }) {
            t += " · \(space)"
            if space == (mode == .cmyk ? "RGB" : "CMYK") { t += " → \(mode.rawValue.uppercased())" }
        }
        return t
    }

    private var p: Fill { paint }

    private var typePicker: some View {
        Picker("Type", selection: Binding(get: { p.type }, set: { set(ColorMath.retype(p, $0)) })) {
            Text("Solid").tag(FillKind.solid)
            Text("Linear").tag(FillKind.linear)
            Text("Radial").tag(FillKind.radial)
        }
        .labelsHidden()
        .fixedSize()
    }

    @ViewBuilder private var stops: some View {
        if p.type == .linear {
            NumberField(label: "Angle", value: ColorMath.angle(p.transform), unit: .degrees) { v in
                var q = p
                q.transform = ColorMath.linear(v)
                set(q)
            }
        }
        ForEach(p.stops.indices, id: \.self) { k in
            let s = p.stops[k]
            HStack(spacing: 6) {
                ColorWell(label: "Stop colour", color: s.color, mode: mode, scope: scope) { c in update(k) { $0.color = c } }
                NumberField(label: "Pos", help: "Stop position", value: s.at * 100, unit: .percent, range: 0...100) { v in update(k) { $0.at = v / 100 } }
                NumberField(label: "α", help: "Stop opacity", value: s.color.alpha * 100, unit: .percent, range: 0...100) { v in update(k) { $0.color = s.color.with(alpha: v / 100) } }
                if p.stops.count > 2 {
                    Button {
                        var q = p
                        q.stops.remove(at: k)
                        set(q)
                    } label: { Image(systemName: "minus") }
                        .buttonStyle(.borderless)
                        .help("Remove stop")
                }
            }
        }
        Button {
            var q = p
            q.stops = ColorMath.split(p.stops)
            set(q)
        } label: { Label("Add Stop", systemImage: "plus") }
            .buttonStyle(.borderless)
    }

    private func update(_ k: Int, _ change: (inout Fill.Stop) -> Void) {
        var q = p
        change(&q.stops[k])
        set(q)
    }
}

private struct GradientChip: View {
    let paint: Fill
    let scope: Scope

    var body: some View {
        let stops = paint.stops.map { s in
            Gradient.Stop(color: SwiftUI.Color(rgb: ColorMath.rgb(s.color, scope), opacity: ColorMath.resolve(s.color, scope).alpha), location: s.at)
        }
        let gradient = Gradient(stops: stops.sorted { $0.location < $1.location })
        ZStack {
            Checkerboard()
            if paint.type == .linear {
                let a = ColorMath.angle(paint.transform) * .pi / 180
                LinearGradient(gradient: gradient, startPoint: UnitPoint(x: 0.5 - cos(a) / 2, y: 0.5 - sin(a) / 2), endPoint: UnitPoint(x: 0.5 + cos(a) / 2, y: 0.5 + sin(a) / 2))
            } else {
                RadialGradient(gradient: gradient, center: .center, startRadius: 0, endRadius: 9)
            }
        }
        .frame(width: 18, height: 18)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

/// Strokes and how they are drawn: weight, side weights, position, join, cap, line style and arrows.
private struct StrokeSection: View {
    let editor: Editor
    let nodes: [Node]
    let mode: ColorMode
    let scope: Scope
    let set: ([String: JSON]) -> Void

    var body: some View {
        let strokes = same(nodes) { $0.strokes }
        let one = nodes.count == 1 ? nodes[0] : nil
        let open = nodes.allSatisfy(\.isOpen)
        let sided = nodes.allSatisfy(\.isRounded)
        PaintList(title: "Stroke", paints: strokes, mode: mode, scope: scope, editor: editor, added: .solid(ColorMath.neutral("black", mode))) {
            set(["strokes": (try? JSON(encoding: $0)) ?? .null])
        }
        if !(strokes ?? []).isEmpty {
            Section {
                HStack {
                    NumberField(label: "Weight", help: "Stroke weight", value: same(nodes) { $0.strokeWeight }, unit: .points, range: 0...1000) { set(["strokeWeight": .number($0)]) }
                    if nodes.allSatisfy({ $0.kind != .text }) {
                        Picker("Line style", selection: Binding(get: { same(nodes) { $0.lineStyle } ?? .solid }, set: { set(["lineStyle": .string($0.rawValue)]) })) {
                            Text("Solid").tag(LineStyle.solid)
                            Text("Dashed").tag(LineStyle.dashed)
                            Text("Dotted").tag(LineStyle.dotted)
                            Text("Wavy").tag(LineStyle.wavy)
                            Text("Zigzag").tag(LineStyle.zigzag)
                        }
                        .labelsHidden()
                    }
                }
                if open {
                    segmented("Cap", Binding(get: { same(nodes) { $0.cap } ?? .none }, set: { set(["cap": .string($0.rawValue)]) }),
                              [(.none, "No cap", "line.diagonal"), (.round, "Round cap", "capsule"), (.square, "Square cap", "square")])
                } else if !nodes.contains(where: \.isOpen) {
                    segmented("Position", Binding(get: { same(nodes) { $0.strokeAlign } ?? .inside }, set: { set(["strokeAlign": .string($0.rawValue)]) }),
                              [(.inside, "Inside", "square.inset.filled"), (.center, "Center", "square.dashed"), (.outside, "Outside", "square")])
                }
                segmented("Join", Binding(get: { same(nodes) { $0.join } ?? .miter }, set: { set(["join": .string($0.rawValue)]) }),
                          [(.miter, "Miter join", "arrowtriangle.up"), (.round, "Round join", "circle"), (.bevel, "Bevel join", "pentagon")])
                if open {
                    Toggle("Arrow at start", isOn: Binding(get: { same(nodes) { $0.arrowStart } ?? false }, set: { set(["arrowStart": .bool($0)]) }))
                    Toggle("Arrow at end", isOn: Binding(get: { same(nodes) { $0.arrowEnd } ?? false }, set: { set(["arrowEnd": .bool($0)]) }))
                }
                if sided {
                    Toggle("Weight per side", isOn: Binding(
                        get: { same(nodes) { !($0.strokeSides ?? []).isEmpty } ?? false },
                        set: { on in set(["strokeSides": .array(on ? Array(repeating: .number(one?.strokeWeight ?? 1), count: 4) : [])]) }))
                    if let one, let sides = one.strokeSides, sides.count == 4 {
                        Grid {
                            GridRow {
                                side(one, sides, 0, "Top")
                                side(one, sides, 1, "Right")
                            }
                            GridRow {
                                side(one, sides, 2, "Bottom")
                                side(one, sides, 3, "Left")
                            }
                        }
                    }
                }
                if mode == .cmyk {
                    Toggle("Overprint stroke", isOn: Binding(get: { same(nodes) { $0.overprintStroke } ?? false }, set: { set(["overprintStroke": .bool($0)]) }))
                }
            }
        }
    }

    private func side(_ n: Node, _ sides: [Double], _ i: Int, _ label: String) -> some View {
        NumberField(label: label, value: sides[i], unit: .points, range: 0...1000) { v in
            var s = sides
            s[i] = v
            set(["strokeSides": .array(s.map { .number($0) })])
        }
    }

    private func segmented<T: Hashable>(_ title: LocalizedStringKey, _ value: Binding<T>, _ options: [(T, LocalizedStringKey, String)]) -> some View {
        Picker(title, selection: value) {
            ForEach(options, id: \.0) { Label($0.1, systemImage: $0.2).labelStyle(.iconOnly).help($0.1).tag($0.0) }
        }
        .pickerStyle(.segmented)
    }
}

/// Drop shadows and layer blurs.
struct EffectList: View {
    /// Nil when the selected layers differ.
    let effects: [Effect]?
    let mode: ColorMode
    let scope: Scope
    let onChange: ([Effect]) -> Void

    @MainActor static func shadow(_ mode: ColorMode) -> Effect {
        Effect(type: .dropShadow, x: 0, y: 4, radius: 4, color: ColorMath.neutral("black", mode).with(alpha: 0.25))
    }

    var body: some View {
        Section {
            if let effects {
                ForEach(effects.indices, id: \.self) { i in
                    let e = effects[i]
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Picker("Effect", selection: Binding(get: { e.type }, set: { t in
                                var n = Self.shadow(mode)
                                n.type = t
                                if t == .blur { n.y = 0 }
                                n.visible = e.visible
                                update(effects, i) { $0 = n }
                            })) {
                                Text("Drop Shadow").tag(Effect.Kind.dropShadow)
                                Text("Layer Blur").tag(Effect.Kind.blur)
                            }
                            .labelsHidden()
                            Spacer()
                            Button { update(effects, i) { $0.visible.toggle() } } label: { Image(systemName: e.visible ? "eye" : "eye.slash") }
                                .buttonStyle(.borderless)
                            Button {
                                var list = effects
                                list.remove(at: i)
                                onChange(list)
                            } label: { Image(systemName: "minus") }
                                .buttonStyle(.borderless)
                                .help("Remove")
                        }
                        Grid {
                            if e.type == .dropShadow {
                                GridRow {
                                    NumberField(label: "X", help: "Shadow offset X", value: e.x) { v in update(effects, i) { $0.x = v } }
                                    NumberField(label: "Y", help: "Shadow offset Y", value: e.y) { v in update(effects, i) { $0.y = v } }
                                }
                            }
                            GridRow {
                                NumberField(label: "Blur", value: e.radius, range: 0...1000) { v in update(effects, i) { $0.radius = v } }
                                if e.type == .dropShadow {
                                    HStack {
                                        ColorWell(label: "Shadow colour", color: e.color, mode: mode, scope: scope) { c in update(effects, i) { $0.color = c } }
                                        NumberField(label: "α", help: "Shadow opacity", value: e.color.alpha * 100, unit: .percent, range: 0...100) { v in
                                            update(effects, i) { $0.color = e.color.with(alpha: v / 100) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .opacity(e.visible ? 1 : 0.5)
                }
            } else {
                Text("Mixed · + replaces all").foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("Effects")
                Spacer()
                Button { onChange((effects ?? []) + [Self.shadow(mode)]) } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("Add")
            }
        }
    }

    private func update(_ effects: [Effect], _ i: Int, _ change: (inout Effect) -> Void) {
        var list = effects
        change(&list[i])
        onChange(list)
    }
}

/// How text below in the layers flows around the layers.
private struct WrapSection: View {
    let nodes: [Node]
    let set: ([String: JSON]) -> Void

    var body: some View {
        Section("Text Wrap") {
            HStack {
                Picker("Text wrap", selection: Binding(get: { same(nodes) { $0.wrap } ?? .none }, set: { set(["wrap": .string($0.rawValue)]) })) {
                    Text("No Text Wrap").tag(Wrap.none)
                    Text("Wrap Around").tag(Wrap.around)
                    Text("Jump Over").tag(Wrap.jump)
                }
                .labelsHidden()
            }
            // Apart beside the layer and above and below it.
            HStack {
                NumberField(label: "↔", help: "Horizontal text wrap offset", value: same(nodes) { $0.wrapOffsetX }, range: 0 ... .infinity) {
                    set(["wrapOffsetX": .number($0)])
                }
                NumberField(label: "↕", help: "Vertical text wrap offset", value: same(nodes) { $0.wrapOffsetY }, range: 0 ... .infinity) {
                    set(["wrapOffsetY": .number($0)])
                }
            }
            .disabled(nodes.allSatisfy { $0.wrap == .none })
        }
    }
}
