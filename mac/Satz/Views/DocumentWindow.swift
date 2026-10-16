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
            Sidebar(editor: editor)
                .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 320)
        } detail: {
            ZStack {
                Canvas(editor: editor)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        VStack(spacing: 0) {
                            if editor.showsFind { FindBar(editor: editor) }
                            if let m = editor.master { MasterBanner(editor: editor, master: m) }
                        }
                    }
                if editor.showsOverview {
                    Overview(editor: editor)
                        .background(.background)
                }
            }
        }
        .inspector(isPresented: $showsInspector) {
            Inspector(editor: editor)
                .inspectorColumnWidth(min: 220, ideal: 260, max: 360)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                ZoomMenu(editor: editor)
            }
            ToolbarItem(placement: .principal) {
                Toggle(isOn: Binding(get: { editor.showsOverview }, set: { _ in editor.toggleOverview() })) {
                    Label("Page Overview", systemImage: "square.grid.2x2")
                }
                .help("Page Overview")
            }
            ToolbarItem(placement: .navigation) {
                ToolPicker(editor: editor)
            }
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

/// The zoom in percent, with the steps and fits to choose from.
struct ZoomMenu: View {
    let editor: Editor

    var body: some View {
        Menu {
            Button("Zoom In") { editor.canvas?.zoomIn() }
            Button("Zoom Out") { editor.canvas?.zoomOut() }
            Divider()
            Button("Zoom to Fit") { editor.canvas?.fit() }
            ForEach([0.5, 1, 2, 4], id: \.self) { z in
                Button(z.formatted(.percent)) { editor.canvas?.zoom(to: z) }
            }
        } label: {
            Text(editor.zoom.formatted(.percent.precision(.fractionLength(0))))
                .monospacedDigit()
                .frame(minWidth: 48)
        }
        .menuIndicator(.visible)
        .fixedSize()
        .help("Zoom")
    }
}

/// The tools that a press on the canvas uses.
struct ToolPicker: View {
    @Bindable var editor: Editor

    var body: some View {
        Picker("Tool", selection: $editor.tool) {
            ForEach(Editor.Tool.allCases) { tool in
                Label(String(localized: tool.title), systemImage: tool.symbol)
                    .help("\(String(localized: tool.title)) (\(tool.key.uppercased()))")
                    .tag(tool)
            }
        }
        .pickerStyle(.segmented)
        .labelStyle(.iconOnly)
    }
}

/// Shown above the canvas while a master is on screen.
struct MasterBanner: View {
    let editor: Editor
    let master: Page

    var body: some View {
        HStack {
            Image(systemName: "doc.on.doc")
            Text("Editing master \(master.name)")
            Spacer()
            Button("Done") { editor.exitMaster() }
                .controlSize(.small)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.purple.opacity(0.18))
    }
}
