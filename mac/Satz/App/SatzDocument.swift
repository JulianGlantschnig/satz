import SatzCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    nonisolated static let satz = UTType(exportedAs: "com.julianglantschnig.satz.document")
}

/// A `.satz` file. The engine keeps a document on the thread that made it, and
/// SwiftUI may read files off the main thread, so the file's bytes wait here until
/// the window asks for its editor on the main actor.
final class SatzDocument: ReferenceFileDocument {
    nonisolated static var readableContentTypes: [UTType] { [.satz] }

    private enum Source {
        case blank
        case file(Data)
    }

    private nonisolated let source: Source
    @MainActor private var made: Result<Editor, Error>?

    /// A new document: one A4 page.
    nonisolated init() {
        source = .blank
    }

    /// A new document from the bytes of a `.satz` file, such as an example's.
    nonisolated init(data: Data) {
        source = .file(data)
    }

    nonisolated init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        source = .file(data)
    }

    /// The bytes of the document as last saved on the main actor, for saves that AppKit
    /// runs on another thread while the main thread may wait for them.
    private final class Saved: @unchecked Sendable {
        private let lock = NSLock()
        private var data: Data?

        var value: Data? { lock.withLock { data } }
        func store(_ d: Data) { lock.withLock { data = d } }
    }

    private nonisolated let saved = Saved()
    @MainActor private var pending: Task<Void, Never>?

    /// The document's editor, or why its file does not open.
    @MainActor var editor: Result<Editor, Error> {
        if let made { return made }
        let result = Result<Editor, Error> {
            switch source {
            case .blank:
                Editor(engine: .blank(width: Units.a4.width, height: Units.a4.height, pages: 1, facing: false))
            case .file(let data):
                Editor(engine: try .load(data))
            }
        }
        made = result
        if case .success(let e) = result {
            saved.store(e.engine.save())
            // Kept fresh a moment after each change, so that a save off the main thread finds it.
            e.changed = { [weak self] in
                guard let self else { return }
                pending?.cancel()
                pending = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    _ = try? self.save()
                }
            }
        }
        return result
    }

    /// Saves the document's bytes now, on the main actor.
    @MainActor private func save() throws -> Data {
        switch editor {
        case .success(let e):
            let data = e.engine.save()
            saved.store(data)
            return data
        case .failure(let error):
            throw error
        }
    }

    /// AppKit asks on the main thread or, for autosaves, on another; the engine only works
    /// on the main thread. Off it, the main thread saves when it can, and if it is waiting for
    /// this save the bytes of the last change serve.
    nonisolated func snapshot(contentType: UTType) throws -> Data {
        if Thread.isMainThread {
            return try MainActor.assumeIsolated { try save() }
        }
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            MainActor.assumeIsolated { _ = try? self.save() }
            done.signal()
        }
        _ = done.wait(timeout: .now() + 2)
        guard let data = saved.value else { throw CocoaError(.fileWriteUnknown) }
        return data
    }

    nonisolated func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: snapshot)
    }
}
