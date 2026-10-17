import AppKit
import PDFKit
import SatzCore

/// What asks the ink previewer for the inks of the spread on screen, one request at a time.
struct InkRequest {
    var key: [String] = []
    var busy = false
    var again = false
}

extension Editor {
    /// The document's name, which its exports take.
    var title: String {
        let name = (canvas?.window?.windowController?.document as? NSDocument)?.displayName
        return (name?.isEmpty == false ? name! : "Satz").replacing(/\.satz$/, with: "")
    }

    func togglePreflight() {
        showsPreflight.toggle()
        pointerInk = nil
        if showsPreflight {
            showsOverview = false
            previewInks()
        } else {
            previewed = nil
            inkRequest = InkRequest()
        }
    }

    /// Opens the preflight, whose export settings sit at its end.
    func openExport() {
        if !showsPreflight { togglePreflight() }
    }

    /// Asks for the inks of the spread on screen when they may have changed, while the
    /// preflight of a CMYK document is open.
    func previewInks() {
        guard showsPreflight, snapshot.colorMode == .cmyk else {
            if previewed != nil { previewed = nil }
            return
        }
        let shown = lists.map(\.id).filter { id in snapshot.pages.contains { $0.id == id } }
        let key = [engine.version, "\(inks)", "\(snapshot.inkLimit)"] + shown
        guard key != inkRequest.key else { return }
        if inkRequest.busy {
            inkRequest.again = true
            return
        }
        inkRequest.key = key
        inkRequest.busy = true
        let printed = snapshot.pages.compactMap { p in engine.printed(page: p.id).map { (p.id, $0) } }
        inkPreviewer.preview({ engine.copy() }, printed: printed, shown: shown, options: inks, limit: snapshot.inkLimit) { [weak self] result in
            guard let self else { return }
            inkRequest.busy = false
            guard showsPreflight else { return }
            switch result {
            case .success(let p): previewed = p
            case .failure(let error): fail(String(localized: "Could not show the inks: \(error.message)"))
            }
            if inkRequest.again {
                inkRequest.again = false
                previewInks()
            }
        }
    }

    /// The name of `format` as the export button and the status line say it.
    static func name(of format: Export.Format) -> String {
        switch format {
        case .pdf: "PDF"
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .zip: String(localized: "Package")
        }
    }

    /// Asks where to save the pages at `indices` as `format`, then exports them in the background.
    func export(_ format: Export.Format, indices: [Int]) {
        guard !exporting, let window = canvas?.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.type]
        panel.nameFieldStringValue = "\(title).\(format.fileExtension)"
        panel.canCreateDirectories = true
        if format.perPage, indices.count > 1 {
            panel.message = String(localized: "Each page is saved as its own file, numbered after this name.")
        }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { self?.export(format, indices: indices, to: url) }
        }
    }

    /// Exports the pages at `indices` as `format` to `url`; images of several pages go
    /// next to it, numbered.
    func export(_ format: Export.Format, indices: [Int], to url: URL) {
        guard !exporting else { return }
        exporting = true
        let kind = Self.name(of: format)
        say(String(localized: "Exporting \(kind)…"))
        let copy = engine.copy()
        let (title, ppi) = (title, snapshot.rasterPpi)
        let numbered = format.perPage && snapshot.pages.count > 1
        Task {
            do {
                let names = try await Task.detached(priority: .userInitiated) {
                    let files = try Export.files(copy, format: format, indices: indices, title: title, ppi: ppi)
                    return try zip(files, indices).map { data, i in
                        let base = url.deletingPathExtension()
                        let to = numbered ? base.deletingLastPathComponent().appending(path: "\(base.lastPathComponent)-\(i + 1).\(url.pathExtension)") : url
                        try data.write(to: to, options: .atomic)
                        return to.lastPathComponent
                    }
                }.value
                say(names.count > 1 ? String(localized: "Exported \(names.count) pages") : String(localized: "Exported \(names.first ?? "")"))
            } catch {
                fail(String(localized: "Could not export the \(kind): \(error.message)"))
            }
            exporting = false
        }
    }

    /// Prints every page through the Mac's print dialog, from a screen PDF of them.
    func printDocument() {
        guard !exporting, let window = canvas?.window else { return }
        exporting = true
        say(String(localized: "Preparing to print…"))
        let copy = engine.copy()
        let (title, all) = (title, Array(snapshot.pages.indices))
        Task {
            defer { exporting = false }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try Export.files(copy, format: .pdf, indices: all, title: title, ppi: 72, preset: .screen)[0]
                }.value
                guard let pdf = PDFDocument(data: data),
                    let op = pdf.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleToFit, autoRotate: true)
                else { throw EngineError.Failed(message: String(localized: "The PDF does not open")) }
                op.jobTitle = title
                op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
            } catch {
                fail(String(localized: "Could not print: \(error.message)"))
            }
        }
    }

    /// Shows the issue `i`: its page, with its layer selected and in view.
    func show(_ i: Issue) {
        stopEditing()
        pageID = i.page
        select(nodes[i.layer] == nil ? [] : [i.layer])
        canvas?.contentChanged()
        canvas?.zoomToSelection()
    }

    /// The words of the text `id` anywhere in the document that do not fit its thread.
    func oversetWords(of id: String) -> Int {
        for p in snapshot.pages + snapshot.masters {
            if let n = Select.index(p.children, page: p)[id]?.node { return n.kind == .text ? oversetWords(n) : 0 }
        }
        return 0
    }
}
