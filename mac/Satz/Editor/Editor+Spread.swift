import SatzCore

extension Editor {
    /// The master on screen, if it is one.
    var master: Page? { snapshot.masters.first { $0.id == pageID } }

    /// The pages of the spread on screen; a master stands alone.
    var spread: [Page] {
        guard let pageID else { return [] }
        if let ids = snapshot.spreads.first(where: { $0.contains(pageID) }) {
            return ids.compactMap { id in snapshot.pages.first { $0.id == id } }
        }
        return page.map { [$0] } ?? []
    }

    /// The pages the canvas shows: those of the spread, or with facing pages the left
    /// and right page of the master on screen, which holds the layers of both.
    var sheets: [Sheet] {
        if let m = master, snapshot.facingPages {
            var left = Sheet(m, x: -m.width)
            left.mirrored = true
            return [left, Sheet(m, x: 0)]
        }
        return spread.map { p in Sheet(p, master: p.master.flatMap { snapshot.page($0) }) }
    }

    /// The display lists the canvas draws, by page id, at their x on the spread.
    var lists: [(id: String, x: Double)] {
        if let m = master { return [(m.id, m.x)] }
        return spread.map { ($0.id, $0.x) }
    }

    /// Names the spread on screen and its pages' sizes, for keeping a view per spread.
    var spreadKey: String {
        lists.map(\.id).joined(separator: ",") + "/" + sheets.map { "\($0.width)x\($0.height)" }.joined(separator: ",")
    }

    /// The index of the spread on screen in `snapshot.spreads`, nil on a master.
    var spreadIndex: Int? {
        guard let pageID else { return nil }
        return snapshot.spreads.firstIndex { $0.contains(pageID) }
    }

    /// Shows the spread `index`, clamped to those there are.
    func showSpread(_ index: Int) {
        let spreads = snapshot.spreads
        guard !spreads.isEmpty else { return }
        let i = min(max(index, 0), spreads.count - 1)
        if let first = spreads[i].first { pageID = first }
    }

    func nextSpread() { showSpread((spreadIndex ?? -1) + 1) }
    func previousSpread() { showSpread((spreadIndex ?? 1) - 1) }
    func firstSpread() { showSpread(0) }
    func lastSpread() { showSpread(snapshot.spreads.count - 1) }
}
