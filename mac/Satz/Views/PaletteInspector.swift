import SatzCore
import SwiftUI

/// The next free name of the form "`base` N" among `names`.
func nextName(_ base: String, _ names: [String]) -> String {
    let taken = Set(names)
    var i = 1
    while taken.contains("\(base) \(i)") { i += 1 }
    return "\(base) \(i)"
}

/// The document's swatches: the plus makes one of the selection's colour, a click edits one.
struct SwatchesSection: View {
    let editor: Editor
    @State private var editing: String?

    var body: some View {
        let snapshot = editor.snapshot
        Section {
            ForEach(snapshot.swatches) { s in
                HStack {
                    Button { editing = s.id } label: {
                        HStack {
                            Chip(color: s.color, scope: .empty, size: 16)
                            Text(s.name).lineLimit(1)
                            Spacer()
                            if s.spot { Text("Spot").font(.caption2).padding(.horizontal, 4).background(Capsule().fill(.quaternary)) }
                            if case .rgb = s.color, snapshot.colorMode == .cmyk {
                                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                                    .help("RGB only, converted to CMYK when printed")
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: Binding(get: { editing == s.id }, set: { if !$0 { editing = nil } }), arrowEdge: .leading) {
                        SwatchEditor(editor: editor, swatch: s).padding(12).frame(width: 250)
                    }
                    .contextMenu {
                        Button("Edit") { editing = s.id }
                        Button("Duplicate") {
                            if let cmd = try? Command.addSwatch(name: nextName(s.name.replacingOccurrences(of: #" \d+$"#, with: "", options: .regularExpression), snapshot.swatches.map(\.name)), color: s.color, spot: s.spot) {
                                editor.apply(cmd)
                            }
                        }
                        Button("Delete", role: .destructive) { editor.apply(.deleteSwatch(s.id)) }
                    }
                    Button { editor.apply(.deleteSwatch(s.id)) } label: { Image(systemName: "minus") }
                        .buttonStyle(.borderless)
                        .help("Delete swatch")
                }
            }
        } header: {
            HStack {
                Text("Swatches")
                Spacer()
                Button(action: add) { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("Add swatch")
            }
        }
    }

    private func add() {
        let snapshot = editor.snapshot
        let node = editor.selected.first
        let fill = node?.fills.first { $0.type == .solid }
        let color = fill.map { ColorMath.resolve($0.color, Scope(snapshot, modes: node?.activeModes ?? [:])) } ?? ColorMath.neutral("black", snapshot.colorMode)
        if let cmd = try? Command.addSwatch(name: nextName(String(localized: "Swatch"), snapshot.swatches.map(\.name)), color: color, spot: false) {
            editing = editor.apply(cmd).first
        }
    }
}

private struct SwatchEditor: View {
    let editor: Editor
    let swatch: Swatch

    var body: some View {
        let snapshot = editor.snapshot
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: Binding(get: { swatch.name }, set: { name in
                if let cmd = try? Command.setSwatch(swatch.id, name: name) { editor.apply(cmd) }
            }))
            .textFieldStyle(.roundedBorder)
            Toggle("Spot colour", isOn: Binding(get: { swatch.spot }, set: { spot in
                var color = swatch.color
                if spot, case .rgb = color { color = ColorMath.fromRGB(ColorMath.rgb(color, .empty), like: color, mode: .cmyk) }
                if let cmd = try? Command.setSwatch(swatch.id, color: color, spot: spot) { editor.apply(cmd) }
            }))
            ColorPickerView(color: swatch.color, mode: swatch.spot ? .cmyk : snapshot.colorMode, scope: Scope(snapshot)) { c in
                if let cmd = try? Command.setSwatch(swatch.id, color: c) { editor.apply(cmd) }
            }
        }
    }
}

/// The kind of a variable by its values.
enum VariableKind: String, CaseIterable {
    case color, number, font

    init(_ v: Variable) {
        switch v.values.values.first {
        case .color?: self = .color
        case .font?: self = .font
        default: self = .number
        }
    }

    var symbol: String {
        switch self {
        case .color: "drop"
        case .number: "number"
        case .font: "textformat"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .color: "Colour"
        case .number: "Number"
        case .font: "Font"
        }
    }
}

/// The document's variables with a value per mode of their collection.
struct VariablesSection: View {
    let editor: Editor
    @State private var open: String?

    var body: some View {
        let snapshot = editor.snapshot
        Section {
            ForEach(snapshot.variables) { v in
                let kind = VariableKind(v)
                HStack {
                    Button { open = v.id } label: {
                        HStack {
                            Image(systemName: kind.symbol).foregroundStyle(.secondary).frame(width: 16)
                            Text(v.name).lineLimit(1)
                            Spacer()
                            preview(v)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: Binding(get: { open == v.id }, set: { if !$0 { open = nil } }), arrowEdge: .leading) {
                        VariableEditor(editor: editor, id: v.id).padding(12).frame(width: 300)
                    }
                    Button { editor.apply(.deleteVariable(v.id)) } label: { Image(systemName: "minus") }
                        .buttonStyle(.borderless)
                        .help("Delete variable")
                }
            }
        } header: {
            HStack {
                Text("Variables")
                Spacer()
                Menu {
                    ForEach(VariableKind.allCases, id: \.self) { k in
                        Button(k.title) { add(k) }
                    }
                } label: { Image(systemName: "plus") }
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Add variable")
            }
        }
    }

    @ViewBuilder private func preview(_ v: Variable) -> some View {
        let snapshot = editor.snapshot
        let first = snapshot.collections.first { $0.id == v.collection }?.modes.first.flatMap { v.values[$0.id] }
        switch first {
        case .color(let c)?: Chip(color: c, scope: Scope(snapshot), size: 14)
        case .number(let n)?: Text(n.formatted()).foregroundStyle(.secondary).monospacedDigit()
        case .font(let f)?: Text((f ?? snapshot.fonts.first)?.name ?? "").foregroundStyle(.secondary).lineLimit(1)
        case nil: EmptyView()
        }
    }

    private func add(_ kind: VariableKind) {
        let snapshot = editor.snapshot
        editor.batch {
            guard let collection = snapshot.collections.first?.id ?? editor.apply(.addCollection(name: String(localized: "Variables"))).first else { return }
            let value: Value = switch kind {
            case .color: .color(ColorMath.neutral("black", snapshot.colorMode))
            case .number: .number(0)
            case .font: .font(nil)
            }
            let name = nextName(String(localized: kind == .color ? "Colour" : kind == .number ? "Number" : "Font"), snapshot.variables.map(\.name))
            if let cmd = try? Command.addVariable(collection: collection, name: name, value: value) {
                open = editor.apply(cmd).first
            }
        }
    }
}

/// Name and value per mode of the variable `id`.
private struct VariableEditor: View {
    let editor: Editor
    let id: String

    var body: some View {
        let snapshot = editor.snapshot
        if let v = snapshot.variables.first(where: { $0.id == id }), let c = snapshot.collections.first(where: { $0.id == v.collection }) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Name", text: Binding(get: { v.name }, set: { n in
                    if let cmd = try? Command.setVariable(id, name: n) { editor.apply(cmd) }
                }))
                .textFieldStyle(.roundedBorder)
                ForEach(c.modes) { m in
                    HStack {
                        TextField("Mode", text: Binding(get: { m.name }, set: { editor.apply(.setMode(collection: c.id, id: m.id, name: $0)) }))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                        value(v, m)
                        if c.modes.count > 1 {
                            Button { editor.apply(.deleteMode(collection: c.id, id: m.id)) } label: { Image(systemName: "minus") }
                                .buttonStyle(.borderless)
                                .help("Delete mode")
                        }
                    }
                }
                Button {
                    editor.apply(.addMode(collection: c.id, name: nextName(String(localized: "Mode"), c.modes.map(\.name))))
                } label: { Label("Add Mode", systemImage: "plus") }
            }
        }
    }

    @ViewBuilder private func value(_ v: Variable, _ m: Collection.Mode) -> some View {
        let snapshot = editor.snapshot
        let set = { (value: Value) in
            if let cmd = try? Command.setVariable(id, mode: m.id, value: value) { editor.apply(cmd) }
        }
        switch v.values[m.id] {
        case .color(let c)?:
            // Colour variables pick among swatches and plain colours, not other variables.
            var scope = Scope(snapshot)
            let _ = scope.variables = []
            ColorWell(label: "Value", color: c, mode: snapshot.colorMode, scope: scope, editor: editor) { set(.color($0)) }
            Spacer()
        case .number(let n)?:
            NumberField(label: "=", value: n, unit: .plain) { set(.number($0)) }
        case .font(let f)?:
            FontMenu(editor: editor, value: f) { set(.font($0)) }
        case nil:
            EmptyView()
        }
    }
}

/// A mode picker per collection with several modes, for the page or layer `id`.
struct ModePickers: View {
    let editor: Editor
    let id: String
    let own: Modes
    let inherited: Modes

    var body: some View {
        let collections = editor.snapshot.collections.filter { $0.modes.count > 1 }
        ForEach(collections) { c in
            let auto = c.modes.first { $0.id == inherited[c.id] } ?? c.modes[0]
            Picker(collections.count > 1 ? "\(c.name) mode" : String(localized: "Mode"), selection: Binding(
                get: { c.modes.contains { $0.id == own[c.id] } ? own[c.id] ?? "" : "" },
                set: { editor.apply(.useMode(id, collection: c.id, mode: $0.isEmpty ? nil : $0)) })
            ) {
                Text("Auto (\(auto.name))").tag("")
                ForEach(c.modes) { Text($0.name).tag($0.id) }
            }
        }
    }
}

/// A field of `prop` on the layer or text style `id`, with a menu that binds a number
/// or font variable to it; bound, it shows the variable instead.
struct VariableBinding<Field: View>: View {
    let editor: Editor
    let id: String
    let prop: String
    let title: LocalizedStringKey
    /// The field's value in the unit variables hold (mm for lengths), for "Create from value".
    var value: Double?
    @ViewBuilder let field: () -> Field

    var body: some View {
        let snapshot = editor.snapshot
        let bound = (snapshot.textStyles.first { $0.id == id }?.bindings ?? editor.nodes[id]?.node.bindings)?[prop]
        let variable = snapshot.variables.first { $0.id == bound }
        let kind: VariableKind = prop == "font" ? .font : .number
        let candidates = snapshot.variables.filter { VariableKind($0) == kind }
        HStack(spacing: 4) {
            if let variable {
                Label(variable.name, systemImage: kind.symbol)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary))
                    .help(Text(title) + Text(": \(variable.name)"))
                Spacer(minLength: 0)
            } else {
                field()
            }
            Menu {
                if variable != nil { Button("Detach Variable") { editor.apply(.bind(id, prop: prop, variable: nil)) } }
                if candidates.isEmpty, kind == .number, let value {
                    Button("Create from Value") {
                        editor.batch {
                            guard let collection = snapshot.collections.first?.id ?? editor.apply(.addCollection(name: String(localized: "Variables"))).first,
                                let cmd = try? Command.addVariable(collection: collection, name: nextName(String(localized: title.stringKey), snapshot.variables.map(\.name)), value: .number(value)),
                                let made = editor.apply(cmd).first
                            else { return }
                            editor.apply(.bind(id, prop: prop, variable: made))
                        }
                    }
                }
                ForEach(candidates) { v in
                    Button { editor.apply(.bind(id, prop: prop, variable: v.id)) } label: {
                        if v.id == bound { Label(v.name, systemImage: "checkmark") } else { Text(v.name) }
                    }
                }
                if candidates.isEmpty && (kind == .font || value == nil) {
                    Text("No variables yet")
                }
            } label: {
                Image(systemName: "curlybraces")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Apply variable")
        }
    }
}

extension LocalizedStringKey {
    /// The key itself, for building names from titles.
    var stringKey: String.LocalizationValue {
        let mirror = Mirror(reflecting: self)
        let key = mirror.children.first { $0.label == "key" }?.value as? String ?? ""
        return String.LocalizationValue(key)
    }
}
