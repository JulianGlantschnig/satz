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

    nonisolated init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        source = .file(data)
    }

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
        return result
    }

    nonisolated func snapshot(contentType: UTType) throws -> Data {
        try MainActor.assumeIsolated {
            switch editor {
            case .success(let e): e.engine.save()
            case .failure(let error): throw error
            }
        }
    }

    nonisolated func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: snapshot)
    }
}
