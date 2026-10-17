import SatzCore
import SwiftUI

/// A number in a unit, for lengths in the unit of the settings while the engine counts pt. It takes
/// expressions such as `10mm + 1cm` or `*2`, steps with the arrow keys (10 with Shift,
/// 0.1 with Option) and with a drag on its label; nil shows that the selection differs.
struct NumberField: View {
    enum Unit {
        case length, points, degrees, percent, plain

        var name: String {
            switch self {
            case .length: Units.unit.rawValue
            case .points: "pt"
            case .degrees: "°"
            case .percent: "%"
            case .plain: ""
            }
        }

        /// The engine's value per shown value.
        var scale: Double { self == .length ? Units.unit.pt : 1 }
    }

    let label: String
    var help: LocalizedStringKey?
    let value: Double?
    var unit: Unit = .length
    var integer = false
    var range: ClosedRange<Double> = -.infinity ... .infinity
    /// What 0 shows as, such as Auto.
    var zero: String?
    let commit: (Double) -> Void

    @AppStorage(Units.key) private var lengthUnit = LengthUnit.mm
    @State private var text = ""
    @State private var scrubbing: Double?
    @FocusState private var focused: Bool

    private var shown: Double? { value.map { $0 / unit.scale } }

    private func format(_ v: Double?) -> String {
        guard let v else { return "" }
        if v == 0, let zero { return zero }
        return v.formatted(.number.precision(.fractionLength(0...(integer ? 0 : 2))).grouping(.never))
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(LocalizedStringKey(label))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(minWidth: 14, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(scrub)
                .onHover { inside in
                    if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                }
            TextField(label, text: $text, prompt: Text(value == nil ? String(localized: "Mixed") : ""))
                .textFieldStyle(.plain)
                .labelsHidden()
                .monospacedDigit()
                .focused($focused)
                .onSubmit(submit)
                .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                    let sign: Double = press.key == .upArrow ? 1 : -1
                    let d = Expr.step(shift: press.modifiers.contains(.shift), option: press.modifiers.contains(.option), integer: integer)
                    set((shown ?? 0) + sign * d)
                    return .handled
                }
                .onExitCommand {
                    text = format(shown)
                    focused = false
                }
            if !unit.name.isEmpty {
                Text(unit.name).font(.caption).foregroundStyle(.tertiary)
            }
            if integer {
                // Whole numbers step with minus and plus too.
                Stepper(label, value: Binding(get: { shown ?? 0 }, set: { set($0) }), in: range)
                    .labelsHidden()
                    .controlSize(.mini)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary.opacity(0.6)))
        .help(help ?? LocalizedStringKey(label))
        .onAppear { text = format(shown) }
        .onChange(of: value) { if !focused { text = format(shown) } }
        .onChange(of: lengthUnit) { text = format(shown) }
        .onChange(of: focused) { _, now in if !now { submit() } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("field-\(label)")
    }

    private func submit() {
        let source = text.trimmingCharacters(in: .whitespaces)
        if let zero, source.lowercased() == zero.lowercased() {
            if shown != 0 { set(0) }
            return
        }
        guard !source.isEmpty, source != format(shown), let v = Expr.evaluate(source, current: shown ?? 0, unit: unit.name) else {
            text = format(shown)
            return
        }
        set(v)
    }

    private func set(_ v: Double) {
        var v = min(max(v, range.lowerBound), range.upperBound)
        if integer { v = v.rounded() }
        text = format(v)
        commit(v * unit.scale)
    }

    /// Dragging the label sideways changes the value by a step per 2 points.
    private var scrub: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { g in
                let start = scrubbing ?? shown ?? 0
                if scrubbing == nil { scrubbing = start }
                let flags = NSEvent.modifierFlags
                let d = Expr.step(shift: flags.contains(.shift), option: flags.contains(.option), integer: integer)
                set(start + (g.translation.width / 2).rounded() * d)
            }
            .onEnded { _ in scrubbing = nil }
    }
}
