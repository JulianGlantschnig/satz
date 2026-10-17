import SatzCore
import SwiftUI

/// Direction, alignment, gap and padding of an auto layout frame, or a button that adds
/// one; see `web/src/AutoLayout.tsx`.
struct AutoLayoutSection: View {
    let editor: Editor
    let node: Node
    @State private var eachSide = false

    private func set(_ props: [String: JSON]) { editor.apply(.set(id: node.id, props)) }

    var body: some View {
        if node.direction == .none {
            Section {
                Button {
                    editor.addAutoLayout()
                } label: {
                    Label("Add Auto Layout", systemImage: "plus")
                }
                .help("Add Auto Layout (⇧A)")
                .accessibilityIdentifier("add-auto-layout")
            } header: {
                Text("Auto Layout")
            }
        } else {
            layout
        }
    }

    private var layout: some View {
        let horizontal = node.direction == .horizontal
        let between = node.alignMain == .spaceBetween
        let padding = [node.paddingTop, node.paddingRight, node.paddingBottom, node.paddingLeft]
        let each = eachSide || !padding.allSatisfy { $0 == padding[0] }
        return Section {
            Picker("Direction", selection: Binding(get: { node.direction }, set: { set(["direction": .string($0.rawValue)]) })) {
                Label("Horizontal", systemImage: "arrow.right").tag(Direction.horizontal)
                Label("Vertical", systemImage: "arrow.down").tag(Direction.vertical)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("direction")
            HStack(alignment: .top, spacing: 12) {
                AlignmentGrid(node: node) { main, cross in
                    set(["alignMain": .string(between ? AlignMain.spaceBetween.rawValue : main.rawValue), "alignCross": .string(cross.rawValue)])
                }
                VStack(spacing: 6) {
                    VariableBinding(editor: editor, id: node.id, prop: "gap", title: "Gap", value: node.gap / Units.ptPerMM) {
                        NumberField(label: horizontal ? "↔" : "↕", help: "Gap", value: between ? nil : node.gap) { set(["gap": .number($0)]) }
                            .disabled(between)
                    }
                    Picker("Spacing", selection: Binding(get: { between }, set: { set(["alignMain": .string(($0 ? AlignMain.spaceBetween : .start).rawValue)]) })) {
                        Text("Fixed").tag(false)
                        Text("Space Between").tag(true)
                    }
                    .labelsHidden()
                    .help("Spacing mode")
                }
            }
            if each {
                Grid(horizontalSpacing: 8, verticalSpacing: 6) {
                    GridRow {
                        side("paddingTop", "T", "Top padding", node.paddingTop)
                        side("paddingRight", "R", "Right padding", node.paddingRight)
                    }
                    GridRow {
                        side("paddingBottom", "B", "Bottom padding", node.paddingBottom)
                        side("paddingLeft", "L", "Left padding", node.paddingLeft)
                    }
                }
            } else {
                NumberField(label: "Padding", value: padding[0], range: 0 ... .infinity) { v in
                    set(Dictionary(uniqueKeysWithValues: Self.sides.map { ($0, JSON.number(v)) }))
                }
            }
        } header: {
            HStack {
                Text("Auto Layout")
                Spacer()
                Toggle(isOn: Binding(get: { each }, set: { on in
                    eachSide = on
                    if !on { set(Dictionary(uniqueKeysWithValues: Self.sides.map { ($0, JSON.number(padding[0])) })) }
                })) {
                    Image(systemName: "square.dashed")
                }
                .toggleStyle(.button)
                .buttonStyle(.borderless)
                .help("Padding per side")
                Button {
                    editor.removeAutoLayout()
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .help("Remove Auto Layout (⌥⇧A)")
                .accessibilityIdentifier("remove-auto-layout")
            }
        }
    }

    static let sides = ["paddingTop", "paddingRight", "paddingBottom", "paddingLeft"]

    private func side(_ prop: String, _ label: String, _ help: LocalizedStringKey, _ value: Double) -> some View {
        VariableBinding(editor: editor, id: node.id, prop: prop, title: help, value: value / Units.ptPerMM) {
            NumberField(label: label, help: help, value: value, range: 0 ... .infinity) { set([prop: .number($0)]) }
        }
    }
}

/// Nine spots that align the children of an auto layout frame along its main and cross axis.
private struct AlignmentGrid: View {
    let node: Node
    let align: (AlignMain, AlignCross) -> Void

    static let spots: [AlignCross] = [.start, .center, .end]
    static let rows = ["top", "center", "bottom"]
    static let columns = ["left", "center", "right"]
    static let rowNames = [String(localized: "top"), String(localized: "centre"), String(localized: "bottom")]
    static let columnNames = [String(localized: "left"), String(localized: "centre"), String(localized: "right")]

    var body: some View {
        let horizontal = node.direction == .horizontal
        let between = node.alignMain == .spaceBetween
        Grid(horizontalSpacing: 2, verticalSpacing: 2) {
            ForEach(0..<3, id: \.self) { r in
                GridRow {
                    ForEach(0..<3, id: \.self) { c in
                        let (main, cross) = horizontal ? (c, r) : (r, c)
                        let on = Self.spots[cross] == node.alignCross && (between ? main == 0 : Self.spots[main].rawValue == node.alignMain.rawValue)
                        Button {
                            align(AlignMain(rawValue: Self.spots[main].rawValue) ?? .start, Self.spots[cross])
                        } label: {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(on ? SwiftUI.Color.accentColor : SwiftUI.Color.secondary.opacity(0.35))
                                .frame(width: on ? 12 : 4, height: on ? 12 : 4)
                                .frame(width: 18, height: 18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "Align \(Self.rowNames[r]) \(Self.columnNames[c])"))
                        .accessibilityIdentifier("align-\(Self.rows[r])-\(Self.columns[c])")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.6)))
    }
}

/// How the one selected layer sizes and stays in its frame: hug or fill in auto layout,
/// absolute position, or its constraints.
struct ResizingSection: View {
    let editor: Editor
    let node: Node

    private func set(_ props: [String: JSON]) { editor.apply(.set(id: node.id, props)) }

    static func applies(_ editor: Editor, _ n: Node) -> Bool {
        let parent = editor.nodes[n.id]?.parent
        return (n.kind == .frame && n.direction != .none) || parent?.kind == .frame
    }

    var body: some View {
        let parent = editor.nodes[node.id]?.parent
        let flows = editor.flow(of: node) != nil
        let hugs = (node.kind == .frame && node.direction != .none) || (node.kind == .text && flows)
        let sizes = Size.allCases.filter { $0 == .fixed || ($0 == .hug ? hugs : flows) }
        Section {
            if hugs || flows {
                HStack {
                    sizing("W", help: "Width sizing", \.horizontal, sizes)
                    sizing("H", help: "Height sizing", \.vertical, sizes)
                }
            }
            if let parent, parent.kind == .frame, parent.direction != .none {
                Toggle("Absolute position", isOn: Binding(get: { node.absolute }, set: { set(["absolute": .bool($0)]) }))
                    .accessibilityIdentifier("absolute")
            }
            if let parent, parent.kind == .frame, !flows {
                Picker("↔", selection: constraint(\.horizontal)) {
                    ForEach(Constraint.allCases, id: \.self) { Text(Self.name($0, horizontal: true)).tag($0) }
                }
                .help("Horizontal constraint")
                Picker("↕", selection: constraint(\.vertical)) {
                    ForEach(Constraint.allCases, id: \.self) { Text(Self.name($0, horizontal: false)).tag($0) }
                }
                .help("Vertical constraint")
            }
        } header: {
            Text(flows || hugs ? "Resizing" : "Constraints")
        }
    }

    private func sizing(_ label: String, help: LocalizedStringKey, _ axis: WritableKeyPath<Sizing, Size>, _ sizes: [Size]) -> some View {
        Picker(label, selection: Binding(get: { node.sizing[keyPath: axis] }, set: { s in
            var to = node.sizing
            to[keyPath: axis] = s
            if let json = try? JSON(encoding: to) { set(["sizing": json]) }
        })) {
            ForEach(sizes, id: \.self) { s in Text(Self.name(s)).tag(s) }
        }
        .help(help)
        .accessibilityIdentifier("sizing-\(label)")
    }

    private func constraint(_ axis: WritableKeyPath<Constraints, Constraint>) -> Binding<Constraint> {
        Binding(get: { node.constraints[keyPath: axis] }, set: { c in
            var to = node.constraints
            to[keyPath: axis] = c
            if let json = try? JSON(encoding: to) { set(["constraints": json]) }
        })
    }

    static func name(_ s: Size) -> String {
        switch s {
        case .fixed: String(localized: "Fixed")
        case .hug: String(localized: "Hug")
        case .fill: String(localized: "sizing.fill", defaultValue: "Fill", comment: "A layer fills its auto layout frame")
        }
    }

    static func name(_ c: Constraint, horizontal: Bool) -> String {
        switch c {
        case .min: horizontal ? String(localized: "Left") : String(localized: "Top")
        case .max: horizontal ? String(localized: "Right") : String(localized: "Bottom")
        case .stretch: horizontal ? String(localized: "Left & Right") : String(localized: "Top & Bottom")
        case .center: String(localized: "Centre")
        case .scale: String(localized: "Scale")
        }
    }
}
