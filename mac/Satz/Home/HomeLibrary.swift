import AppKit
import Observation

/// The documents the home window shows: the `.satz` files in the Satz folder, those opened
/// lately anywhere, the starred ones and the collections, which are only Satz's. Files
/// deleted here wait in a trash of Satz's own in the Satz folder for 30 days.
@MainActor
@Observable
final class HomeLibrary {
    static let folderKey = "homeFolder"
    static let trashName = ".satz-papierkorb"
    static let trashDays = 30.0

    /// The app's library. The UI tests keep theirs in a folder of their own, `SATZ_HOME`.
    static let shared: HomeLibrary = {
        if let base = ProcessInfo.processInfo.environment["SATZ_HOME"] {
            let url = URL(fileURLWithPath: base)
            return HomeLibrary(defaultFolder: url.appending(path: "Satz"), store: url.appending(path: "home.json"), systemRecents: false)
        }
        let support = URL.applicationSupportDirectory.appending(path: "Satz")
        return HomeLibrary(defaultFolder: URL.documentsDirectory.appending(path: "Satz"), store: support.appending(path: "home.json"), systemRecents: true)
    }()

    struct Project: Identifiable, Hashable {
        var url: URL
        var edited: Date
        /// When it was opened last, if it was.
        var opened: Date?
        var starred: Bool
        var collections: Set<UUID>
        /// Whether it lies in the Satz folder.
        var inFolder: Bool

        var id: String { url.path }
        var name: String { url.deletingPathExtension().lastPathComponent }
    }

    struct Collection: Codable, Identifiable, Hashable {
        var id = UUID()
        var name: String
    }

    /// A file in the trash: `file` is its name there, `original` where it was.
    struct Trashed: Codable, Identifiable, Hashable {
        var file: String
        var original: String
        var date: Date
        var starred = false
        var collections: Set<UUID> = []

        var id: String { file }
        var name: String { URL(fileURLWithPath: original).deletingPathExtension().lastPathComponent }
    }

    /// What Satz knows of a file beyond the file itself.
    private struct Entry: Codable {
        var path: String
        var bookmark: Data?
        var opened: Date?
        var starred = false
        var collections: Set<UUID> = []

        var isEmpty: Bool { opened == nil && !starred && collections.isEmpty }
    }

    private struct Store: Codable {
        var entries: [Entry] = []
        var collections: [Collection] = []
        var trashed: [Trashed] = []
    }

    let defaultFolder: URL
    let storeURL: URL
    /// Whether the documents macOS lists as recent count as opened.
    let systemRecents: Bool
    /// Where the chosen Satz folder is kept.
    let defaults: UserDefaults
    /// The time, which the tests set.
    var now: () -> Date = Date.init

    private var store = Store()
    private(set) var projects: [Project] = []
    private(set) var collections: [Collection] = []
    private(set) var trashed: [Trashed] = []

    init(defaultFolder: URL, store: URL, systemRecents: Bool, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.defaultFolder = defaultFolder
        self.storeURL = store
        self.systemRecents = systemRecents
        if let data = try? Data(contentsOf: store), let s = try? JSONDecoder().decode(Store.self, from: data) {
            self.store = s
        }
    }

    /// The Satz folder: the one of the settings, else Documents/Satz.
    var folder: URL {
        get {
            defaults.string(forKey: Self.folderKey).map { URL(fileURLWithPath: $0, isDirectory: true) } ?? defaultFolder
        }
        set {
            defaults.set(newValue.path, forKey: Self.folderKey)
            reload()
        }
    }

    var trashFolder: URL { folder.appending(path: Self.trashName, directoryHint: .isDirectory) }

    // MARK: Reading

    /// Reads the files again: the Satz folder, the files Satz knows and those macOS lists as
    /// recent. Files gone vanish, files moved are found by their bookmarks, and the trash
    /// drops what waited longer than 30 days.
    func reload() {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        purge()

        var entries: [Entry] = []
        for var e in store.entries {
            guard let url = resolve(&e) else { continue }
            e.path = url.path
            if !entries.contains(where: { $0.path == e.path }) { entries.append(e) }
        }
        store.entries = entries
        let known = Set(store.collections.map(\.id))
        for i in store.entries.indices { store.entries[i].collections.formIntersection(known) }

        var urls = scan()
        let recents = systemRecents ? NSDocumentController.shared.recentDocumentURLs.filter { $0.pathExtension == "satz" } : []
        for url in store.entries.map({ URL(fileURLWithPath: $0.path) }) + recents where !urls.contains(url.standardizedFileURL) {
            if fm.fileExists(atPath: url.path), !url.path.hasPrefix(trashFolder.path + "/") { urls.append(url.standardizedFileURL) }
        }
        let inFolder = folder.standardizedFileURL.path + "/"
        let recentPaths = Set(recents.map(\.standardizedFileURL.path))
        projects = urls.map { url in
            let e = store.entries.first { $0.path == url.path }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .contentAccessDateKey])
            let opened = e?.opened ?? (recentPaths.contains(url.path) ? values?.contentAccessDate : nil)
            return Project(
                url: url, edited: values?.contentModificationDate ?? .distantPast, opened: opened,
                starred: e?.starred ?? false, collections: e?.collections ?? [], inFolder: url.path.hasPrefix(inFolder))
        }
        collections = store.collections
        trashed = store.trashed.sorted { $0.date > $1.date }
        save()
    }

    /// The `.satz` files in the Satz folder and its folders, not in the trash.
    private func scan() -> [URL] {
        guard
            let walk = FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }
        return walk.compactMap { $0 as? URL }.filter { $0.pathExtension == "satz" }.map(\.standardizedFileURL)
    }

    /// Where the file of `e` is now, following its bookmark, or nil when it is gone.
    private func resolve(_ e: inout Entry) -> URL? {
        if let data = e.bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &stale),
                FileManager.default.fileExists(atPath: url.path), !url.path.hasPrefix(trashFolder.path + "/")
            {
                if stale { e.bookmark = try? url.bookmarkData() }
                return url.standardizedFileURL
            }
        }
        guard FileManager.default.fileExists(atPath: e.path) else { return nil }
        let url = URL(fileURLWithPath: e.path).standardizedFileURL
        e.bookmark = try? url.bookmarkData()
        return url
    }

    private func save() {
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(store).write(to: storeURL, options: .atomic)
    }

    // MARK: Changes

    /// Changes what Satz knows of the file at `url`.
    private func change(_ url: URL, _ edit: (inout Entry) -> Void) {
        let path = url.standardizedFileURL.path
        if let i = store.entries.firstIndex(where: { $0.path == path }) {
            edit(&store.entries[i])
            if store.entries[i].isEmpty { store.entries.remove(at: i) }
        } else {
            var e = Entry(path: path, bookmark: try? url.bookmarkData())
            edit(&e)
            if !e.isEmpty { store.entries.append(e) }
        }
        reload()
    }

    /// Notes that the document at `url` was opened now.
    func opened(_ url: URL) {
        change(url) { $0.opened = now() }
    }

    func star(_ url: URL, _ on: Bool) {
        change(url) { $0.starred = on }
    }

    func add(_ url: URL, to collection: UUID) {
        change(url) { _ = $0.collections.insert(collection) }
    }

    func remove(_ url: URL, from collection: UUID) {
        change(url) { _ = $0.collections.remove(collection) }
    }

    @discardableResult
    func newCollection(_ name: String) -> UUID {
        let c = Collection(name: name)
        store.collections.append(c)
        reload()
        return c.id
    }

    func rename(collection id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let i = store.collections.firstIndex(where: { $0.id == id }) else { return }
        store.collections[i].name = name
        reload()
    }

    func delete(collection id: UUID) {
        store.collections.removeAll { $0.id == id }
        for i in store.entries.indices { store.entries[i].collections.remove(id) }
        store.entries.removeAll { $0.isEmpty }
        reload()
    }

    /// Renames the file at `url` beside itself; what Satz knows of it moves along.
    @discardableResult
    func rename(_ url: URL, to name: String) throws -> URL {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != url.deletingPathExtension().lastPathComponent else { return url }
        guard !name.contains("/"), !name.hasPrefix(".") else { throw CocoaError(.fileWriteInvalidFileName) }
        let target = url.deletingLastPathComponent().appending(path: name).appendingPathExtension("satz")
        guard !FileManager.default.fileExists(atPath: target.path) else { throw CocoaError(.fileWriteFileExists) }
        try FileManager.default.moveItem(at: url, to: target)
        move(url, to: target)
        reload()
        return target
    }

    /// A copy of the file at `url` beside it, "Name copy".
    @discardableResult
    func duplicate(_ url: URL) throws -> URL {
        let base = url.deletingPathExtension().lastPathComponent + " " + String(localized: "copy")
        let target = free(url.deletingLastPathComponent(), base, "satz")
        try FileManager.default.copyItem(at: url, to: target)
        reload()
        return target
    }

    /// Moves the file at `url` into the trash, with its star and collections.
    func trash(_ url: URL) throws {
        try FileManager.default.createDirectory(at: trashFolder, withIntermediateDirectories: true)
        let file = UUID().uuidString + "-" + url.lastPathComponent
        try FileManager.default.moveItem(at: url, to: trashFolder.appending(path: file))
        let path = url.standardizedFileURL.path
        let e = store.entries.first { $0.path == path }
        store.entries.removeAll { $0.path == path }
        store.trashed.append(Trashed(file: file, original: path, date: now(), starred: e?.starred ?? false, collections: e?.collections ?? []))
        reload()
    }

    /// Puts the file back where it was, beside a file of its name if one came since.
    @discardableResult
    func restore(_ t: Trashed) throws -> URL {
        let original = URL(fileURLWithPath: t.original)
        let dir = original.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = free(dir, original.deletingPathExtension().lastPathComponent, original.pathExtension)
        try FileManager.default.moveItem(at: trashFolder.appending(path: t.file), to: target)
        store.trashed.removeAll { $0.file == t.file }
        let e = Entry(path: target.path, bookmark: try? target.bookmarkData(), starred: t.starred, collections: t.collections)
        if !e.isEmpty { store.entries.append(e) }
        reload()
        return target
    }

    func deleteForever(_ t: Trashed) throws {
        let url = trashFolder.appending(path: t.file)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        store.trashed.removeAll { $0.file == t.file }
        reload()
    }

    func emptyTrash() {
        for t in store.trashed { try? FileManager.default.removeItem(at: trashFolder.appending(path: t.file)) }
        store.trashed = []
        reload()
    }

    /// Deletes what waited in the trash longer than 30 days, and forgets files gone from it.
    private func purge() {
        let limit = now().addingTimeInterval(-Self.trashDays * 86400)
        store.trashed.removeAll { t in
            let url = trashFolder.appending(path: t.file)
            if t.date < limit { try? FileManager.default.removeItem(at: url) }
            return t.date < limit || !FileManager.default.fileExists(atPath: url.path)
        }
    }

    private func move(_ from: URL, to: URL) {
        let path = from.standardizedFileURL.path
        guard let i = store.entries.firstIndex(where: { $0.path == path }) else { return }
        store.entries[i].path = to.standardizedFileURL.path
        store.entries[i].bookmark = try? to.bookmarkData()
    }

    /// `dir/name.ext`, or `name 2.ext` and on while that is taken.
    private func free(_ dir: URL, _ name: String, _ ext: String) -> URL {
        var url = dir.appending(path: name).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appending(path: "\(name) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return url
    }
}
