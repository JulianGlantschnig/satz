import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The home window: the documents in the Satz folder, those opened lately, the starred ones,
/// the collections and the trash, as pictures of their first pages or as a list.
struct HomeView: View {
    static let id = "home"

    enum Place: Hashable {
        case recent, all, starred, trash
        case collection(UUID)
    }

    enum Sort: String, CaseIterable, Identifiable {
        case edited, opened, name
        var id: Self { self }
        var title: LocalizedStringKey {
            switch self {
            case .edited: "Last Edited"
            case .opened: "Last Opened"
            case .name: "Name"
            }
        }
    }

    @State private var library = HomeLibrary.shared
    @State private var place: Place? = .recent
    @AppStorage("homeSort") private var sort = Sort.edited
    @AppStorage("homeList") private var asList = false
    @State private var search = ""
    @State private var selection: Set<String> = []
    @State private var renaming: String?
    @State private var renamingCollection: UUID?
    @State private var failure: String?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 280)
        } detail: {
            detail
                .navigationTitle("Home")
                .navigationSubtitle(title)
                .toolbar { toolbar }
                .searchable(text: $search, placement: .toolbar, prompt: Text("Search"))
        }
        .frame(minWidth: 760, minHeight: 480)
        .onAppear(perform: library.reload)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in library.reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in library.reload() }
        .onChange(of: place) {
            selection = []
            renaming = nil
        }
        .alert("The file could not be changed", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
        } message: {
            Text(failure ?? "")
        }
    }

    private var title: String {
        switch place ?? .recent {
        case .recent: String(localized: "Recent")
        case .all: String(localized: "All Projects")
        case .starred: String(localized: "Favourites")
        case .trash: String(localized: "Trash")
        case .collection(let id): library.collections.first { $0.id == id }?.name ?? ""
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $place) {
            Label("Recent", systemImage: "clock").tag(Place.recent)
                .accessibilityIdentifier("home-recent")
            Label("All Projects", systemImage: "doc.on.doc").tag(Place.all)
                .accessibilityIdentifier("home-all")
            Label("Favourites", systemImage: "star").tag(Place.starred)
                .accessibilityIdentifier("home-starred")
                .dropDestination(for: URL.self) { urls, _ in
                    urls.forEach { library.star($0, true) }
                    return !urls.isEmpty
                }
            Label("Trash", systemImage: "trash").tag(Place.trash)
                .accessibilityIdentifier("home-trash")
                .dropDestination(for: URL.self) { urls, _ in
                    attempt { try urls.forEach(library.trash) }
                    return !urls.isEmpty
                }
            Section {
                ForEach(library.collections) { c in
                    collectionRow(c).tag(Place.collection(c.id))
                }
            } header: {
                HStack {
                    Text("Collections")
                    Spacer()
                    Button {
                        let id = library.newCollection(String(localized: "New Collection"))
                        place = .collection(id)
                        renamingCollection = id
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("New Collection")
                    .accessibilityIdentifier("home-new-collection")
                }
                // The plus sits inside the rows' selection, where their content ends.
                .padding(.trailing, 17)
                .accessibilityElement(children: .contain)
            }
        }
        .listStyle(.sidebar)
    }

    private func collectionRow(_ c: HomeLibrary.Collection) -> some View {
        Label {
            if renamingCollection == c.id {
                HomeRenameField(name: c.name) { name in
                    library.rename(collection: c.id, to: name)
                    renamingCollection = nil
                }
            } else {
                Text(c.name).accessibilityIdentifier("collection-\(c.name)")
            }
        } icon: {
            Image(systemName: "folder")
        }
        .dropDestination(for: URL.self) { urls, _ in
            urls.forEach { library.add($0, to: c.id) }
            return !urls.isEmpty
        }
        .contextMenu {
            Button("Rename…") { renamingCollection = c.id }
            Button("Delete Collection", role: .destructive) {
                if place == .collection(c.id) { place = .recent }
                library.delete(collection: c.id)
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if place == .trash {
                Button("Empty Trash") { library.emptyTrash() }
                    .disabled(library.trashed.isEmpty)
                    .accessibilityIdentifier("home-empty-trash")
            } else {
                Picker("View", selection: $asList) {
                    Label("Pictures", systemImage: "square.grid.2x2").tag(false)
                    Label("List", systemImage: "list.bullet").tag(true)
                }
                .pickerStyle(.segmented)
                .help("Show as pictures or as a list")
                .accessibilityIdentifier("home-view")
                Menu {
                    Picker("Sort by", selection: $sort) {
                        ForEach(Sort.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Sort by", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort by")
                .accessibilityIdentifier("home-sort")
            }
            Button {
                NSDocumentController.shared.openDocument(nil)
            } label: {
                Label("Open…", systemImage: "folder")
            }
            .help("Open a file from anywhere")
            .accessibilityIdentifier("home-open")
            Button {
                openWindow(id: StartView.id)
            } label: {
                Label("New…", systemImage: "plus")
            }
            .help("Start a document from a format or an example")
            .accessibilityIdentifier("home-new")
        }
    }

    // MARK: Content

    /// The projects of the chosen place, searched and sorted.
    private var shown: [HomeLibrary.Project] {
        let all = library.projects.filter { p in
            switch place ?? .recent {
            case .recent: p.opened != nil
            case .all: p.inFolder
            case .starred: p.starred
            case .trash: false
            case .collection(let id): p.collections.contains(id)
            }
        }
        let found = search.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(search) }
        return found.sorted { a, b in
            switch sort {
            case .edited: a.edited > b.edited
            case .opened: (a.opened ?? .distantPast, a.edited) > (b.opened ?? .distantPast, b.edited)
            case .name: a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if place == .trash {
            trash
        } else {
            let items = shown
            if items.isEmpty {
                empty
            } else if asList {
                list(items)
            } else {
                grid(items)
            }
        }
    }

    @ViewBuilder
    private var empty: some View {
        if !search.isEmpty {
            ContentUnavailableView.search(text: search)
        } else {
            switch place ?? .recent {
            case .starred:
                ContentUnavailableView(
                    "No favourites", systemImage: "star",
                    description: Text("Star a document from its context menu, or drag it onto Favourites."))
            case .collection:
                ContentUnavailableView(
                    "This collection is empty", systemImage: "folder",
                    description: Text("Drag documents onto the collection in the sidebar."))
            default:
                ContentUnavailableView {
                    Label("No documents yet", systemImage: "doc")
                } description: {
                    Text("Documents you save in \(library.folder.path(percentEncoded: false).abbreviatingWithTilde) show here.")
                } actions: {
                    Button("New Document…") { openWindow(id: StartView.id) }
                }
            }
        }
    }

    private func grid(_ items: [HomeLibrary.Project]) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 22)], spacing: 26) {
                ForEach(items) { p in
                    ProjectCard(
                        project: p, selected: selection.contains(p.id), renaming: renaming == p.id,
                        rename: { name in
                            renaming = nil
                            attempt { try library.rename(p.url, to: name) }
                        }
                    )
                    .onTapGesture(count: 2) { open(p.url) }
                    .onTapGesture { selection = [p.id] }
                    .draggable(p.url)
                    .contextMenu { menu(for: [p]) }
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onDeleteCommand { trashSelection() }
    }

    private func list(_ items: [HomeLibrary.Project]) -> some View {
        Table(items, selection: $selection) {
            TableColumn("Name") { p in
                HStack(spacing: 8) {
                    PagePicture(url: p.url).frame(width: 18, height: 24)
                    if renaming == p.id {
                        HomeRenameField(name: p.name) { name in
                            renaming = nil
                            attempt { try library.rename(p.url, to: name) }
                        }
                    } else {
                        Text(p.name)
                    }
                    if p.starred { Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow) }
                }
                .draggable(p.url)
            }
            TableColumn("Edited") { p in
                Text(p.edited, format: .relative(presentation: .named)).foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 130)
            TableColumn("Where") { p in
                Text(p.url.deletingLastPathComponent().path(percentEncoded: false).abbreviatingWithTilde)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            menu(for: library.projects.filter { ids.contains($0.id) })
        } primaryAction: { ids in
            library.projects.filter { ids.contains($0.id) }.forEach { open($0.url) }
        }
        .onDeleteCommand { trashSelection() }
        .accessibilityIdentifier("home-list")
    }

    @ViewBuilder
    private func menu(for projects: [HomeLibrary.Project]) -> some View {
        if let p = projects.first {
            Button("Open") { projects.forEach { open($0.url) } }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(projects.map(\.url)) }
            Divider()
            Button("Rename") {
                selection = [p.id]
                renaming = p.id
            }
            .disabled(projects.count > 1)
            Button("Duplicate") { attempt { try projects.forEach { try library.duplicate($0.url) } } }
            Divider()
            let starred = projects.allSatisfy(\.starred)
            Button(starred ? "Remove from Favourites" : "Add to Favourites") {
                projects.forEach { library.star($0.url, !starred) }
            }
            Menu("Collections") {
                ForEach(library.collections) { c in
                    let inside = projects.allSatisfy { $0.collections.contains(c.id) }
                    Toggle(c.name, isOn: Binding(get: { inside }, set: { on in
                        projects.forEach { on ? library.add($0.url, to: c.id) : library.remove($0.url, from: c.id) }
                    }))
                }
                if !library.collections.isEmpty { Divider() }
                Button("New Collection…") {
                    let id = library.newCollection(String(localized: "New Collection"))
                    projects.forEach { library.add($0.url, to: id) }
                    place = .collection(id)
                    renamingCollection = id
                }
            }
            Divider()
            Button("Move to Trash") { attempt { try projects.forEach { try library.trash($0.url) } } }
        }
    }

    // MARK: Trash

    @ViewBuilder
    private var trash: some View {
        if library.trashed.isEmpty {
            ContentUnavailableView(
                "The trash is empty", systemImage: "trash",
                description: Text("Documents moved to the trash wait here for 30 days."))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Documents are deleted 30 days after they were moved here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 22)], spacing: 26) {
                        ForEach(library.trashed) { t in
                            TrashCard(trashed: t, url: library.trashFolder.appending(path: t.file))
                                .contextMenu {
                                    Button("Put Back") { attempt { try library.restore(t) } }
                                    Button("Delete Now", role: .destructive) { attempt { try library.deleteForever(t) } }
                                }
                        }
                    }
                }
                .padding(24)
            }
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    // MARK: Actions

    private func open(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { failure = error.localizedDescription }
        }
        library.opened(url)
    }

    private func trashSelection() {
        let urls = library.projects.filter { selection.contains($0.id) }.map(\.url)
        attempt { try urls.forEach(library.trash) }
        selection = []
    }

    private func attempt(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// A document as a picture of its first page on the pasteboard grey of the canvas, with its
/// name and when it was edited.
private struct ProjectCard: View {
    let project: HomeLibrary.Project
    let selected: Bool
    let renaming: Bool
    let rename: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PagePicture(url: project.url, ppi: 40)
                .padding(18)
                .frame(maxWidth: .infinity)
                .frame(height: 210)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: Theme.pasteboard)))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(selected ? Color.accentColor : .primary.opacity(0.08), lineWidth: selected ? 3 : 1))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    if renaming {
                        HomeRenameField(name: project.name, commit: rename)
                    } else {
                        Text(project.name)
                            .font(.system(size: 14, weight: .medium, design: .serif))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Text("Edited \(project.edited.formatted(.relative(presentation: .named)))")
                        .font(.system(size: Theme.small))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if project.starred {
                    Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(.yellow)
                        .accessibilityLabel("Favourite")
                }
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
        .help(project.url.path(percentEncoded: false).abbreviatingWithTilde)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("project-\(project.name)")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// A document in the trash, with the days it has left.
private struct TrashCard: View {
    let trashed: HomeLibrary.Trashed
    let url: URL

    var body: some View {
        let left = max(0, Int(HomeLibrary.trashDays) - Calendar.current.dateComponents([.day], from: trashed.date, to: .now).day!)
        VStack(alignment: .leading, spacing: 8) {
            PagePicture(url: url, ppi: 40)
                .padding(18)
                .frame(maxWidth: .infinity)
                .frame(height: 210)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: Theme.pasteboard)))
                .opacity(0.6)
            VStack(alignment: .leading, spacing: 2) {
                Text(trashed.name).font(.system(size: 14, weight: .medium, design: .serif)).lineLimit(1)
                Text("Deleted in \(left) days").font(.system(size: Theme.small)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
        .help(trashed.original)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trashed-\(trashed.name)")
    }
}

/// A field that commits a new name on Return or when it loses focus.
struct HomeRenameField: View {
    let name: String
    let commit: (String) -> Void
    @State private var text = ""
    @State private var done = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Name", text: $text)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .accessibilityIdentifier("rename")
            .onAppear { text = name }
            // After the list has taken its new selection, which takes the focus.
            .task {
                try? await Task.sleep(for: .milliseconds(150))
                focused = true
            }
            .onSubmit(finish)
            .onChange(of: focused) { _, now in if !now { finish() } }
    }

    private func finish() {
        guard !done else { return }
        done = true
        commit(text)
    }
}

extension String {
    /// The path with the home folder as ~.
    var abbreviatingWithTilde: String { (self as NSString).abbreviatingWithTildeInPath }
}
