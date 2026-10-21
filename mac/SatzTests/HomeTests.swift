import Foundation
import SatzCore
import Testing

@testable import Satz

@MainActor
struct HomeTests {
    let base = FileManager.default.temporaryDirectory.appending(path: "home-\(UUID().uuidString)")
    var folder: URL { base.appending(path: "Satz") }

    func library() -> HomeLibrary {
        let defaults = UserDefaults(suiteName: "home-\(UUID().uuidString)")!
        let l = HomeLibrary(defaultFolder: folder, store: base.appending(path: "home.json"), systemRecents: false, defaults: defaults)
        l.reload()
        return l
    }

    /// A document at `url`.
    @discardableResult
    func write(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Engine.blank(width: 100, height: 100, pages: 1, facing: false).save().write(to: url)
        return url.standardizedFileURL
    }

    @Test func theSatzFolderAndItsFoldersHoldTheProjects() throws {
        let l = library()
        try write(folder.appending(path: "a.satz"))
        try write(folder.appending(path: "Kunden/b.satz"))
        try write(base.appending(path: "elsewhere.satz"))
        try "x".write(to: folder.appending(path: "notes.txt"), atomically: true, encoding: .utf8)
        l.reload()
        #expect(l.projects.map(\.name).sorted() == ["a", "b"])
        #expect(l.projects.allSatisfy { $0.inFolder })
        #expect(l.projects.allSatisfy { $0.opened == nil })
    }

    @Test func aFileOpenedElsewhereIsRecentAndFollowsItsMoves() throws {
        let l = library()
        let url = try write(base.appending(path: "Schreibtisch/flyer.satz"))
        l.opened(url)
        var p = try #require(l.projects.first)
        #expect(p.name == "flyer" && p.opened != nil && !p.inFolder)
        let moved = base.appending(path: "Archiv/flyer.satz")
        try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: url, to: moved)
        l.reload()
        p = try #require(l.projects.first)
        #expect(p.url.path == moved.standardizedFileURL.path && p.opened != nil)
        // A file gone vanishes.
        try FileManager.default.removeItem(at: moved)
        l.reload()
        #expect(l.projects.isEmpty)
        // What Satz knew holds after a restart.
        let again = try write(base.appending(path: "b.satz"))
        l.star(again, true)
        let defaults = UserDefaults(suiteName: "home-\(UUID().uuidString)")!
        let next = HomeLibrary(defaultFolder: folder, store: base.appending(path: "home.json"), systemRecents: false, defaults: defaults)
        next.reload()
        #expect(next.projects.map(\.starred) == [true])
    }

    @Test func starsAndCollectionsGoWithTheFile() throws {
        let l = library()
        let url = try write(folder.appending(path: "a.satz"))
        l.reload()
        l.star(url, true)
        let c = l.newCollection("Kunden")
        let d = l.newCollection("2026")
        l.add(url, to: c)
        l.add(url, to: d)
        var p = try #require(l.projects.first)
        #expect(p.starred && p.collections == [c, d])
        l.rename(collection: c, to: "Kundschaft")
        #expect(l.collections.map(\.name) == ["Kundschaft", "2026"])
        l.delete(collection: d)
        p = try #require(l.projects.first)
        #expect(p.collections == [c])
        // Renaming the file keeps them.
        let renamed = try l.rename(url, to: "Plakat")
        p = try #require(l.projects.first)
        #expect(renamed.lastPathComponent == "Plakat.satz" && p.name == "Plakat" && p.starred && p.collections == [c])
        #expect(throws: (any Error).self) { try l.rename(renamed, to: "a/b") }
        l.remove(renamed, from: c)
        l.star(renamed, false)
        p = try #require(l.projects.first)
        #expect(!p.starred && p.collections.isEmpty)
    }

    @Test func aDuplicateLiesBesideItsFile() throws {
        let l = library()
        let url = try write(folder.appending(path: "a.satz"))
        let copy = try l.duplicate(url)
        let second = try l.duplicate(url)
        #expect(copy.lastPathComponent == "a copy.satz" || copy.lastPathComponent == "a Kopie.satz")
        #expect(second.deletingPathExtension().lastPathComponent.hasSuffix(" 2"))
        #expect(l.projects.count == 3)
    }

    @Test func theTrashKeepsFilesFor30DaysAndPutsThemBack() throws {
        let l = library()
        let inside = try write(folder.appending(path: "a.satz"))
        let outside = try write(base.appending(path: "Schreibtisch/b.satz"))
        l.opened(outside)
        l.star(inside, true)
        try l.trash(inside)
        try l.trash(outside)
        #expect(l.projects.isEmpty)
        #expect(l.trashed.map(\.name).sorted() == ["a", "b"])
        #expect(!FileManager.default.fileExists(atPath: inside.path))
        // A file of the name came since: the old one goes beside it, with its star.
        try write(inside)
        let a = try #require(l.trashed.first { $0.name == "a" })
        let back = try l.restore(a)
        #expect(back.lastPathComponent == "a 2.satz")
        #expect(l.projects.first { $0.url == back }?.starred == true)
        // From outside the Satz folder it goes back there.
        let b = try #require(l.trashed.first { $0.name == "b" })
        let restored = try l.restore(b)
        #expect(restored.path == outside.path)
        // After 30 days it is deleted.
        try l.trash(outside)
        let file = l.trashFolder.appending(path: try #require(l.trashed.first).file)
        l.now = { Date().addingTimeInterval(31 * 86400) }
        l.reload()
        #expect(l.trashed.isEmpty && !FileManager.default.fileExists(atPath: file.path))
        try l.trash(back)
        try l.deleteForever(try #require(l.trashed.first))
        #expect(l.trashed.isEmpty)
        try l.trash(inside)
        l.emptyTrash()
        #expect(l.trashed.isEmpty && l.projects.isEmpty)
    }

    @Test func theSatzFolderIsChosen() throws {
        let l = library()
        let other = base.appending(path: "Andere")
        try write(other.appending(path: "c.satz"))
        l.folder = other
        #expect(l.projects.map(\.name) == ["c"])
        #expect(l.trashFolder.path.hasPrefix(other.path))
    }
}
