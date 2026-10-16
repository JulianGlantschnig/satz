import Foundation
import Testing

@testable import SatzCore

/// The repository's root.
let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

struct DisplayListTests {
    /// `op` as the engine serializes it to JSON, for the fixture the web app shares.
    func plain(_ op: DisplayList.Op) -> JSON {
        func floats(_ v: [Float]) -> JSON { .array(v.map { .number(Double($0)) }) }
        func paint(_ p: DisplayList.Paint) -> JSON {
            switch p {
            case .solid(let c): return ["type": "solid", "color": floats(c)]
            case .linear(let t, let s), .radial(let t, let s):
                let type: JSON = if case .linear = p { "linear" } else { "radial" }
                return ["type": type, "transform": floats(t), "stops": .array(s.map { ["at": .number(Double($0.at)), "color": floats($0.color)] })]
            }
        }
        switch op {
        case .page(let w, let h, let b): return ["op": "page", "width": .number(Double(w)), "height": .number(Double(h)), "bleed": .number(Double(b))]
        case .beginItem(let item, _): return ["op": "beginItem", "item": .number(Double(item))]
        case .endItem: return ["op": "endItem"]
        case .fillPath(let p, let path): return ["op": "fillPath", "paint": paint(p), "path": floats(path)]
        case .glyphRun(let font, let size, let p, let glyphs, let positions):
            return ["op": "glyphRun", "font": .number(Double(font)), "size": .number(Double(size)), "paint": paint(p), "glyphs": .array(glyphs.map { .number(Double($0)) }), "positions": floats(positions)]
        case .image(let image, let t): return ["op": "image", "image": .number(Double(image)), "transform": floats(t)]
        case .pushClip(let path, let invert): return ["op": "pushClip", "path": floats(path), "invert": .bool(invert)]
        case .popClip: return ["op": "popClip"]
        case .strokePath(let p, let width, let cap, let join, let path):
            return ["op": "strokePath", "paint": paint(p), "width": .number(Double(width)), "cap": .number(Double(cap)), "join": .number(Double(join)), "path": floats(path)]
        case .pushLayer(_, let opacity, let blend, let blur, let shadows):
            return ["op": "pushLayer", "opacity": .number(Double(opacity)), "blend": .number(Double(blend)), "blur": .number(Double(blur)),
                    "shadows": .array(shadows.map { ["offset": floats($0.offset), "blur": .number(Double($0.blur)), "color": floats($0.color)] })]
        case .popLayer: return ["op": "popLayer"]
        case .beginMask: return ["op": "beginMask"]
        case .endMask: return ["op": "endMask"]
        case .popMask: return ["op": "popMask"]
        case .pushTransform(let t): return ["op": "pushTransform", "transform": floats(t)]
        case .popTransform: return ["op": "popTransform"]
        }
    }

    @Test func decodesWhatTheRustEncoderWrote() throws {
        let dir = root.appending(path: "web/src/testdata")
        let ops = try DisplayList.decode(Data(contentsOf: dir.appending(path: "display-list.bin")))
        let expected = try JSONDecoder().decode([JSON].self, from: Data(contentsOf: dir.appending(path: "display-list.json")))
        #expect(ops.count == expected.count)
        for (op, want) in zip(ops, expected) {
            #expect(plain(op) == want)
        }
    }

    @Test func closingFindsTheMatchingEndWithEndMaskBetween() {
        let item = DisplayList.Op.beginItem(item: 0, hash: 0)
        let ops: [DisplayList.Op] = [.beginMask, item, .endItem, .endMask, item, .endItem, .popMask]
        #expect(DisplayList.closing(ops, 0) == 3)
        #expect(DisplayList.closing(ops, 3) == 6)
        #expect(DisplayList.closing(ops, 1) == 2)
    }

    @Test func aTruncatedListThrows() {
        #expect(throws: DisplayList.DecodeError.self) { try DisplayList.decode(Data([3, 0, 0, 0])) }
    }

    @MainActor @Test func everyPageOfTheExamplesDecodes() throws {
        for name in ["booklet", "poster"] {
            let e = try Engine.load(example(name))
            let s = try e.snapshot
            for p in s.pages + s.masters {
                let ops = try DisplayList.decode(e.displayList(page: p.id))
                guard case .page = ops.first else { Issue.record("no page op"); continue }
                #expect(ops.count > 1)
            }
        }
    }
}
