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
    var selection: [String] = [] {
        didSet {
            if let c = cropping, !selection.contains(c) { cropping = nil }
            if let v = vector, !selection.contains(v.id) { vector = nil }
        }
    }
    /// The layers of the spread on screen by id, with their parents and pages.
    private(set) var nodes: [String: Entry] = [:]
    /// The layer under the pointer in the layers list, outlined on the canvas.
    var hover: String?
    /// The guide picked on the canvas: its page, axis and index.
    var guide: PickedGuide?
    /// Where the pointer is over the canvas, in the spread's space.
    @ObservationIgnored var pointer: CGPoint?

    enum Tool: String, CaseIterable, Identifiable {
        case move, frame, text, rect, ellipse, polygon, star, line, pen, eyedropper

        var id: String { rawValue }

        /// The kind of layer the tool draws.
        var kind: NewKind? {
            switch self {
            case .move: nil
            case .frame: .frame
            case .text: .text
            case .rect: .rect
            case .ellipse: .ellipse
            case .polygon: .polygon
            case .star: .star
            case .line: .line
            case .pen, .eyedropper: nil
            }
        }

        /// Its key on the canvas, as in Figma.
        var key: String {
            switch self {
            case .move: "v"
            case .frame: "f"
            case .text: "t"
            case .rect: "r"
            case .ellipse: "o"
            case .polygon: "y"
            case .star: "s"
            case .line: "l"
            case .pen: "p"
            case .eyedropper: "i"
            }
        }

        /// Size in mm of a layer made with a click.
        var size: (Double, Double) { self == .line ? (30, 0) : self == .text ? (0, 0) : (30, 30) }

        var symbol: String {
            switch self {
            case .move: "cursorarrow"
            case .frame: "number"
            case .text: "textformat"
            case .rect: "rectangle"
            case .ellipse: "circle"
            case .polygon: "triangle"
            case .star: "star"
            case .line: "line.diagonal"
            case .pen: "pencil.tip"
            case .eyedropper: "eyedropper"
            }
        }

        var title: LocalizedStringResource {
            switch self {
            case .move: "Move"
            case .frame: "Frame"
            case .text: "Text"
            case .rect: "Rectangle"
            case .ellipse: "Ellipse"
            case .polygon: "Polygon"
            case .star: "Star"
            case .line: "Line"
            case .pen: "Pen"
            case .eyedropper: "Eyedropper"
            }
        }
    }

    struct PickedGuide: Equatable {
        var page: String
        var axis: XY
        var index: Int
    }
    private(set) var status: Status?
    /// What a press on the canvas does.
    var tool: Tool = .move {
        didSet {
            if tool != .move {
                placing = []
                cropping = nil
                vector = nil
            }
            if tool != .pen { finishPen(closed: false) }
            if [.rect, .ellipse, .line, .polygon, .star].contains(tool) { lastShape = tool }
        }
    }
    /// The shape tool used last, which the toolbar shows.
    var lastShape: Tool = .rect
    /// Images to place, the first with the next click on the canvas.
    var placing: [Placing] = []
    /// The image whose handles crop it and which a drag moves inside its frame.
    var cropping: String?
    /// The path being drawn with the pen, inside an open undo group.
    var pen: Pen?
    /// The path whose points are edited, how a click edits them and the points picked.
    var vector: PathEdit?
    /// The text layer edited in its frame, which is then the selection.
    var editing: Editing?
    /// The text frame whose out-port was clicked, to thread into the next one clicked.
    var threading: String?
    /// The page overview shows in place of the canvas, with the pages and masters picked in it.
    var showsOverview = false
    var overviewSelection: [String] = []
    /// Pictures of pages for the overview.
    @ObservationIgnored private(set) lazy var thumbnails = Thumbnails(editor: self)

    /// The find bar shows, and the matches it marks on the canvas.
    var showsFind = false
    var found: [Find.Match] = []
    /// Layout grids and guides show on the canvas.
    var showsGrids = false
    /// The preflight is open: the pages show as they print, with what `inks` marks over them.
    var showsPreflight = false
    /// The plates the preflight shows and what it marks over them.
    var inks = InkPreview.Options() {
        didSet { if inks != oldValue { previewInks() } }
    }
    /// The inks of the pages on screen while the preflight is open.
    var previewed: InkPreview?
    /// The ink coverage in percent under the pointer while the preflight is open.
    var pointerInk: Int?
    /// An export or a print runs in the background.
    var exporting = false
    @ObservationIgnored let inkPreviewer = InkPreviewer()
    @ObservationIgnored var inkRequest = InkRequest()
    /// The command palette shows over the canvas.
    var showsPalette = false
    /// The list of keyboard shortcuts shows.
    var showsShortcuts = false
    /// Rulers show along the canvas.
    var showsRulers = true
    /// The canvas's zoom, 1 at one pt per screen point.
    var zoom: Double = 1

    /// What the canvas and the page thumbnails draw from.
    @ObservationIgnored private(set) lazy var scenes = SceneSource(engine: engine)

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
    @ObservationIgnored private(set) var typing = false
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
            finishPen(closed: false)
            groups = 0
            typing = false
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

    /// Makes `icc` the document's CMYK profile, or FOGRA51 for nil.
    func setProfile(_ icc: Data?) {
        do {
            try engine.setProfile(icc)
            refresh()
        } catch {
            fail(error.message)
        }
    }

    /// Adds a TrueType or OpenType font, which sets the text in it again.
    @discardableResult
    func addFont(_ data: Data) -> Typeface? {
        do {
            let face = try engine.addFont(data)
            refresh()
            return face
        } catch {
            fail(error.message)
            return nil
        }
    }

    /// Shows `text` in the status line.
    func say(_ text: String) {
        status = Status(text: text, error: false)
    }

    func fail(_ text: String) {
        status = Status(text: text, error: true)
    }

    func clearStatus() {
        status = nil
    }

    /// Opens an undo group that lasts until `endGroup`; groups opened inside it join it.
    func beginGroup() {
        if groups == 0 {
            groupStart = engine.version
            _ = try? engine.apply(.beginUndoGroup)
        }
        groups += 1
    }

    func endGroup(register: Bool = true) {
        guard groups > 0 else { return }
        groups -= 1
        if groups == 0 {
            _ = try? engine.apply(.endUndoGroup)
            if register && engine.version != groupStart { registerUndo() }
            groupStart = nil
        }
    }

    /// Typing into the edited text is one undo step until the caret moves. Its undo
    /// registers at the first key, so that Undo works at once; it ends the step first.
    func beginTyping() {
        guard !typing else { return }
        typing = true
        beginGroup()
        undoManager?.registerUndo(withTarget: self) { editor in
            editor.endTyping()
            editor.step(.undo)
        }
    }

    func endTyping() {
        guard typing else { return }
        typing = false
        endGroup(register: false)
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
    func step(_ command: Command) {
        apply(command)
        undoManager?.registerUndo(withTarget: self) { editor in
            editor.step(command == .undo ? .redo : .undo)
        }
    }

    /// Reads the snapshot again and keeps the page and selection where they still exist.
    private func refresh() {
        // A page that goes leaves the page at its place on screen, as the web app does.
        let at = snapshot.pages.firstIndex { $0.id == pageID } ?? 0
        // The engine makes a snapshot of every state it reaches.
        snapshot = try! engine.snapshot
        if pageID.flatMap({ snapshot.page($0) }) == nil, !snapshot.pages.isEmpty {
            pageID = snapshot.pages[min(at, snapshot.pages.count - 1)].id
        }
        nodes = index()
        selection.removeAll { nodes[$0] == nil }
        if let e = editing {
            if let n = nodes[e.id]?.node, n.kind == .text, let length = story(of: n)?.utf16Length {
                editing = Editing(id: e.id, anchor: min(e.anchor, length), focus: min(e.focus, length))
                follow()
            } else {
                editing = nil
                typing = false
            }
        }
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

    /// The page to add after or act on: the current one, or the last page on a master.
    var pageOrLast: String? {
        snapshot.pages.contains { $0.id == pageID } ? pageID : snapshot.pages.last?.id
    }

    func addPage() {
        if let id = apply(.addPage(after: pageOrLast)).first { showPage(id) }
    }

    func duplicatePage() {
        guard let id = pageOrLast else { return }
        if let made = apply(.duplicatePage(id)).first { showPage(made) }
    }

    func deletePage() {
        guard let id = pageOrLast else { return }
        deletePages([id])
    }

    func undo() { undoManager?.undo() }
    func redo() { undoManager?.redo() }
}
