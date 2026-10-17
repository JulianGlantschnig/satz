import Foundation
import SatzCore
import Testing

@testable import Satz

@MainActor
struct AutoLayoutTests {
    /// Three rectangles in a row in an auto layout frame.
    func row() throws -> (Editor, frame: Node, kids: [String]) {
        let e = try SatzDocument().editor.get()
        let page = try #require(e.pageID)
        let ids = (0..<3).map { i in
            e.apply(.create(parent: page, kind: .rect, x: Units.mm(10 + 30 * Double(i)), y: Units.mm(10), w: Units.mm(20), h: Units.mm(20)))[0]
        }
        e.select(ids)
        e.addAutoLayout()
        let frame = try #require(e.selected.first)
        #expect(frame.kind == .frame)
        #expect(frame.direction == .horizontal)
        return (e, frame, frame.children?.map(\.id) ?? [])
    }

    @Test func autoLayoutWrapsTheSelectionInAFrameThatLaysItOut() throws {
        let (e, frame, kids) = try row()
        #expect(kids.count == 3)
        #expect(e.nodes[kids[0]].flatMap { e.flow(of: $0.node) }?.id == frame.id)
        e.apply(.set(id: frame.id, ["gap": .number(Units.mm(4))]))
        let a = try #require(e.nodes[kids[0]]?.node)
        let b = try #require(e.nodes[kids[1]]?.node)
        #expect(abs(b.x - (a.x + a.w) - Units.mm(4)) < 0.01)
        e.select([frame.id])
        e.removeAutoLayout()
        #expect(e.nodes[frame.id]?.node.direction == Direction.none)
        #expect(e.nodes[kids[0]].flatMap { e.flow(of: $0.node) } == nil)
    }

    @Test func aDraggedLayerLandsBetweenTheOthers() throws {
        let (e, frame, kids) = try row()
        let f = try #require(e.nodes[frame.id]?.node)
        let (a, b) = (try #require(e.nodes[kids[0]]?.node), try #require(e.nodes[kids[1]]?.node))
        // Between the first and the second, with the third dragged.
        let p = CGPoint(x: a.x + a.w + 1, y: a.y + a.h / 2)
        let i = Editor.insertion(f, [kids[2]], p)
        #expect(i.index == 1)
        #expect(abs(i.line.0.x - (a.x + a.w + b.x) / 2) < 0.01)
        #expect(i.line.0.y == f.y && i.line.1.y == f.y + f.h)
        #expect(e.flowFrame(at: CGPoint(x: f.x + 1, y: f.y + 1), outside: [kids[2]])?.id == frame.id)
        #expect(e.flowFrame(at: CGPoint(x: f.x + 1, y: f.y + 1), outside: [frame.id]) == nil)
        e.apply(.move([kids[2]], parent: frame.id, index: i.index))
        #expect(e.nodes[frame.id]?.node.children?.map(\.id) == [kids[0], kids[2], kids[1]])
    }

    @Test func twoLayersOfAFlowSwapTheirOrder() throws {
        let (e, frame, kids) = try row()
        e.select([frame.id])
        #expect(e.swappable().map(\.id) == kids)
        e.swap(kids[0], kids[2])
        #expect(e.nodes[frame.id]?.node.children?.map(\.id) == [kids[2], kids[1], kids[0]])
    }

    @Test func layersOutsideAFlowSwapTheirPlaces() throws {
        let e = try SatzDocument().editor.get()
        let page = try #require(e.pageID)
        let a = e.apply(.create(parent: page, kind: .rect, x: Units.mm(10), y: Units.mm(10), w: Units.mm(20), h: Units.mm(20)))[0]
        let b = e.apply(.create(parent: page, kind: .ellipse, x: Units.mm(100), y: Units.mm(50), w: Units.mm(30), h: Units.mm(30)))[0]
        e.select([a, b])
        e.swap(a, b)
        let (m, n) = (try #require(e.nodes[a]?.node), try #require(e.nodes[b]?.node))
        #expect(abs(m.x - Units.mm(100)) < 0.01 && abs(m.y - Units.mm(50)) < 0.01)
        #expect(abs(n.x - Units.mm(10)) < 0.01 && abs(n.y - Units.mm(10)) < 0.01)
    }
}
