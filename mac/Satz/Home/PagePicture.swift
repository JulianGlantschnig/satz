import ImageIO
import SatzCore
import SwiftUI

/// A picture of the first page of the `.satz` file at `url`, made off the main thread and
/// kept while the file stays as it is. White paper shows until it is made.
struct PagePicture: View {
    let url: URL
    /// The picture's resolution; it shows at half of it, for Retina screens.
    var ppi = 20.0

    @State private var picture: CGImage?

    /// Pictures already made, by file, date and resolution.
    @MainActor private static var made: [String: CGImage] = [:]

    var body: some View {
        Group {
            if let picture {
                Image(decorative: picture, scale: 2).resizable().aspectRatio(contentMode: .fit)
            } else {
                Rectangle().fill(.white).aspectRatio(210.0 / 297, contentMode: .fit)
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
        .task(id: key) {
            if let made = Self.made[key] {
                picture = made
                return
            }
            let (url, ppi) = (url, ppi)
            // Each picture is made from the file on a thread of its own.
            let image = await Task.detached(priority: .utility) { () -> CGImage? in
                guard let data = try? Data(contentsOf: url),
                    let png = try? Export.files(DocumentCopy(bytes: data), format: .png, indices: [0], title: "", ppi: ppi).first,
                    let source = CGImageSourceCreateWithData(png as CFData, nil)
                else { return nil }
                return CGImageSourceCreateImageAtIndex(source, 0, nil)
            }.value
            if let image {
                if Self.made.count > 400 { Self.made.removeAll() }
                Self.made[key] = image
                picture = image
            }
        }
    }

    private var key: String {
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return "\(url.path)|\(date?.timeIntervalSince1970 ?? 0)|\(ppi)"
    }
}
