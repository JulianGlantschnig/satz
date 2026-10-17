import Foundation
import SatzCore
import Testing

@testable import Satz

@MainActor
struct ExportTests {
    func booklet() throws -> Editor {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "examples/booklet.satz")
        return Editor(engine: try .load(Data(contentsOf: url)))
    }

    func waitUntil(_ done: () -> Bool) async {
        for _ in 0..<600 where !done() { try? await Task.sleep(for: .milliseconds(50)) }
    }

    @Test func imagesOfSeveralPagesGoNextToTheChosenFileNumbered() async throws {
        let e = try booklet()
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        e.apply(.setDocument(["rasterPpi": .number(36)]))
        e.export(.png, indices: [0, 2], to: dir.appending(path: "Booklet.png"))
        #expect(e.exporting)
        await waitUntil { !e.exporting }
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(names == ["Booklet-1.png", "Booklet-3.png"])
        #expect(e.status?.error == false)
    }

    @Test func aPDFGoesWhereItWasAskedTo() async throws {
        let e = try booklet()
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        e.export(.pdf, indices: [0], to: url)
        await waitUntil { !e.exporting }
        #expect(try Data(contentsOf: url).prefix(5) == Data("%PDF-".utf8))
    }

    @Test func thePreflightShowsTheInksOfTheSpreadAndFollowsThePlates() async throws {
        let e = try booklet()
        e.togglePreflight()
        await waitUntil { e.previewed != nil }
        let first = try #require(e.previewed)
        #expect(first.sheets.map(\.page) == e.spread.map(\.id))
        e.inks.on = 0b1000
        await waitUntil { e.previewed.map { $0.sheets.first?.image !== first.sheets.first?.image } ?? false }
        #expect(e.previewed?.highest == first.highest)
        e.togglePreflight()
        #expect(e.previewed == nil)
    }

    @Test func anIssueShowsItsPageAndSelectsItsLayer() throws {
        let e = try booklet()
        let page = try #require(e.snapshot.pages.last)
        let text = try #require(e.apply(.create(parent: page.id, kind: .text, x: 20, y: 20, w: 40, h: 10)).first)
        e.apply(.set(id: text, ["sizing": ["horizontal": "fixed", "vertical": "fixed"]]))
        e.apply(.setText(id: text, text: String(repeating: "Lorem ipsum dolor sit amet ", count: 40)))
        let issue = try #require(e.snapshot.preflight.first { $0.layer == text && $0.problem == .overset })
        e.showPage(e.snapshot.pages[0].id)
        e.show(issue)
        #expect(e.pageID == page.id)
        #expect(e.selection == [text])
        #expect(e.oversetWords(of: text) > 0)
    }
}
