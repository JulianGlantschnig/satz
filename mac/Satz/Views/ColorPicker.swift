import SatzCore
import SwiftUI

extension SwiftUI.Color {
    /// The screen colour 0xRRGGBB with `opacity`.
    init(rgb: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double(rgb >> 16 & 0xff) / 255, green: Double(rgb >> 8 & 0xff) / 255, blue: Double(rgb & 0xff) / 255, opacity: opacity)
    }
}

/// A colour chip over a checkerboard, which shows its transparency.
struct Chip: View {
    let color: SatzCore.Color
    let scope: Scope
    var size: CGFloat = 18

    var body: some View {
        let process = ColorMath.resolve(color, scope)
        ZStack {
            Checkerboard()
            SwiftUI.Color(rgb: ColorMath.rgb(process, scope), opacity: process.alpha)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))
    }
}

struct Checkerboard: View {
    var body: some View {
        SwiftUI.Canvas { ctx, size in
            let s: CGFloat = 4
            for y in stride(from: 0, to: size.height, by: s) {
                for x in stride(from: 0, to: size.width, by: s) where (Int(x / s) + Int(y / s)) % 2 == 0 {
                    ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)), with: .color(.gray.opacity(0.35)))
                }
            }
        }
        .background(.white)
    }
}

/// A chip that opens the colour picker; with an editor the picker has a swatches tab.
struct ColorWell: View {
    let label: LocalizedStringKey
    let color: SatzCore.Color
    let mode: ColorMode
    let scope: Scope
    var editor: Editor?
    let onChange: (SatzCore.Color) -> Void
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: { Chip(color: color, scope: scope) }
            .buttonStyle(.plain)
            .help(label)
            .accessibilityLabel(label)
            .popover(isPresented: $open, arrowEdge: .leading) {
                ColorPickerView(color: color, mode: mode, scope: scope, editor: editor, onChange: onChange)
                    .padding(12)
                    .frame(width: 250)
            }
    }
}

struct ColorPickerView: View {
    let color: SatzCore.Color
    let mode: ColorMode
    let scope: Scope
    var editor: Editor?
    let onChange: (SatzCore.Color) -> Void

    @State private var tab = 0
    @State private var hsv = HSV(0, 0, 0)
    @State private var last: SatzCore.Color?
    @State private var hexText = ""

    private var process: SatzCore.Color { ColorMath.resolve(color, scope) }
    private var screen: UInt32 { ColorMath.rgb(process, scope) }
    private var bound: String? {
        switch color {
        case .swatch(let s, _, _): s
        case .variable(let v, _): v
        default: nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if editor != nil {
                Picker("", selection: $tab) {
                    Text("Custom").tag(0)
                    Text("Swatches").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if tab == 1 {
                swatches
            } else {
                custom
            }
        }
        .onAppear {
            tab = bound != nil && editor != nil ? 1 : 0
            sync()
        }
        .onChange(of: color) { sync() }
    }

    /// Takes the hue and saturation from the colour unless it is the one set from them.
    private func sync() {
        if color != last { hsv = ColorMath.hsv(screen) }
        hexText = ColorMath.hex(screen)
    }

    private func set(_ h: HSV) {
        hsv = h
        let next = ColorMath.fromRGB(ColorMath.rgb(h), like: process, mode: mode)
        last = next
        onChange(next)
    }

    @ViewBuilder private var custom: some View {
        SaturationArea(hsv: hsv) { set($0) }
            .frame(height: 150)
        HueSlider(hue: hsv.h) { set(HSV($0, hsv.s, hsv.v)) }
            .frame(height: 12)
        OpacitySlider(rgb: screen, opacity: process.alpha) { onChange(process.with(alpha: $0)) }
            .frame(height: 12)
        if mode == .cmyk, case .cmyk(let k, let a) = process.cmykForm(mode: mode, screen: screen) {
            ForEach(0..<4, id: \.self) { i in
                HStack {
                    Text(verbatim: String(Array("CMYK")[i])).font(.caption.monospaced()).frame(width: 12)
                    Slider(value: Binding(get: { k[i] * 100 }, set: { v in
                        var c = k
                        c[i] = (v.rounded()) / 100
                        onChange(.cmyk(c, alpha: a))
                    }), in: 0...100)
                    Text(verbatim: "\(Int((k[i] * 100).rounded()))").font(.caption.monospacedDigit()).frame(width: 28, alignment: .trailing)
                }
            }
            HStack {
                Button("Copy CMYK") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ColorMath.cmykText(k), forType: .string)
                }
                Button("Paste CMYK") {
                    if let v = NSPasteboard.general.string(forType: .string).flatMap(ColorMath.parseCMYK) { onChange(.cmyk(v, alpha: a)) }
                }
            }
            .controlSize(.small)
        }
        HStack {
            Text("Hex").font(.caption).foregroundStyle(.secondary)
            TextField("Hex", text: $hexText)
                .textFieldStyle(.roundedBorder)
                .monospaced()
                .onSubmit {
                    if let v = ColorMath.parseHex(hexText) { set(ColorMath.hsv(v)) }
                }
            NumberField(label: "α", help: "Opacity", value: process.alpha * 100, unit: .percent, range: 0...100) { onChange(process.with(alpha: $0 / 100)) }
                .frame(width: 80)
        }
    }

    @ViewBuilder private var swatches: some View {
        let colors = scope.variables.filter { v in v.values.values.contains { if case .color = $0 { true } else { false } } }
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if scope.swatches.isEmpty && colors.isEmpty {
                    Text("No swatches or colour variables yet.").foregroundStyle(.secondary)
                }
                if !colors.isEmpty {
                    Text("Variables").font(.caption).foregroundStyle(.secondary)
                    ForEach(colors) { v in
                        row(name: v.name, chip: .variable(v.id, alpha: 1), selected: v.id == bound) { onChange(.variable(v.id, alpha: 1)) }
                    }
                }
                if !scope.swatches.isEmpty {
                    Text("Swatches").font(.caption).foregroundStyle(.secondary)
                    ForEach(scope.swatches) { s in
                        row(name: s.name, chip: s.color, selected: s.id == bound, spot: s.spot) { onChange(.swatch(s.id, tint: 1, alpha: 1)) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 240)
        Button {
            guard let editor else { return }
            let names = Set(scope.swatches.map(\.name))
            var i = 1
            while names.contains(String(localized: "Swatch \(i)")) { i += 1 }
            if let cmd = try? Command.addSwatch(name: String(localized: "Swatch \(i)"), color: process.with(alpha: 1), spot: false),
                let id = editor.apply(cmd).first
            {
                onChange(.swatch(id, tint: 1, alpha: process.alpha))
            }
        } label: {
            Label("Save as Swatch", systemImage: "plus")
        }
    }

    private func row(name: String, chip: SatzCore.Color, selected: Bool, spot: Bool = false, pick: @escaping () -> Void) -> some View {
        Button(action: pick) {
            HStack {
                Chip(color: chip, scope: scope, size: 16)
                Text(name).lineLimit(1)
                Spacer()
                if spot { Text("Spot").font(.caption2).padding(.horizontal, 4).background(Capsule().fill(.quaternary)) }
                if selected { Image(systemName: "checkmark") }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}

extension SatzCore.Color {
    /// The colour as CMYK for the ink sliders: CMYK as it is, RGB separated.
    @MainActor
    func cmykForm(mode: ColorMode, screen: UInt32) -> SatzCore.Color {
        if case .cmyk = self { return self }
        return ColorMath.fromRGB(screen, like: self, mode: .cmyk)
    }
}

/// Saturation across and brightness up at the hue `hsv.h`.
private struct SaturationArea: View {
    let hsv: HSV
    let set: (HSV) -> Void

    var body: some View {
        GeometryReader { g in
            ZStack {
                SwiftUI.Color(rgb: ColorMath.rgb(HSV(hsv.h, 1, 1)))
                LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                Circle()
                    .strokeBorder(.white, lineWidth: 2)
                    .shadow(radius: 1)
                    .frame(width: 14, height: 14)
                    .position(x: hsv.s * g.size.width, y: (1 - hsv.v) * g.size.height)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { d in
                set(HSV(hsv.h, min(1, max(0, d.location.x / g.size.width)), min(1, max(0, 1 - d.location.y / g.size.height))))
            })
        }
        .accessibilityLabel("Saturation and brightness")
    }
}

private struct HueSlider: View {
    let hue: Double
    let set: (Double) -> Void

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                LinearGradient(colors: stride(from: 0.0, through: 360, by: 60).map { SwiftUI.Color(rgb: ColorMath.rgb(HSV($0, 1, 1))) }, startPoint: .leading, endPoint: .trailing)
                    .clipShape(Capsule())
                Circle().strokeBorder(.white, lineWidth: 2).shadow(radius: 1)
                    .frame(width: 14, height: 14)
                    .offset(x: hue / 360 * g.size.width - 7)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { d in set(min(360, max(0, d.location.x / g.size.width * 360))) })
        }
        .accessibilityLabel("Hue")
    }
}

private struct OpacitySlider: View {
    let rgb: UInt32
    let opacity: Double
    let set: (Double) -> Void

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Checkerboard().clipShape(Capsule())
                LinearGradient(colors: [SwiftUI.Color(rgb: rgb, opacity: 0), SwiftUI.Color(rgb: rgb)], startPoint: .leading, endPoint: .trailing)
                    .clipShape(Capsule())
                Circle().strokeBorder(.white, lineWidth: 2).shadow(radius: 1)
                    .frame(width: 14, height: 14)
                    .offset(x: opacity * g.size.width - 7)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { d in set((Double(min(1, max(0, d.location.x / g.size.width))) * 100).rounded() / 100) })
        }
        .accessibilityLabel("Opacity")
    }
}
