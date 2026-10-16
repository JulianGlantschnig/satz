import Foundation

/// A change to the document, as the engine's `Command` takes it in JSON; see
/// `engine/src/doc/mod.rs`. The constructors below name each command's fields.
public struct Command: Hashable, Sendable, CustomStringConvertible {
    public var type: String
    public var fields: [String: JSON]

    public init(_ type: String, _ fields: [String: JSON] = [:]) {
        self.type = type
        self.fields = fields
    }

    public var json: String {
        var o = fields
        o["type"] = .string(type)
        return JSON.object(o).encodedString()
    }

    public var description: String { json }

    /// Whether it changes the document; undo and redo do, the undo group markers not.
    public var changes: Bool { type != "beginUndoGroup" && type != "endUndoGroup" }
}

extension JSON {
    static func strings(_ v: [String]) -> JSON { .array(v.map { .string($0) }) }
    static func numbers(_ v: [Double]) -> JSON { .array(v.map { .number($0) }) }
    static func optional(_ v: String?) -> JSON { v.map { .string($0) } ?? .null }
}

public enum NewKind: String, Sendable, CaseIterable {
    case rect, ellipse, polygon, star, line, path, text, frame
}

public enum Order: String, Sendable { case forward, backward, front, back }
public enum BooleanOp: String, Sendable, CaseIterable { case union, subtract, intersect, exclude }
public enum ImageFit: String, Sendable, CaseIterable { case cover, contain, frame }

extension Command {
    public static func create(parent: String, kind: NewKind, x: Double, y: Double, w: Double, h: Double) -> Command {
        Command("create", ["parent": .string(parent), "kind": .string(kind.rawValue), "x": .number(x), "y": .number(y), "w": .number(w), "h": .number(h)])
    }

    public static func placeImage(parent: String, image: String, name: String, x: Double, y: Double, w: Double, h: Double) -> Command {
        Command("placeImage", ["parent": .string(parent), "image": .string(image), "name": .string(name), "x": .number(x), "y": .number(y), "w": .number(w), "h": .number(h)])
    }

    public static func setFrame(id: String, x: Double, y: Double, w: Double, h: Double, crop: Bool = false) -> Command {
        Command("setFrame", ["id": .string(id), "x": .number(x), "y": .number(y), "w": .number(w), "h": .number(h), "crop": .bool(crop)])
    }

    public static func setText(id: String, text: String) -> Command {
        Command("setText", ["id": .string(id), "text": .string(text)])
    }

    /// Replaces the UTF-16 range `range` of the text `id` with `text`.
    public static func editText(id: String, range: Range<Int>, text: String) -> Command {
        Command("editText", ["id": .string(id), "range": .numbers([Double(range.lowerBound), Double(range.upperBound)]), "text": .string(text)])
    }

    /// Sets text attributes `props` on the UTF-16 `range` of the text `id`, or all of it for nil.
    public static func format(id: String, range: Range<Int>?, _ props: [String: JSON]) -> Command {
        var f = props
        f["id"] = .string(id)
        f["range"] = range.map { .numbers([Double($0.lowerBound), Double($0.upperBound)]) } ?? .null
        return Command("format", f)
    }

    /// Sets the properties `props` of the layer `id`.
    public static func set(id: String, _ props: [String: JSON]) -> Command {
        var f = props
        f["id"] = .string(id)
        return Command("set", f)
    }

    public static func setPath(id: String, path: [Double]) -> Command {
        Command("setPath", ["id": .string(id), "path": .numbers(path)])
    }

    public static func delete(_ ids: [String]) -> Command { Command("delete", ["ids": .strings(ids)]) }
    public static func group(_ ids: [String], frame: Bool) -> Command { Command("group", ["ids": .strings(ids), "frame": .bool(frame)]) }
    public static func ungroup(_ ids: [String]) -> Command { Command("ungroup", ["ids": .strings(ids)]) }
    public static func mask(_ ids: [String]) -> Command { Command("mask", ["ids": .strings(ids)]) }
    public static func autoLayout(_ ids: [String]) -> Command { Command("autoLayout", ["ids": .strings(ids)]) }
    public static func duplicate(_ ids: [String]) -> Command { Command("duplicate", ["ids": .strings(ids)]) }
    public static func copy(_ ids: [String]) -> Command { Command("copy", ["ids": .strings(ids)]) }

    public static func move(_ ids: [String], parent: String, index: Int) -> Command {
        Command("move", ["ids": .strings(ids), "parent": .string(parent), "index": .number(Double(index))])
    }

    public static func order(_ ids: [String], to: Order) -> Command {
        Command("order", ["ids": .strings(ids), "to": .string(to.rawValue)])
    }

    public static func paste(above: [String], page: String?) -> Command {
        var f: [String: JSON] = ["above": .strings(above)]
        if let page { f["page"] = .string(page) }
        return Command("paste", f)
    }

    public static func flatten(_ id: String) -> Command { Command("flatten", ["id": .string(id)]) }
    public static func flip(_ id: String, vertical: Bool) -> Command { Command("flip", ["id": .string(id), "vertical": .bool(vertical)]) }
    public static func fitImage(_ id: String, _ fit: ImageFit) -> Command { Command("fitImage", ["id": .string(id), "fit": .string(fit.rawValue)]) }
    public static func boolean(_ ids: [String], _ op: BooleanOp) -> Command { Command("boolean", ["ids": .strings(ids), "op": .string(op.rawValue)]) }
    public static func fillArea(_ id: String, x: Double, y: Double) -> Command { Command("fillArea", ["id": .string(id), "x": .number(x), "y": .number(y)]) }
    public static func scaleText(_ id: String, by: Double) -> Command { Command("scaleText", ["id": .string(id), "by": .number(by)]) }

    public static func addPage(after: String?) -> Command { Command("addPage", ["after": .optional(after)]) }
    public static func duplicatePage(_ id: String) -> Command { Command("duplicatePage", ["id": .string(id)]) }
    public static func deletePage(_ id: String) -> Command { Command("deletePage", ["id": .string(id)]) }
    public static func movePages(_ ids: [String], index: Int) -> Command { Command("movePages", ["ids": .strings(ids), "index": .number(Double(index))]) }

    public static func setPage(_ id: String, width: Double? = nil, height: Double? = nil, bleed: Double? = nil, scale: Bool? = nil) -> Command {
        var f: [String: JSON] = ["id": .string(id)]
        if let width { f["width"] = .number(width) }
        if let height { f["height"] = .number(height) }
        if let bleed { f["bleed"] = .number(bleed) }
        if let scale { f["scale"] = .bool(scale) }
        return Command("setPage", f)
    }

    public static func setGrids(_ id: String, _ grids: [Grid]) throws -> Command {
        Command("setGrids", ["id": .string(id), "grids": try JSON(encoding: grids)])
    }

    public static func setGuides(_ id: String, _ guides: Guides) throws -> Command {
        Command("setGuides", ["id": .string(id), "guides": try JSON(encoding: guides)])
    }

    public static func setSection(_ id: String, _ section: Section?) throws -> Command {
        Command("setSection", ["id": .string(id), "section": try section.map { try JSON(encoding: $0) } ?? .null])
    }

    public static func addMaster(like: String?, layers: Bool? = nil) -> Command {
        var f: [String: JSON] = ["like": .optional(like)]
        if let layers { f["layers"] = .bool(layers) }
        return Command("addMaster", f)
    }

    public static func setMaster(_ id: String, name: String) -> Command { Command("setMaster", ["id": .string(id), "name": .string(name)]) }
    public static func deleteMaster(_ id: String) -> Command { Command("deleteMaster", ["id": .string(id)]) }
    public static func useMaster(page: String, master: String?) -> Command { Command("useMaster", ["page": .string(page), "master": .optional(master)]) }
    public static func override(page: String, id: String) -> Command { Command("override", ["page": .string(page), "id": .string(id)]) }
    public static func resetToMaster(_ ids: [String]) -> Command { Command("resetToMaster", ["ids": .strings(ids)]) }
    public static func thread(from: String, to: String) -> Command { Command("thread", ["from": .string(from), "to": .string(to)]) }
    public static func unthread(_ id: String) -> Command { Command("unthread", ["id": .string(id)]) }

    /// Sets document settings such as `rasterPpi`, `colorMode` or `preset`.
    public static func setDocument(_ settings: [String: JSON]) -> Command { Command("setDocument", settings) }

    public static func addSwatch(name: String, color: Color, spot: Bool) throws -> Command {
        Command("addSwatch", ["name": .string(name), "color": try JSON(encoding: color), "spot": .bool(spot)])
    }

    public static func setSwatch(_ id: String, name: String? = nil, color: Color? = nil, spot: Bool? = nil) throws -> Command {
        var f: [String: JSON] = ["id": .string(id)]
        if let name { f["name"] = .string(name) }
        if let color { f["color"] = try JSON(encoding: color) }
        if let spot { f["spot"] = .bool(spot) }
        return Command("setSwatch", f)
    }

    public static func deleteSwatch(_ id: String) -> Command { Command("deleteSwatch", ["id": .string(id)]) }
    public static func addCollection(name: String) -> Command { Command("addCollection", ["name": .string(name)]) }
    public static func setCollection(_ id: String, name: String) -> Command { Command("setCollection", ["id": .string(id), "name": .string(name)]) }
    public static func deleteCollection(_ id: String) -> Command { Command("deleteCollection", ["id": .string(id)]) }
    public static func addMode(collection: String, name: String) -> Command { Command("addMode", ["collection": .string(collection), "name": .string(name)]) }
    public static func setMode(collection: String, id: String, name: String) -> Command { Command("setMode", ["collection": .string(collection), "id": .string(id), "name": .string(name)]) }
    public static func deleteMode(collection: String, id: String) -> Command { Command("deleteMode", ["collection": .string(collection), "id": .string(id)]) }

    public static func addVariable(collection: String, name: String, value: Value) throws -> Command {
        Command("addVariable", ["collection": .string(collection), "name": .string(name), "value": try JSON(encoding: value)])
    }

    public static func setVariable(_ id: String, name: String? = nil, mode: String? = nil, value: Value? = nil) throws -> Command {
        var f: [String: JSON] = ["id": .string(id)]
        if let name { f["name"] = .string(name) }
        if let mode { f["mode"] = .string(mode) }
        if let value { f["value"] = try JSON(encoding: value) }
        return Command("setVariable", f)
    }

    public static func deleteVariable(_ id: String) -> Command { Command("deleteVariable", ["id": .string(id)]) }

    public static func useMode(_ id: String, collection: String, mode: String?) -> Command {
        Command("useMode", ["id": .string(id), "collection": .string(collection), "mode": .optional(mode)])
    }

    public static func bind(_ id: String, prop: String, variable: String?) -> Command {
        Command("bind", ["id": .string(id), "prop": .string(prop), "variable": .optional(variable)])
    }

    public static func addTextStyle(name: String, _ attrs: [String: JSON] = [:]) -> Command {
        var f = attrs
        f["name"] = .string(name)
        return Command("addTextStyle", f)
    }

    public static func setTextStyle(_ id: String, name: String? = nil, _ attrs: [String: JSON] = [:]) -> Command {
        var f = attrs
        f["id"] = .string(id)
        if let name { f["name"] = .string(name) }
        return Command("setTextStyle", f)
    }

    public static func deleteTextStyle(_ id: String) -> Command { Command("deleteTextStyle", ["id": .string(id)]) }

    public static let undo = Command("undo")
    public static let redo = Command("redo")
    public static let beginUndoGroup = Command("beginUndoGroup")
    public static let endUndoGroup = Command("endUndoGroup")
}

extension Command {
    private static let framed: Set<String> = ["create", "placeImage", "setFrame"]
    /// Steps per mm that frames round to: positions to 0.1 mm, sizes to 0.01 mm.
    private static let grid: [String: Double] = ["x": 10, "y": 10, "w": 100, "h": 100]

    /// The command with x and y on a 0.1 mm grid and w and h on 0.01 mm unless they stay
    /// as in `was`, and its other numbers on 2 decimals, except the factor `by`; see
    /// `rounded` in `web/src/editor.ts`.
    public func rounded(was: Node? = nil) -> Command {
        let mm = 72 / 25.4
        func cents(_ v: Double) -> Double { (v * 100).rounded() / 100 }
        var out = self
        for (k, v) in fields {
            let per = Self.framed.contains(type) ? Self.grid[k] : nil
            if per != nil, let was, let n = v.number, n == Self.value(was, k) { continue }
            switch v {
            case .number(let n) where k != "by":
                out.fields[k] = .number(per.map { ((n / mm) * $0).rounded() / $0 * mm } ?? cents(n))
            case .array(let a) where !a.isEmpty && a.allSatisfy({ $0.number != nil }):
                out.fields[k] = .array(a.map { .number(cents($0.number!)) })
            default:
                break
            }
        }
        return out
    }

    private static func value(_ n: Node, _ key: String) -> Double? {
        switch key {
        case "x": n.x
        case "y": n.y
        case "w": n.w
        case "h": n.h
        default: nil
        }
    }
}
