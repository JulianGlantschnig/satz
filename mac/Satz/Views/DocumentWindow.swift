import SatzCore
import SwiftUI

/// A document's window, or why its file does not open.
struct DocumentWindow: View {
    let document: SatzDocument

    var body: some View {
        switch document.editor {
        case .success(let editor):
            EditorView(editor: editor)
        case .failure(let error):
            ContentUnavailableView(
                "This file does not open",
                systemImage: "exclamationmark.triangle",
                description: Text(error.localizedDescription)
            )
            .frame(minWidth: 480, minHeight: 320)
        }
    }
}

struct EditorView: View {
    @Bindable var editor: Editor
    @Environment(\.undoManager) private var undoManager
    @State private var showsInspector = true

    var body: some View {
        NavigationSplitView {
            PagesSidebar(editor: editor)
                .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 320)
        } detail: {
            CanvasPlaceholder(editor: editor)
        }
        .inspector(isPresented: $showsInspector) {
            InspectorPlaceholder(editor: editor)
                .inspectorColumnWidth(min: 220, ideal: 260, max: 360)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showsInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StatusLine(status: editor.status)
        }
        .focusedSceneValue(\.editor, editor)
        .onAppear { editor.undoManager = undoManager }
        .onChange(of: undoManager) { _, new in editor.undoManager = new }
        .frame(minWidth: 800, minHeight: 500)
    }
}

/// The page list until the page overview comes.
struct PagesSidebar: View {
    @Bindable var editor: Editor

    var body: some View {
        List(selection: $editor.pageID) {
            Section("Pages") {
                ForEach(Array(editor.snapshot.pages.enumerated()), id: \.element.id) { i, page in
                    Label(String(localized: "Page \(i + 1)"), systemImage: "doc")
                        .tag(Optional(page.id))
                }
            }
            if !editor.snapshot.masters.isEmpty {
                Section("Masters") {
                    ForEach(editor.snapshot.masters) { master in
                        Label(master.name, systemImage: "doc.on.doc")
                            .tag(Optional(master.id))
                    }
                }
            }
        }
    }
}

struct CanvasPlaceholder: View {
    let editor: Editor

    var body: some View {
        VStack(spacing: 8) {
            if let page = editor.page {
                Text(verbatim: "\(Int(page.width.rounded())) × \(Int(page.height.rounded())) pt")
                    .font(.title3.monospacedDigit())
                Text("\(page.children.count) layers")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background.secondary)
    }
}

struct InspectorPlaceholder: View {
    let editor: Editor

    var body: some View {
        Form {
            Section("Document") {
                LabeledContent("Colour mode", value: editor.snapshot.colorMode == .cmyk ? "CMYK" : "RGB")
                LabeledContent("Pages", value: "\(editor.snapshot.pages.count)")
                LabeledContent("Facing pages", value: editor.snapshot.facingPages ? String(localized: "On") : String(localized: "Off"))
            }
        }
        .formStyle(.grouped)
    }
}

struct StatusLine: View {
    let status: Editor.Status?

    var body: some View {
        if let status {
            HStack {
                Image(systemName: status.error ? "exclamationmark.circle.fill" : "info.circle")
                    .foregroundStyle(status.error ? .red : .secondary)
                Text(status.text)
                    .lineLimit(1)
                Spacer()
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
        }
    }
}
