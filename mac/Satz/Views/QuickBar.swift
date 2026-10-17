import SatzCore
import SwiftUI

/// The most used properties of the selection, above it on the canvas; see `web/src/Quick.tsx`.
struct QuickBar: View {
    static let key = "quickEdit"

    let editor: Editor

    private enum Paint: String { case fills, strokes }

    private func set(_ props: [String: JSON]) {
        editor.batch {
            for n in editor.selected { editor.apply(.set(id: n.id, props)) }
        }
    }

    var body: some View {
        let nodes = editor.selected
        let one = nodes.count == 1 ? nodes[0] : nil
        HStack(spacing: 6) {
            if nodes.count > 1 {
                ForEach(Editor.Align.allCases.prefix(6)) { a in
                    Button { editor.align(a) } label: { Image(systemName: a.symbol) }
                        .help(Text(a.title))
                }
                if editor.combinable {
                    Divider().frame(height: 16)
                    ForEach(BooleanOp.allCases, id: \.self) { op in
                        Button { editor.combine(op) } label: { Image(systemName: ArrangeSection.symbol(op)) }
                            .help(ArrangeSection.title(op))
                    }
                }
                Divider().frame(height: 16)
            }
            if let one, one.kind == .text { text(one) }
            if !nodes.contains(where: { $0.kind == .group || $0.ppi != nil || $0.isOpen }) {
                paintMenu(.fills, nodes)
            }
            let stroked = nodes.allSatisfy { $0.kind != .group && $0.ppi == nil }
            if stroked { paintMenu(.strokes, nodes) }
            if stroked, let one, !one.strokes.isEmpty {
                NumberField(label: "", help: "Stroke weight", value: one.strokeWeight, unit: .points, range: 0 ... 1000) { set(["strokeWeight": .number($0)]) }
                    .frame(width: 70)
            }
            if let one, one.ppi != nil, editor.selectedImage != nil { image(one) }
            if let one, one.kind == .shape, one.shape == .polygon || one.shape == .star {
                NumberField(label: "Points", value: Double(one.count ?? 5), unit: .plain, integer: true, range: 3...60) { set(["count": .number($0)]) }
                    .frame(width: 90)
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.background, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quick-bar")
    }

    @ViewBuilder
    private func text(_ n: Node) -> some View {
        let spans = n.story.flatMap { editor.snapshot.stories[$0]?.spans.map(\.attrs) } ?? []
        let format = { (props: [String: JSON]) in editor.apply(.format(id: n.id, range: nil, props)) }
        NumberField(label: "", help: "Font size", value: shared(spans) { $0.size }, unit: .points, range: 0.1 ... 5000) { format(["size": .number($0)]) }
            .frame(width: 70)
        Picker("Align", selection: Binding(get: { shared(spans) { $0.textAlign } ?? .left }, set: { format(["textAlign": .string($0.rawValue)]) })) {
            Image(systemName: "text.alignleft").tag(Attrs.TextAlign.left).help("Align left")
            Image(systemName: "text.aligncenter").tag(Attrs.TextAlign.center).help("Align center")
            Image(systemName: "text.alignright").tag(Attrs.TextAlign.right).help("Align right")
            Image(systemName: "text.justify").tag(Attrs.TextAlign.justify).help("Justify")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    /// A menu of the colours of the document for the fills or strokes of `nodes`.
    private func paintMenu(_ paint: Paint, _ nodes: [Node]) -> some View {
        let s = editor.snapshot
        let scope = Scope(s, modes: nodes.first?.activeModes ?? [:])
        let top = (paint == .fills ? nodes.first?.fills : nodes.first?.strokes)?.last { $0.visible }
        let mixed = nodes.contains { n in (paint == .fills ? n.fills : n.strokes) != (paint == .fills ? nodes[0].fills : nodes[0].strokes) }
        let title = paint == .fills ? String(localized: "Fill colour") : String(localized: "Stroke colour")
        let colors: [(String, SatzCore.Color?)] = [
            (String(localized: "None"), nil),
            (String(localized: "Black"), ColorMath.neutral("black", s.colorMode)),
            (String(localized: "White"), ColorMath.neutral("white", s.colorMode)),
        ] + s.swatches.map { ($0.name, SatzCore.Color.swatch($0.id, tint: 1, alpha: 1)) }
        return Menu {
            ForEach(colors.indices, id: \.self) { i in
                let (name, color) = colors[i]
                Button {
                    let list = color.map { [Fill.solid($0)] } ?? []
                    if let json = try? JSON(encoding: list) { set([paint.rawValue: json]) }
                } label: {
                    Text(name)
                }
            }
        } label: {
            Group {
                if mixed {
                    Image(systemName: "questionmark.square.dashed")
                } else if let top, top.type == .solid {
                    Chip(color: top.color, scope: scope, size: 14)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.secondary.opacity(0.8)))
                } else if top != nil {
                    Image(systemName: top?.type == .image ? "photo" : "square.fill.on.square")
                } else {
                    Image(systemName: "square.slash")
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if paint == .strokes { Image(systemName: "line.diagonal").font(.system(size: 7, weight: .bold)).offset(x: 3, y: 3) }
            }
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help(title)
        .accessibilityIdentifier("quick-\(paint.rawValue)")
    }

    @ViewBuilder
    private func image(_ n: Node) -> some View {
        Toggle(isOn: Binding(get: { editor.cropping == n.id }, set: { _ in editor.toggleCrop() })) {
            Image(systemName: "crop")
        }
        .toggleStyle(.button)
        .help("Crop")
        Menu {
            ForEach(ImageSection.fits, id: \.0) { f in
                Button(f.1) { editor.fitImage(f.0) }
            }
        } label: {
            Image(systemName: "aspectratio")
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Fit Image")
        AdjustButton(editor: editor, node: n)
    }
}

/// The brightness, contrast and saturation of an image, in a popover.
private struct AdjustButton: View {
    let editor: Editor
    let node: Node
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: { Image(systemName: "slider.horizontal.3") }
            .help("Adjust Image")
            .popover(isPresented: $open, arrowEdge: .bottom) {
                Form {
                    if let n = editor.selectedImage { ImageSection(editor: editor, node: n) }
                }
                .formStyle(.grouped)
                .frame(width: 300)
            }
    }
}
