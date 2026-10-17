import Foundation
import ImageIO
import Testing

@testable import SatzCore

@MainActor
struct ExportTests {
    @Test func pageRangesNameThePagesThereAre() {
        #expect(Export.pages("", count: 3) == [0, 1, 2])
        #expect(Export.pages("1-3, 5", count: 6) == [0, 1, 2, 4])
        #expect(Export.pages("2–2,1", count: 2) == [0, 1])
        #expect(Export.pages("4", count: 3) == nil)
        #expect(Export.pages("3-1", count: 3) == nil)
        #expect(Export.pages("1,,2", count: 3) == nil)
        #expect(Export.pages("1-2-3", count: 3) == nil)
        #expect(Export.pages("x", count: 3) == nil)
    }

    @Test func aPDFOffTheMainActorHoldsTheChosenPages() async throws {
        let copy = try Engine.load(example("booklet")).copy()
        let files = try await Task.detached {
            try Export.files(copy, format: .pdf, indices: [0, 2, 3], title: "Booklet", ppi: 72)
        }.value
        #expect(files.count == 1)
        let pdf = try #require(CGDataProvider(data: files[0] as CFData).flatMap(CGPDFDocument.init))
        #expect(pdf.numberOfPages == 3)
    }

    @Test func aScreenPresetOverridesThePrintOne() async throws {
        let e = try Engine.load(example("booklet"))
        try e.apply(.setDocument(["preset": .string("x4")]))
        let copy = e.copy()
        let (x4, screen) = try await Task.detached {
            (try Export.files(copy, format: .pdf, indices: [0], title: "B", ppi: 72)[0],
             try Export.files(copy, format: .pdf, indices: [0], title: "B", ppi: 72, preset: .screen)[0])
        }.value
        #expect(String(decoding: x4, as: UTF8.self).contains("OutputIntent"))
        #expect(!String(decoding: screen, as: UTF8.self).contains("OutputIntent"))
    }

    @Test func imagesComeOnePerPageAtTheirResolution() async throws {
        let copy = try Engine.load(example("poster")).copy()
        let files = try await Task.detached {
            try Export.files(copy, format: .jpeg, indices: [0], title: "Poster", ppi: 36)
        }.value
        #expect(files.count == 1)
        let source = try #require(CGImageSourceCreateWithData(files[0] as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == "public.jpeg")
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let page = try Engine.load(example("poster")).snapshot.pages[0]
        #expect(abs(Double(image.width) - page.width / 2) <= 1)
    }

    @Test func aPackageIsAZip() async throws {
        let copy = try Engine.load(example("booklet")).copy()
        let zip = try await Task.detached {
            try Export.files(copy, format: .zip, indices: [0], title: "Booklet", ppi: 72)[0]
        }.value
        #expect(zip.prefix(2) == Data("PK".utf8))
    }

    @Test func theInkPreviewShowsTheShownPagesAndTheWholeDocument() async throws {
        let e = try Engine.load(example("booklet"))
        let s = try e.snapshot
        let printed = s.pages.map { ($0.id, e.printed(page: $0.id)!) }
        let previewer = InkPreviewer()
        var copies = 0
        func run(_ options: InkPreview.Options) async throws -> InkPreview {
            try await withCheckedThrowingContinuation { c in
                previewer.preview({ copies += 1; return e.copy() }, printed: printed, shown: [s.pages[1].id], options: options, limit: s.inkLimit) {
                    c.resume(with: $0)
                }
            }
        }
        let all = try await run(.init())
        #expect(all.sheets.count == 1)
        #expect(all.max.count == 4 + all.spots.count)
        #expect(all.highest > 0)
        let sheet = all.sheets[0]
        #expect(sheet.coverage.count == sheet.width * sheet.height)
        // Over its bleed at 48 ppi.
        let page = s.pages[1]
        #expect(abs(Double(sheet.width) - (page.width + 2 * page.bleed) * 48 / 72) <= 1)
        var none = InkPreview.Options()
        none.on = 0
        let off = try await run(none)
        #expect(copies == 1)
        #expect(off.highest == all.highest)
    }
}
