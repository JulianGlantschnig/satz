import SatzCore
import SwiftUI

/// Finds text in every story and replaces it, above the canvas.
struct FindBar: View {
    @Bindable var editor: Editor
    @State private var query = ""
    @State private var replacement = ""
    @State private var matchCase = false
    @State private var words = false
    @State private var style = ""
    @FocusState private var focused: Bool

    private var all: [Find.Match] {
        Find.matches(editor.snapshot, query, matchCase: matchCase, words: words, style: style)
    }

    /// The index of the match the edited text selects.
    private func current(_ all: [Find.Match]) -> Int? {
        guard let e = editor.editing, let n = editor.nodes[e.id]?.node else { return nil }
        return all.firstIndex { $0.story == n.story && $0.range == e.range }
    }

    var body: some View {
        let all = all
        let current = current(all)
        VStack(spacing: 6) {
            HStack {
                TextField("Find", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit { next(1, all) }
                    .accessibilityIdentifier("find-query")
                Text(query.isEmpty ? "" : current.map { String(localized: "\($0 + 1) of \(all.count)") } ?? String(localized: "\(all.count) found"))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 70)
                Button { next(-1, all) } label: { Image(systemName: "chevron.up") }
                    .disabled(all.isEmpty)
                    .help("Previous match")
                Button { next(1, all) } label: { Image(systemName: "chevron.down") }
                    .disabled(all.isEmpty)
                    .help("Next match")
                Button { editor.showsFind = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help("Close")
            }
            HStack {
                TextField("Replace with", text: $replacement)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { replaceOne(all, current) }
                    .accessibilityIdentifier("find-replacement")
                Button("Replace") { replaceOne(all, current) }.disabled(all.isEmpty)
                Button("Replace All") { replaceAll(all) }.disabled(all.isEmpty)
            }
            HStack {
                Toggle("Match case", isOn: $matchCase)
                Toggle("Whole words", isOn: $words)
                Spacer()
                Picker("In text style", selection: $style) {
                    Text("Any").tag("")
                    ForEach(editor.snapshot.textStyles) { Text($0.name).tag($0.id) }
                }
                .fixedSize()
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
        }
        .padding(10)
        .background(.bar)
        .onAppear { focused = true }
        .onChange(of: all) { editor.found = all }
        .onAppear { editor.found = all }
        .onDisappear { editor.found = [] }
        .onExitCommand { editor.showsFind = false }
    }

    private func next(_ d: Int, _ all: [Find.Match]) {
        guard !all.isEmpty else { return }
        let i: Int
        if let c = current(all) {
            i = c + d
        } else if let e = editor.editing, let n = editor.nodes[e.id]?.node, let after = all.firstIndex(where: { $0.story == n.story && $0.range.lowerBound >= e.range.upperBound }) {
            i = d > 0 ? after : after - 1
        } else {
            i = d > 0 ? 0 : all.count - 1
        }
        editor.endTyping()
        editor.reveal(all[(i % all.count + all.count) % all.count])
    }

    private func replaceOne(_ all: [Find.Match], _ current: Int?) {
        guard let current else { return next(1, all) }
        let m = all[current]
        editor.apply(.editText(id: m.story, range: m.range, text: replacement))
        let rest = Find.matches(editor.snapshot, query, matchCase: matchCase, words: words, style: style)
        let length = (replacement as NSString).length
        if let following = rest.first(where: { $0.story == m.story && $0.range.lowerBound >= m.range.lowerBound + length })
            ?? rest.first(where: { $0.story != m.story }) ?? rest.first
        {
            editor.reveal(following)
        }
    }

    private func replaceAll(_ all: [Find.Match]) {
        editor.batch {
            for m in all.reversed() { editor.apply(.editText(id: m.story, range: m.range, text: replacement)) }
        }
        editor.say(String(localized: "Replaced \(all.count) matches"))
    }
}
