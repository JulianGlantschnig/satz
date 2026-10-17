import SwiftUI

/// The look of Satz: a flat, compact panel in the native Mac idiom, the page the only
/// thing with colour; see the design notes in `mac/README.md`.
enum Theme {
    /// Labels, field prefixes and section headers.
    static let small: CGFloat = 11
    static let rowHeight: CGFloat = 22
    static let inset: CGFloat = 12

    /// Around the pages: a neutral grey that keeps paper and colours true.
    static var pasteboard: NSColor {
        NSColor(name: "pasteboard") { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.094, green: 0.094, blue: 0.102, alpha: 1)
                : NSColor(srgbRed: 0.804, green: 0.804, blue: 0.816, alpha: 1)
        }
    }
}

/// A scrolling column of panel sections divided by hairlines, in place of a grouped form.
struct Panel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.controlSize, .small)
            .font(.system(size: Theme.small))
            .pickerStyle(.menu)
        }
    }
}

/// One section of a panel: a small header and its rows, with a hairline under it. It takes
/// the initializers of `Section`, so that inspector code reads the same.
struct PanelSection<Content: View, Header: View>: View {
    let content: Content
    let header: Header?

    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) {
        self.content = content()
        self.header = header()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let header {
                header
                    .font(.system(size: Theme.small, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            content
        }
        .padding(.horizontal, Theme.inset)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Divider() }
    }
}

extension PanelSection where Header == Text {
    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.header = Text(title)
    }

    init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.header = Text(title)
    }
}

extension PanelSection where Header == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
        self.header = nil
    }
}
