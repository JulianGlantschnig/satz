import Foundation
import SatzCore

/// Pages, masters and sections; see `web/src/editor.ts` and `web/src/Overview.tsx`.
extension Editor {
    /// Deletes the pages `ids`, keeping at least one, and shows the page after them.
    func deletePages(_ ids: [String]) {
        let all = snapshot.pages.map(\.id)
        let del = ids.filter { all.contains($0) }
        guard !del.isEmpty else { return }
        guard del.count < all.count else {
            fail(String(localized: "A document keeps at least 1 page"))
            return
        }
        let numbers = del.compactMap { all.firstIndex(of: $0) }.map { $0 + 1 }
        let first = (numbers.min() ?? 1) - 1
        let next = all.enumerated().first { !del.contains($0.element) && $0.offset >= first }?.element ?? all.last { !del.contains($0) }
        batch {
            for id in del { apply(.deletePage(id)) }
        }
        if let next {
            if del.contains(pageID ?? "") { showPage(next) }
            if showsOverview { overviewSelection = [next] }
        }
        say(del.count == 1 ? String(localized: "Deleted page \(numbers[0])") : String(localized: "Deleted \(del.count) pages"))
    }

    /// Moves the pages `ids` to `index` among the others.
    func movePages(_ ids: [String], to index: Int) {
        apply(.movePages(ids, index: index))
    }

    /// Makes a master like the page or master `like`, with its layers when asked, and opens it.
    func addMaster(like: String?, layers: Bool = false) {
        if let id = apply(.addMaster(like: like, layers: layers)).first {
            showPage(id)
            showsOverview = false
        }
    }

    func renameMaster(_ id: String, _ name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        apply(.setMaster(id, name: name))
    }

    func deleteMasters(_ ids: [String]) {
        batch {
            for id in ids { apply(.deleteMaster(id)) }
        }
    }

    /// Gives the pages `pages` the master `master`, or none.
    func useMaster(_ master: String?, on pages: [String]) {
        batch {
            for p in pages { apply(.useMaster(page: p, master: master)) }
        }
    }

    /// Leaves the master on screen for the first page that uses it, or the first page.
    func exitMaster() {
        guard let m = master else { return }
        showPage(snapshot.pages.first { $0.master == m.id }?.id ?? snapshot.pages.first?.id ?? m.id)
    }

    /// The letters that the page numbers of the master `name` show.
    func prefix(_ name: String) -> String { masterPrefix(name) }

    /// Opens the page overview with the current page picked, or closes it.
    func toggleOverview() {
        stopEditing()
        showsOverview.toggle()
        if showsOverview { overviewSelection = pageID.map { [$0] } ?? [] }
    }

    /// Overrides the master layer `id` on the page `page` and selects the copy.
    func override(_ id: String, on page: String) {
        select(apply(.override(page: page, id: id)))
    }
}
