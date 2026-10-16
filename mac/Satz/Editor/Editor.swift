import Observation
import SatzCore
import SwiftUI

/// What one document window shows and does: the engine's document, the page on
/// screen, the selection and the status line. Every change goes through `apply`.
@Observable
final class Editor {
    let engine: Engine
    private(set) var snapshot: Snapshot
    /// The page or master on screen.
    var pageID: String?
    /// Selected layers, in the order they were chosen.
    var selection: [String] = []
    private(set) var status: Status?

    struct Status: Equatable {
        var text: String
        var error: Bool
    }

    /// The window's undo manager; each undo step of the engine registers in it, so
    /// that the Edit menu, the window's edited mark and autosave follow the engine.
    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored private var groups = 0
    @ObservationIgnored private var groupStart: String?

    init(engine: Engine) {
        self.engine = engine
        // A document that loaded makes a snapshot; one that does not is a bug in the engine.
        snapshot = try! engine.snapshot
        pageID = snapshot.pages.first?.id
    }

    var page: Page? { pageID.flatMap { snapshot.page($0) } }

    var isMaster: Bool { snapshot.masters.contains { $0.id == pageID } }

    /// Applies `command`; a command the engine rejects shows in the status line and
    /// returns nothing.
    @discardableResult
    func apply(_ command: Command) -> [String] {
        if command.type == "undo" || command.type == "redo" {
            groups = 0
        }
        let before = engine.version
        do {
            let made = try engine.apply(command)
            let notes = engine.notes
            status = notes.isEmpty ? nil : Status(text: notes.joined(separator: ". "), error: false)
            if groups == 0 && command.type != "undo" && command.type != "redo" && engine.version != before {
                registerUndo()
            }
            refresh()
            return made
        } catch {
            fail(error.localizedDescription)
            return []
        }
    }

    func fail(_ text: String) {
        status = Status(text: text, error: true)
    }

    /// Opens an undo group that lasts until `endGroup`; groups opened inside it join it.
    func beginGroup() {
        if groups == 0 {
            groupStart = engine.version
            _ = try? engine.apply(.beginUndoGroup)
        }
        groups += 1
    }

    func endGroup() {
        guard groups > 0 else { return }
        groups -= 1
        if groups == 0 {
            _ = try? engine.apply(.endUndoGroup)
            if engine.version != groupStart { registerUndo() }
            groupStart = nil
        }
    }

    /// Runs `body` as one undo step, or as part of the group already open.
    func batch<T>(_ body: () throws -> T) rethrows -> T {
        beginGroup()
        defer { endGroup() }
        return try body()
    }

    private func registerUndo() {
        undoManager?.registerUndo(withTarget: self) { editor in
            editor.step(.undo)
        }
    }

    /// Undoes or redoes one engine step and registers its opposite.
    private func step(_ command: Command) {
        apply(command)
        undoManager?.registerUndo(withTarget: self) { editor in
            editor.step(command == .undo ? .redo : .undo)
        }
    }

    /// Reads the snapshot again and keeps the page and selection where they still exist.
    private func refresh() {
        // The engine makes a snapshot of every state it reaches.
        snapshot = try! engine.snapshot
        if pageID.flatMap({ snapshot.page($0) }) == nil {
            pageID = snapshot.pages.first?.id
        }
        let ids = Set(allNodeIDs())
        selection.removeAll { !ids.contains($0) }
    }

    private func allNodeIDs() -> [String] {
        func walk(_ nodes: [Node]) -> [String] {
            nodes.flatMap { [$0.id] + walk($0.children ?? []) }
        }
        return (snapshot.pages + snapshot.masters).flatMap { walk($0.children) }
    }

    // MARK: Pages

    /// The number of the page `id` as it prints, with its master's prefix.
    func pageNumber(_ id: String) -> Int? {
        snapshot.pages.firstIndex { $0.id == id }.map { $0 + 1 }
    }

    func addPage() {
        if let id = apply(.addPage(after: pageID)).first { pageID = id }
    }

    func duplicatePage() {
        guard let pageID, !isMaster else { return }
        if let id = apply(.duplicatePage(pageID)).first { self.pageID = id }
    }

    func deletePage() {
        guard let pageID, !isMaster, snapshot.pages.count > 1 else { return }
        apply(.deletePage(pageID))
    }

    func undo() { undoManager?.undo() }
    func redo() { undoManager?.redo() }
}
