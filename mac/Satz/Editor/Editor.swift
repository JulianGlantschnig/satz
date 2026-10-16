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
    var pageID: String? {
        didSet { if pageID != oldValue { nodes = index() } }
    }
    /// Selected layers, in the order they were chosen.
    var selection: [String] = []
    /// The layers of the spread on screen by id, with their parents and pages.
    private(set) var nodes: [String: Entry] = [:]
    /// The layer under the pointer in the layers list, outlined on the canvas.
    var hover: String?
    /// The guide picked on the canvas: its page, axis and index.
    var guide: PickedGuide?
    /// Where the pointer is over the canvas, in the spread's space.
    @ObservationIgnored var pointer: CGPoint?

    struct PickedGuide: Equatable {
        var page: String
        var axis: XY
        var index: Int
    }
    private(set) var status: Status?
    /// Layout grids and guides show on the canvas.
    var showsGrids = false
    /// The canvas's zoom, 1 at one pt per screen point.
    var zoom: Double = 1

    /// The window's canvas, for the commands that move its view.
    @ObservationIgnored weak var canvas: CanvasView?

    struct Status: Equatable {
        var text: String
        var error: Bool
    }

    /// The window's undo manager; each undo step of the engine registers in it, so
    /// that the Edit menu, the window's edited mark and autosave follow the engine.
    @ObservationIgnored weak var undoManager: UndoManager?
    /// The plain text the last copy of layers put on the pasteboard; other text there came from elsewhere.
    @ObservationIgnored var copiedText: String?
    /// The last copies `duplicate` made and where their originals were.
    @ObservationIgnored var copies: (ids: [String], from: CGPoint)?
    @ObservationIgnored private var groups = 0
    @ObservationIgnored private var groupStart: String?

    init(engine: Engine) {
        self.engine = engine
        // A document that loaded makes a snapshot; one that does not is a bug in the engine.
        snapshot = try! engine.snapshot
        pageID = snapshot.pages.first?.id
        nodes = index()
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
            let was = command.fields["id"]?.string.flatMap { nodes[$0]?.node }
            let made = try engine.apply(command.rounded(was: was))
            let notes = engine.notes
            status = notes.isEmpty ? nil : Status(text: notes.joined(separator: ". "), error: false)
            if groups == 0 && command.type != "undo" && command.type != "redo" && engine.version != before {
                registerUndo()
            }
            refresh()
            return made
        } catch {
            fail(error.message)
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
        nodes = index()
        selection.removeAll { nodes[$0] == nil }
        if let g = guide, (snapshot.page(g.page)?.guides).map({ (g.axis == .x ? $0.x : $0.y).count <= g.index }) ?? true {
            guide = nil
        }
    }

    /// The layers of the spread on screen, or of the master on screen.
    private func index() -> [String: Entry] {
        var out: [String: Entry] = [:]
        let pages = master.map { [$0] } ?? spread
        for p in pages { Select.index(p.children, page: p, into: &out) }
        return out
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
