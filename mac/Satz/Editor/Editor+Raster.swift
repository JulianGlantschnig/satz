import Foundation
import SatzCore

/// Rasters on pages: a locked group "Raster" under everything else of a page, made from
/// `RasterGrid.Spec`, which it keeps to be edited again.
extension Editor {
    enum RasterTarget: String, CaseIterable, Identifiable {
        case page, pages, master
        var id: Self { self }

        var title: LocalizedStringResource {
            switch self {
            case .page: "Current Page"
            case .pages: "All Pages"
            case .master: "Master Page"
            }
        }
    }

    /// The raster group of the page or master `id`.
    func raster(on id: String) -> Node? {
        snapshot.page(id)?.children.first { $0.raster != nil }
    }

    /// The raster of the current page, its master's when the page has none.
    var currentRaster: RasterGrid.Spec? {
        guard let page else { return nil }
        let node = raster(on: page.id) ?? page.master.flatMap { raster(on: $0) }
        return node?.raster.flatMap(RasterGrid.Spec.from(json:))
    }

    /// The pages or master that `target` reaches from the current page.
    func sheets(_ target: RasterTarget) -> [Page] {
        guard let page else { return [] }
        switch target {
        case .page: return [page]
        case .pages: return snapshot.pages
        case .master:
            if isMaster { return [page] }
            return page.master.flatMap { snapshot.page($0) }.map { [$0] } ?? []
        }
    }

    /// Puts the raster of `spec` on the sheets of `target`, in place of the rasters there.
    func applyRaster(_ spec: RasterGrid.Spec, to target: RasterTarget) {
        let sheets = sheets(target)
        guard !sheets.isEmpty else {
            fail(String(localized: "This page has no master page"))
            return
        }
        batch {
            for sheet in sheets {
                let master = snapshot.masters.contains { $0.id == sheet.id }
                if master && snapshot.facingPages {
                    // A master spread: its left page lies left of 0, its right one from 0 on.
                    placeRaster(spec, on: sheet, x: -sheet.width, mirrored: true)
                    placeRaster(spec, on: sheet, x: 0, mirrored: false, replace: false)
                } else {
                    placeRaster(spec, on: sheet, x: 0, mirrored: sheet.side == .left)
                }
            }
        }
        say(String(localized: "Raster applied to \(sheets.count) pages"))
    }

    /// Removes the rasters of the sheets of `target`.
    func removeRaster(from target: RasterTarget) {
        let ids = sheets(target).flatMap { s in s.children.filter { $0.raster != nil }.map(\.id) }
        guard !ids.isEmpty else { return }
        apply(.delete(ids))
    }

    private func placeRaster(_ spec: RasterGrid.Spec, on sheet: Page, x: Double, mirrored: Bool, replace: Bool = true) {
        if replace {
            let old = sheet.children.filter { $0.raster != nil }.map(\.id)
            if !old.isEmpty { apply(.delete(old)) }
        }
        let pt = Units.ptPerMM
        let (left, right) = mirrored ? (spec.marginRight, spec.marginLeft) : (spec.marginLeft, spec.marginRight)
        let w = sheet.width / pt - left - right, h = sheet.height / pt - spec.marginTop - spec.marginBottom
        guard w > 0, h > 0 else {
            fail(String(localized: "The margins leave no room for the raster"))
            return
        }
        let drawing = RasterGrid.build(spec, width: w, height: h, mirrored: mirrored)
        let (ox, oy) = (x + left * pt, spec.marginTop * pt)
        let mode = snapshot.colorMode
        func color(_ hex: String) -> SatzCore.Color {
            ColorMath.fromRGB(ColorMath.parseHex(hex) ?? 0, like: .black, mode: mode)
        }
        guard let area = apply(.create(parent: sheet.id, kind: .frame, x: ox, y: oy, w: w * pt, h: h * pt)).first else { return }
        apply(.set(id: area, ["clip": .bool(true), "fills": .array([]), "name": .string(String(localized: "Raster area"))]))
        var inside: [String] = [], outside: [String] = []
        for s in drawing.strokes where !s.path.isEmpty {
            var path = s.path
            var i = 0
            while i < path.count {
                let n = path[i] == 4 ? 3 : path[i] == 5 ? 0 : 1
                for k in 0..<n {
                    path[i + 1 + 2 * k] = ox + path[i + 1 + 2 * k] * pt
                    path[i + 2 + 2 * k] = oy + path[i + 2 + 2 * k] * pt
                }
                i += 1 + 2 * n
            }
            guard let id = apply(.create(parent: sheet.id, kind: .path, x: ox, y: oy, w: 0, h: 0)).first else { continue }
            apply(.setPath(id: id, path: path))
            let paint = (try? JSON(encoding: [Fill.solid(color(s.color))])) ?? .array([])
            if s.filled {
                apply(.set(id: id, ["fills": paint, "strokes": .array([])]))
            } else {
                apply(.set(id: id, [
                    "fills": .array([]), "strokes": paint, "strokeWeight": .number(s.weight * pt),
                    "lineStyle": .string(s.style.rawValue), "strokeAlign": .string("center"),
                ]))
            }
            if s.clipped { inside.append(id) } else { outside.append(id) }
        }
        if !inside.isEmpty { apply(.move(inside, parent: area, index: 0)) }
        for label in drawing.labels {
            guard let id = apply(.create(parent: sheet.id, kind: .text, x: 0, y: 0, w: 0, h: 0)).first else { continue }
            apply(.setText(id: id, text: label.text))
            var attrs: [String: JSON] = [
                "size": .number(label.size),
                "fills": (try? JSON(encoding: [Fill.solid(color(label.color))])) ?? .array([]),
            ]
            if let font = spec.headerFont, let json = try? JSON(encoding: font) { attrs["font"] = json }
            apply(.format(id: id, range: nil, attrs))
            guard let n = nodes[id]?.node else { continue }
            let lx = ox + label.x * pt
            let left = switch label.anchor {
            case .start: lx
            case .middle: lx - n.w / 2
            case .end: lx - n.w
            }
            // The baseline sits about 0.8 of the size below the top of the line.
            apply(.setFrame(id: id, x: left, y: oy + label.y * pt - label.size * 0.8, w: n.w, h: n.h))
            outside.append(id)
        }
        guard let group = apply(.group([area] + outside, frame: false)).first else { return }
        apply(.set(id: group, [
            "name": .string(String(localized: "Raster")), "locked": .bool(true),
            "nonprinting": .bool(!spec.prints), "raster": .string(spec.json),
        ]))
        apply(.order([group], to: .back))
    }
}
