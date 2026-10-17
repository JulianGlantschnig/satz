import Foundation
import SatzCore

/// What the canvas and the page thumbnails draw from: the decoded display lists of the
/// pages and masters, their fonts and images, and the CMYK ink table; one per document.
@MainActor
final class SceneSource {
    private let engine: Engine
    let resources = Resources()
    private(set) lazy var painter = Painter(resources: resources)

    /// Decoded display lists by page id, with their version.
    private var decoded: [String: (version: UInt32, ops: [DisplayList.Op], plates: (cmy: [DisplayList.Op], k: [DisplayList.Op])?)] = [:]
    private var inkTable: InkTable?
    private var inkProfile: String??
    private var listeners: [UUID: () -> Void] = [:]

    init(engine: Engine) {
        self.engine = engine
        resources.decoded = { [weak self] in
            self?.listeners.values.forEach { $0() }
        }
    }

    /// Runs `run` whenever an image has decoded, until the returned token goes.
    func onImagesDecoded(_ run: @escaping () -> Void) -> UUID {
        let id = UUID()
        listeners[id] = run
        return id
    }

    func stopListening(_ id: UUID) { listeners[id] = nil }

    /// The scene of the display lists `lists` at their x on the spread over `sheets`.
    func scene(
        _ snapshot: Snapshot, lists: [(id: String, x: Double)], sheets: [Sheet], pasteboard: Bool,
        on: SIMD4<Float> = SIMD4(repeating: 1)
    ) -> CanvasScene {
        let cmyk = snapshot.colorMode == .cmyk
        if !cmyk {
            inkTable = nil
            inkProfile = nil
        } else if inkTable == nil || inkProfile != .some(snapshot.profile) {
            inkTable = InkTable(pixels: engine.lut(), id: Int.random(in: 1...Int.max))
            if inkProfile != nil { resources.forgetImages() }
            inkProfile = .some(snapshot.profile)
        }
        let out: [CanvasScene.List] = lists.map { item in
            let version = engine.listVersion(page: item.id)
            if let d = decoded[item.id], d.version == version, (d.plates != nil) == cmyk {
                return CanvasScene.List(id: item.id, x: item.x, version: version, ops: d.ops, plates: d.plates)
            }
            let ops = (try? DisplayList.decode(engine.displayList(page: item.id))) ?? []
            var plates: (cmy: [DisplayList.Op], k: [DisplayList.Op])?
            if cmyk {
                plates = (
                    (try? DisplayList.decode(engine.plate(page: item.id, k: false))) ?? [],
                    (try? DisplayList.decode(engine.plate(page: item.id, k: true))) ?? []
                )
            }
            decoded[item.id] = (version, ops, plates)
            resources.prepare(ops)
            if let plates { resources.prepare(plates.cmy + plates.k) }
            return CanvasScene.List(id: item.id, x: item.x, version: version, ops: ops, plates: plates)
        }
        let live = Set((snapshot.pages + snapshot.masters).map(\.id))
        decoded = decoded.filter { live.contains($0.key) }
        return CanvasScene(lists: out, sheets: sheets, pasteboard: pasteboard, lut: inkTable, on: on)
    }
}
