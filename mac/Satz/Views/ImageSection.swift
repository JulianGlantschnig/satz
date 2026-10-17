import SatzCore
import SwiftUI

/// The image of the one selected image frame: crop, fit and adjust it; see `web/src/Quick.tsx`.
struct ImageSection: View {
    let editor: Editor
    let node: Node

    static let fits: [(ImageFit, LocalizedStringKey, String)] = [
        (.cover, "Fill Frame", "arrow.up.left.and.arrow.down.right"),
        (.contain, "Fit in Frame", "arrow.down.right.and.arrow.up.left"),
        (.frame, "Frame to Image", "crop"),
    ]

    var body: some View {
        let s = editor.snapshot
        let fill = node.fills.first { $0.type == .image }
        let adjust = fill?.adjust ?? [0, 0, 0]
        let fit = Editor.fit(of: node.fills)
        Section {
            HStack {
                Toggle(isOn: Binding(get: { editor.cropping == node.id }, set: { _ in editor.toggleCrop() })) {
                    Label("Crop", systemImage: "crop")
                }
                .toggleStyle(.button)
                .help("Crop: the handles crop the frame, a drag moves the image (double-click)")
                .accessibilityIdentifier("crop")
                Spacer()
                ForEach(Self.fits, id: \.0) { f in
                    Button { editor.fitImage(f.0) } label: { Image(systemName: f.2) }
                        .help(f.1)
                        .buttonStyle(.borderless)
                        .foregroundStyle(fit == f.0 ? SwiftUI.Color.accentColor : .primary)
                        .accessibilityIdentifier("fit-\(f.0.rawValue)")
                }
            }
            ForEach(0..<3, id: \.self) { i in
                AdjustRow(editor: editor, title: Self.adjustTitles[i], value: adjust.count == 3 ? adjust[i] : 0) { v in
                    var to = adjust.count == 3 ? adjust : [0, 0, 0]
                    to[i] = v
                    editor.adjust(node, to)
                }
            }
            if adjust.contains(where: { $0 != 0 }) {
                Button("Reset Adjustments") { editor.adjust(node, [0, 0, 0]) }
                    .controlSize(.small)
            }
        } header: {
            HStack {
                Text("Image")
                Spacer()
                if let ppi = node.ppi { Text("\(Int(ppi.rounded())) ppi").monospacedDigit() }
                if s.colorMode == .cmyk, let hash = fill?.image, s.images[hash] == "RGB" {
                    Text("RGB → CMYK")
                        .help("An RGB image, converted to CMYK on export")
                }
            }
        }
    }

    static let adjustTitles: [LocalizedStringKey] = ["Brightness", "Contrast", "Saturation"]
}

/// A slider and a field in percent for one adjustment, -100 % … 100 %; a drag of the
/// slider is one undo step.
private struct AdjustRow: View {
    let editor: Editor
    let title: LocalizedStringKey
    let value: Double
    let commit: (Double) -> Void

    var body: some View {
        HStack {
            Text(title).frame(width: 74, alignment: .leading)
            Slider(value: Binding(get: { value * 100 }, set: { commit($0.rounded() / 100) }), in: -100...100) { editing in
                if editing { editor.beginGroup() } else { editor.endGroup() }
            }
            .controlSize(.small)
            .accessibilityLabel(Text(title))
            NumberField(label: "", help: title, value: (value * 100).rounded(), unit: .percent, integer: true, range: -100...100) {
                commit($0 / 100)
            }
            .frame(width: 64)
        }
    }
}
