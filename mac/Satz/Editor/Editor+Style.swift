import SatzCore
import SwiftUI

extension Editor {
    /// The paint of `n` that Copy Style takes; see `STYLE` in `web/src/commands.ts`.
    static func style(of n: Node) -> [String: JSON] {
        var out: [String: JSON] = [
            "strokeWeight": .number(n.strokeWeight), "opacity": .number(n.opacity),
        ]
        out["fills"] = try? JSON(encoding: n.fills)
        out["strokes"] = try? JSON(encoding: n.strokes)
        out["effects"] = try? JSON(encoding: n.effects)
        out["strokeAlign"] = try? JSON(encoding: n.strokeAlign)
        out["join"] = try? JSON(encoding: n.join)
        out["cap"] = try? JSON(encoding: n.cap)
        out["lineStyle"] = try? JSON(encoding: n.lineStyle)
        out["blend"] = try? JSON(encoding: n.blend)
        return out
    }

    /// Keeps the fills, strokes, opacity, blend and effects of the first selected layer.
    func copyStyle() {
        guard let n = selected.first else { return }
        copiedStyle = Self.style(of: n)
        say(String(localized: "Copied the style of \(n.name)"))
    }

    /// Gives the selected layers the style copied last.
    func pasteStyle() {
        guard let style = copiedStyle else { return }
        batch {
            for n in selected where n.kind != .group { apply(.set(id: n.id, style)) }
        }
    }

    /// Turns the selected shapes and texts into paths of their outlines.
    func flatten() {
        batch {
            for n in selected where n.kind == .text || n.kind == .shape { apply(.flatten(n.id)) }
        }
    }

    /// Text frames that fit their text: auto width for one line, else auto height; with
    /// `height`, auto height always; see `resize` in `web/src/editor.ts`.
    func fitText(height: Bool = false) {
        batch {
            for n in selected where n.kind == .text {
                let lines = n.story.flatMap { snapshot.stories[$0]?.text }?.contains("\n") ?? false
                let mode: Sizing.Resizing = height || lines || n.prev != nil || n.next != nil ? .autoHeight : .autoWidth
                if let json = try? JSON(encoding: n.sizing.text(mode)) { apply(.set(id: n.id, ["sizing": json])) }
            }
        }
    }

    /// Gives the selected text frames the resize mode `mode`.
    func resizeText(_ mode: Sizing.Resizing) {
        batch {
            for n in selected where n.kind == .text {
                if let json = try? JSON(encoding: n.sizing.text(mode)) { apply(.set(id: n.id, ["sizing": json])) }
            }
        }
    }

    var hasText: Bool { selected.contains { $0.kind == .text } }
}
