import SwiftUI
@preconcurrency import AppKit
import UniformTypeIdentifiers
import KindleManagerSupport

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        KM_Shutdown()
    }
}

@main
struct KindleManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup("Kindle Manager") {
            ContentView(store: store)
        }
        .windowToolbarStyle(.unifiedCompact)
    }
}

struct APIResponse<T: Decodable>: Decodable {
    let ok: Bool
    let error: String?
    let data: T?
}

struct InitPayload: Decodable {
    let ok: Bool
    let error: String?
}

struct TransferProgressPayload: Decodable {
    let active: Bool
    let sent: UInt64
    let total: UInt64
}

struct CreateFolderPayload: Decodable {
    let ok: Bool
    let id: UInt32?
    let error: String?
}

struct ScanData: Decodable {
    let scanned: Int?
    let added: Int?
    let updated: Int?
    let moved: Int?
    let deleted: Int?
}

struct ScanResult: Sendable {
    let ok: Bool
    let added: Int
    let error: String?
}

enum APIError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text):
            return text
        }
    }
}

struct Book: Codable, Identifiable, Hashable {
    let id: Int64
    let title: String
    let author: String
    let series: String?
    let seriesIndex: Double?
    let publisher: String?
    let year: Int?
    let language: String?
    let isbn: String?
    let description: String?
    let format: String
    let size: Int64
    let path: String?
    let coverPath: String?
}

struct Operation: Codable, Identifiable {
    let id: String
    let type: String
    let status: String
    let title: String
    let progress: Double
}

struct DeviceFile: Codable, Identifiable, Hashable {
    let id: UInt32
    let parentID: UInt32
    let storageID: UInt32
    let name: String
    let size: UInt64
    let isFolder: Bool
}

struct TreeNode: Identifiable {
    let id: UInt32
    let parentID: UInt32
    let storageID: UInt32
    let name: String
    let isFolder: Bool
    let size: UInt64
    var children: [TreeNode]?
}

struct DeviceFolder: Identifiable, Hashable {
    let id: UInt32
    let storageID: UInt32
    let label: String
}

struct LocalEntry: Identifiable, Hashable {
    let path: String
    let name: String
    let isDir: Bool
    let size: Int64
    let modified: Date?
    var id: String { path }
    var url: URL { URL(fileURLWithPath: path, isDirectory: isDir) }
}

struct Place: Identifiable, Hashable {
    let name: String
    let icon: String
    let url: URL
    let group: String
    var id: String { url.path }
}

struct RawDevice: Codable, Identifiable {
    let bus: Int
    let devNum: Int
    let vendorID: UInt16
    let productID: UInt16
    let vendor: String
    let product: String
    var id: String { "\(bus)-\(devNum)" }
}

struct OpResult: Sendable {
    let ok: Bool
    let message: String
}

struct ImportResult: Sendable {
    let copied: Int
    let errors: [String]
}

@_silgen_name("KM_Initialize")
func KM_Initialize(_ p: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
@_silgen_name("KM_Shutdown")
func KM_Shutdown()
@_silgen_name("KM_LibraryGetBooks")
func KM_LibraryGetBooks() -> UnsafeMutablePointer<CChar>?
@_silgen_name("KM_LibraryScan")
func KM_LibraryScan(_ p: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
@_silgen_name("KM_DeviceGetInfo")
func KM_DeviceGetInfo(_ bus: Int32, _ dev: Int32) -> UnsafeMutablePointer<CChar>?
@_silgen_name("KM_DeviceUploadBook")
func KM_DeviceUploadBook(_ path: UnsafePointer<CChar>?, _ parent: UInt32, _ storage: UInt32) -> UnsafeMutablePointer<CChar>?
@_silgen_name("KM_DeviceDownloadBook")
func KM_DeviceDownloadBook(_ id: UInt32, _ path: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
@_silgen_name("KM_DeviceDeleteBook")
func KM_DeviceDeleteBook(_ id: UInt32) -> UnsafeMutablePointer<CChar>?
@_silgen_name("KM_DeviceMoveBook")
func KM_DeviceMoveBook(_ id: UInt32, _ storage: UInt32, _ parent: UInt32) -> UnsafeMutablePointer<CChar>?
@_silgen_name("KM_DeviceCopyBook")
func KM_DeviceCopyBook(_ id: UInt32, _ storage: UInt32, _ parent: UInt32) -> UnsafeMutablePointer<CChar>?
@_silgen_name("KM_DeviceCreateFolder")
func KM_DeviceCreateFolder(_ name: UnsafePointer<CChar>?, _ parent: UInt32, _ storage: UInt32) -> UnsafeMutablePointer<CChar>?
@_silgen_name("KM_DeviceRenameBook")
func KM_DeviceRenameBook(_ id: UInt32, _ name: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
@_silgen_name("KM_DeviceIsConnected")
func KM_DeviceIsConnected() -> Int32
@_silgen_name("KM_DeviceDiscover")
func KM_DeviceDiscover() -> UnsafeMutablePointer<CChar>?
@_silgen_name("KM_DeviceListBooks")
func KM_DeviceListBooks() -> UnsafeMutablePointer<CChar>?
@_silgen_name("KM_DeviceTransferProgress")
func KM_DeviceTransferProgress() -> UnsafeMutablePointer<CChar>?
@_silgen_name("KM_DeviceCancelTransfer")
func KM_DeviceCancelTransfer() -> UnsafeMutablePointer<CChar>?
@_silgen_name("KM_ConvertBook")
func KM_ConvertBook(_ input: UnsafePointer<CChar>?, _ output: UnsafePointer<CChar>?, _ format: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
@_silgen_name("KM_OperationList")
func KM_OperationList() -> UnsafeMutablePointer<CChar>?
@_silgen_name("KM_OperationCancel")
func KM_OperationCancel(_ id: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
@_silgen_name("KM_FreeMemory")
func KM_FreeMemory(_ p: UnsafeMutableRawPointer?)

func kmString(_ p: UnsafeMutablePointer<CChar>?) -> String {
    guard let p else { return "" }
    let s = String(cString: p)
    KM_FreeMemory(p)
    return s
}

func withCStr<T>(_ s: String, _ f: (UnsafePointer<CChar>) -> T) -> T {
    let p = strdup(s)!
    defer { free(p) }
    return f(UnsafePointer(p))
}

func isOK(_ json: String) -> Bool {
    guard let data = json.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let ok = object["ok"] as? Bool else {
        return false
    }
    return ok
}

func errorText(_ raw: String) -> String {
    guard let data = raw.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let message = object["error"] as? String else {
        return raw
    }
    return message
}

func decodeEnvelope<T: Decodable>(_ raw: String, as type: T.Type) throws -> T {
    guard let data = raw.data(using: .utf8) else {
        throw APIError.message("empty response")
    }
    let response = try JSONDecoder().decode(APIResponse<T>.self, from: data)
    guard response.ok else {
        throw APIError.message(response.error ?? "request failed")
    }
    guard let value = response.data else {
        throw APIError.message("missing response data")
    }
    return value
}

func loadBooks() throws -> [Book] {
    try decodeEnvelope(kmString(KM_LibraryGetBooks()), as: [Book].self)
}

struct DeviceLoadResult: Sendable {
    let devices: [RawDevice]
    let error: String?
}

struct FolderUploadEntry: Sendable {
    let url: URL
    let components: [String]
    let isDirectory: Bool
}

func loadDevicesResult() -> DeviceLoadResult {
    do {
        let devices = try decodeEnvelope(kmString(KM_DeviceDiscover()), as: [RawDevice].self)
        return DeviceLoadResult(devices: devices, error: nil)
    } catch {
        return DeviceLoadResult(devices: [], error: error.localizedDescription)
    }
}

func loadDeviceFilesResult() -> (files: [DeviceFile], error: String?) {
    let raw = kmString(KM_DeviceListBooks())
    do {
        return (try decodeEnvelope(raw, as: [DeviceFile].self), nil)
    } catch {
        return ([], error.localizedDescription)
    }
}

func loadDeviceFiles() -> [DeviceFile] {
    loadDeviceFilesResult().files
}

func loadOperations() throws -> [Operation] {
    try decodeEnvelope(kmString(KM_OperationList()), as: [Operation].self)
}

func connectDevice(_ d: RawDevice) -> String {
    kmString(KM_DeviceGetInfo(Int32(d.bus), Int32(d.devNum)))
}

func icon(for entry: LocalEntry) -> String {
    if entry.isDir { return "folder.fill" }
    switch entry.url.pathExtension.lowercased() {
    case "epub", "mobi", "azw", "azw3", "fb2", "pdf", "txt", "djvu", "cbz", "cbr":
        return "book.closed.fill"
    case "jpg", "jpeg", "png", "gif", "heic", "webp", "tiff":
        return "photo"
    case "mp3", "m4a", "flac", "wav", "aac":
        return "music.note"
    case "zip", "rar", "7z", "tar", "gz", "bz2":
        return "archivebox"
    case "app":
        return "app"
    default:
        return "doc"
    }
}

func byteString(_ n: Int64) -> String {
    let f = ByteCountFormatter()
    f.countStyle = .file
    f.allowedUnits = [.useKB, .useMB, .useGB]
    return f.string(fromByteCount: n)
}

func dateString(_ d: Date) -> String {
    let f = DateFormatter()
    f.dateStyle = .short
    f.timeStyle = .short
    return f.string(from: d)
}

@MainActor
func chooseDirectory(prompt: String) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = prompt
    panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
    return panel.runModal() == .OK ? panel.url : nil
}

@MainActor
func chooseOpenFile(prompt: String) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.prompt = prompt
    panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
    return panel.runModal() == .OK ? panel.url : nil
}

@MainActor
func chooseSaveURL(name: String) -> URL? {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = name
    panel.canCreateDirectories = true
    return panel.runModal() == .OK ? panel.url : nil
}

let kindleCutType = NSPasteboard.PasteboardType("com.kindlemanager.cut")

func pasteboardFileURLs() -> [URL] {
    let pb = NSPasteboard.general
    let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
    guard let items = pb.readObjects(forClasses: [NSURL.self], options: options) as? [NSURL] else {
        return []
    }
    return items.map { $0 as URL }
}

func pasteboardIsCut() -> Bool {
    NSPasteboard.general.types?.contains(kindleCutType) ?? false
}

func writeFileURLsToPasteboard(_ urls: [URL], cut: Bool) {
    guard !urls.isEmpty else { return }
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.writeObjects(urls.map { $0 as NSURL })
    if cut {
        pb.setString("1", forType: kindleCutType)
    }
}

func listLocal(_ dir: URL, showHidden: Bool) -> [LocalEntry] {
    let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
    let opts: FileManager.DirectoryEnumerationOptions = showHidden ? [] : [.skipsHiddenFiles]
    guard let urls = try? FileManager.default.contentsOfDirectory(
        at: dir,
        includingPropertiesForKeys: keys,
        options: opts
    ) else { return [] }

    var out: [LocalEntry] = []
    for url in urls {
        let values = try? url.resourceValues(forKeys: Set(keys))
        out.append(LocalEntry(
            path: url.path,
            name: url.lastPathComponent,
            isDir: values?.isDirectory ?? false,
            size: Int64(values?.fileSize ?? 0),
            modified: values?.contentModificationDate
        ))
    }
    out.sort { a, b in
        if a.isDir != b.isDir { return a.isDir }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }
    return out
}

func buildDeviceTree(from files: [DeviceFile]) -> [TreeNode] {
    var byParent: [UInt32: [DeviceFile]] = [:]
    for f in files { byParent[f.parentID, default: []].append(f) }

    func makeNode(_ f: DeviceFile) -> TreeNode {
        let kids = (byParent[f.id] ?? []).sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }.map(makeNode)
        return TreeNode(
            id: f.id,
            parentID: f.parentID,
            storageID: f.storageID,
            name: f.name,
            isFolder: f.isFolder,
            size: f.size,
            children: kids.isEmpty ? nil : kids
        )
    }

    let folderIDs = Set(files.filter { $0.isFolder }.map(\.id))
    let roots = files.filter { file in
        file.parentID == 0 || !folderIDs.contains(file.parentID)
    }
    return roots.sorted { a, b in
        if a.isFolder != b.isFolder { return a.isFolder }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }.map(makeNode)
}

func deviceFolders(_ files: [DeviceFile], rootLabel: String = "Kindle (root)") -> [DeviceFolder] {
    var byID: [UInt32: DeviceFile] = [:]
    for f in files where f.isFolder { byID[f.id] = f }

    func label(for f: DeviceFile) -> String {
        var parts = [f.name]
        var cur = f
        var guardCount = 0
        while cur.parentID != 0, let parent = byID[cur.parentID], guardCount < 64 {
            parts.insert(parent.name, at: 0)
            cur = parent
            guardCount += 1
        }
        return parts.joined(separator: " / ")
    }

    var out = files.filter { $0.isFolder }.map {
        DeviceFolder(id: $0.id, storageID: $0.storageID, label: label(for: $0))
    }
    out.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    out.insert(DeviceFolder(id: 0, storageID: 0, label: rootLabel), at: 0)
    return out
}

enum AppSection: String, CaseIterable, Identifiable {
    case library
    case devices
    case files
    case convert

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: return "Library"
        case .devices: return "Kindle"
        case .files: return "Files"
        case .convert: return "Convert"
        }
    }

    var icon: String {
        switch self {
        case .library: return "books.vertical"
        case .devices: return "cable.connector"
        case .files: return "folder"
        case .convert: return "arrow.2.circlepath"
        }
    }
}

struct ContentView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        Group {
            switch store.section {
            case "library": LibraryView(store: store)
            case "devices": DevicesView(store: store)
            case "convert": ConvertView(store: store)
            case "files": FilesView(store: store)
            default: LibraryView(store: store)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 4) {
                    ForEach(AppSection.allCases) { section in
                        sectionButton(section)
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 10) {
                    Menu {
                        ForEach(AppLanguage.allCases) { language in
                            Button {
                                store.language = language
                            } label: {
                                if store.language == language {
                                    Label(language.displayName, systemImage: "checkmark")
                                } else {
                                    Text(language.displayName)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "globe")
                    }
                    .help(store.t("Language"))
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    Button {
                        store.toggleTheme()
                    } label: {
                        Image(systemName: store.theme.icon)
                    }
                    .buttonStyle(.borderless)
                    .help(store.t(store.theme == .dark ? "Light theme" : "Dark theme"))
                }
            }
        }
        .preferredColorScheme(store.theme.colorScheme)
        .environment(\.appLanguage, store.language)
        .alert("Kindle Manager", isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button(store.t("OK"), role: .cancel) { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
    }

    private func sectionButton(_ section: AppSection) -> some View {
        Button {
            store.section = section.rawValue
        } label: {
            Image(systemName: section.icon)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 32, height: 28)
                .background(
                    store.section == section.rawValue
                        ? Color.accentColor.opacity(0.10)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(store.t(section.title))
    }
}

enum LibraryLayout: String, CaseIterable, Identifiable {
    case grid
    case list

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }
}

struct LibraryView: View {
    @ObservedObject var store: AppStore
    @State private var search = ""
    @State private var layout: LibraryLayout = .grid
    @State private var sortAscending = true

    private var filteredBooks: [Book] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        var list = store.books
        if !query.isEmpty {
            list = list.filter {
                $0.title.localizedCaseInsensitiveContains(query)
                    || $0.author.localizedCaseInsensitiveContains(query)
                    || ($0.series ?? "").localizedCaseInsensitiveContains(query)
            }
        }
        return list.sorted {
            let result = $0.title.localizedCaseInsensitiveCompare($1.title)
            return sortAscending ? result == .orderedAscending : result == .orderedDescending
        }
    }

    private var folderName: String {
        guard let root = store.libraryRoot else { return store.t("Library") }
        return URL(fileURLWithPath: root).lastPathComponent
    }

    private var bookCountText: String {
        switch store.language {
        case .en: "Books: \(store.books.count)"
        case .ru: "Книг: \(store.books.count)"
        }
    }

    private func logLibraryState() {
        let line = "root=\(store.libraryRoot ?? "nil") books=\(store.books.count) filtered=\(filteredBooks.count) header=\(bookCountText) status=\(store.libraryStatus)\n"
        try? line.write(toFile: "/tmp/km-ui-debug.txt", atomically: true, encoding: .utf8)
    }

    var body: some View {
        Group {
            if store.libraryRoot == nil {
                emptyLibrary
            } else {
                libraryContent
            }
        }
        .onAppear { logLibraryState() }
        .onChange(of: store.books.count) { _, _ in logLibraryState() }
        .onChange(of: store.libraryStatus) { _, _ in logLibraryState() }
    }

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label(store.t("Library"), systemImage: "books.vertical")
        } description: {
            Text(store.t("Choose a folder with your books to build a library."))
        } actions: {
            Button(store.t("Choose Folder…")) { chooseLibrary() }
                .buttonStyle(.borderedProminent)
        }
    }

    private var libraryContent: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.libraryScanning {
                ProgressView(store.t("Scanning…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredBooks.isEmpty {
                ContentUnavailableView(
                    search.isEmpty ? store.t("No Books") : store.t("No Matches"),
                    systemImage: "book.closed",
                    description: Text(search.isEmpty
                        ? store.t("This folder does not contain supported book files.")
                        : store.t("Try a different search."))
                )
            } else {
                HStack(spacing: 0) {
                    content
                    if let book = store.selectedBook {
                        Divider()
                        BookDetailView(book: book)
                            .frame(minWidth: 0, idealWidth: 300, maxWidth: 320)
                    }
                }
            }

            if !store.libraryStatus.isEmpty {
                Divider()
                Text(store.libraryStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(folderName)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Text(bookCountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TextField(store.t("Search books"), text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            Picker(store.t("View"), selection: $layout) {
                ForEach(LibraryLayout.allCases) { value in
                    Image(systemName: value.icon).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 88)
            Button {
                sortAscending.toggle()
            } label: {
                Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
            }
            .buttonStyle(.borderless)
            .help(store.t(sortAscending ? "Sort Z–A" : "Sort A–Z"))
            Button {
                Task { _ = await store.rescanLibrary() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(store.t("Refresh"))
            .disabled(store.libraryScanning)
            Button { chooseLibrary() } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help(store.t("Choose another folder"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .grid:
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 16)],
                    spacing: 20
                ) {
                    ForEach(filteredBooks) { book in
                        BookCard(book: book, selected: store.selectedBook?.id == book.id)
                            .onTapGesture { store.selectedBook = book }
                            .contextMenu {
                                if let path = book.path {
                                    Button(store.t("Show in Finder")) {
                                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                                    }
                                }
                            }
                    }
                }
                .padding(20)
            }
        case .list:
            List(filteredBooks, selection: $store.selectedBook) { book in
                HStack(spacing: 10) {
                    BookCover(path: book.coverPath)
                        .frame(width: 34, height: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(book.title).font(.headline).lineLimit(1)
                        Text(book.author.isEmpty ? store.t("Unknown author") : book.author)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(book.format.uppercased())
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(byteString(book.size))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .trailing)
                }
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .listStyle(.inset)
        }
    }

    private func chooseLibrary() {
        guard let url = chooseDirectory(prompt: store.t("Choose Library")) else { return }
        Task { _ = await store.openLibrary(at: url) }
    }
}

struct BookCover: View {
    let path: String?

    var body: some View {
        Group {
            if let path, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.12))
                    .overlay {
                        Image(systemName: "book.closed")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct BookCard: View {
    let book: Book
    let selected: Bool
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BookCover(path: book.coverPath)
                .frame(maxWidth: .infinity)
                .frame(height: 170)

            Text(book.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text(book.author.isEmpty ? L10n.text("Unknown author", language) : book.author)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 6) {
                Text(book.format.uppercased())
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(byteString(book.size))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(selected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct BookDetailView: View {
    let book: Book
    @Environment(\.appLanguage) private var language

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                BookCover(path: book.coverPath)
                    .frame(width: 170, height: 230)
                    .frame(maxWidth: .infinity)

                Text(book.title)
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)
                Text(book.author.isEmpty ? L10n.text("Unknown author", language) : book.author)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if let series = book.series, !series.isEmpty {
                    Text(series + (book.seriesIndex.map { " #\($0)" } ?? ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                    if let publisher = book.publisher, !publisher.isEmpty {
                        GridRow { Text(L10n.text("Publisher", language)).foregroundStyle(.secondary); Text(publisher) }
                    }
                    if let year = book.year, year > 0 {
                        GridRow { Text(L10n.text("Year", language)).foregroundStyle(.secondary); Text(String(year)) }
                    }
                    if let bookLanguage = book.language, !bookLanguage.isEmpty {
                        GridRow { Text(L10n.text("Language of book", language)).foregroundStyle(.secondary); Text(bookLanguage) }
                    }
                    if let isbn = book.isbn, !isbn.isEmpty {
                        GridRow { Text(L10n.text("ISBN", language)).foregroundStyle(.secondary); Text(isbn).textSelection(.enabled) }
                    }
                    GridRow { Text(L10n.text("Format", language)).foregroundStyle(.secondary); Text(book.format.uppercased()) }
                    GridRow { Text(L10n.text("Size", language)).foregroundStyle(.secondary); Text(byteString(book.size)) }
                }
                .font(.caption)

                if let description = book.description, !description.isEmpty {
                    Divider()
                    Text(description)
                        .font(.callout)
                        .textSelection(.enabled)
                }

                if let path = book.path {
                    Button(L10n.text("Show in Finder", language)) {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                    .buttonStyle(.link)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ConvertView: View {
    @ObservedObject var store: AppStore
    @State private var format = "azw3"
    @State private var busy = false

    private let formats = ["azw3", "epub", "mobi", "pdf", "txt"]

    private var convertOperations: [Operation] {
        Array(store.operations.filter { $0.type == "convert" }.prefix(5))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.t("Convert"))
                        .font(.title2.weight(.semibold))
                    Text(store.t("Prepare a book for your Kindle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                GroupBox(store.t("Input")) {
                    fileRow(
                        path: store.convertInput,
                        placeholder: store.t("No file selected")
                    ) {
                        guard let url = chooseOpenFile(prompt: store.t("Input")) else { return }
                        store.convertInput = url.path
                        if store.convertOutput.isEmpty {
                            store.convertOutput = url
                                .deletingPathExtension()
                                .appendingPathExtension(format)
                                .path
                        }
                        store.convertResult = ""
                    }
                }

                GroupBox(store.t("Output")) {
                    fileRow(
                        path: store.convertOutput,
                        placeholder: store.t("No output selected")
                    ) {
                        let base = store.convertInput.isEmpty
                            ? "book"
                            : URL(fileURLWithPath: store.convertInput).deletingPathExtension().lastPathComponent
                        guard let url = chooseSaveURL(name: "\(base).\(format)") else { return }
                        store.convertOutput = url.path
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(store.t("Format")).font(.caption).foregroundStyle(.secondary)
                    Picker(store.t("Format"), selection: $format) {
                        ForEach(formats, id: \.self) { value in
                            Text(value.uppercased()).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                HStack(spacing: 10) {
                    Button(store.t("Convert")) { start() }
                        .buttonStyle(.borderedProminent)
                        .disabled(busy || store.convertInput.isEmpty || store.convertOutput.isEmpty)
                    if busy {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                }

                if !store.convertResult.isEmpty {
                    Text(store.convertResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if !convertOperations.isEmpty {
                    Divider()
                    Text(store.t("Activity")).font(.headline)
                    VStack(spacing: 8) {
                        ForEach(convertOperations) { op in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(op.title).font(.callout).lineLimit(1)
                                    Text(store.t(op.status.capitalized))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if op.status == "pending" || op.status == "running" {
                                    ProgressView(value: op.progress)
                                        .frame(width: 100)
                                    Button(store.t("Cancel")) {
                                        Task { _ = await store.cancelOperation(op.id) }
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: format) { _, newFormat in
            guard !store.convertOutput.isEmpty else { return }
            store.convertOutput = URL(fileURLWithPath: store.convertOutput)
                .deletingPathExtension()
                .appendingPathExtension(newFormat)
                .path
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                store.reloadOperations(silent: true)
            }
        }
    }

    private func fileRow(path: String, placeholder: String, choose: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(path.isEmpty ? placeholder : path)
                .lineLimit(1)
                .foregroundStyle(path.isEmpty ? .secondary : .primary)
            Spacer()
            Button(store.t("Choose…"), action: choose)
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    private func start() {
        let inputURL = URL(fileURLWithPath: store.convertInput)
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            store.lastError = store.t("Input file does not exist")
            return
        }
        let outputURL = URL(fileURLWithPath: store.convertOutput)
            .deletingPathExtension()
            .appendingPathExtension(format)
        guard FileManager.default.fileExists(atPath: outputURL.deletingLastPathComponent().path) else {
            store.lastError = store.t("Output folder does not exist")
            return
        }
        store.convertOutput = outputURL.path
        busy = true
        let input = store.convertInput
        let output = store.convertOutput
        let selectedFormat = format
        Task {
            let result = await store.startConversion(
                input: input,
                output: output,
                format: selectedFormat
            )
            busy = false
            if isOK(result) {
                store.convertResult = store.t("Conversion queued")
            } else {
                store.convertResult = result
                store.lastError = errorText(result)
            }
        }
    }
}

// MARK: - Kindle device browser

struct DevicesView: View {
    @ObservedObject var store: AppStore

    @State private var tree: [TreeNode] = []
    @State private var selection = Set<UInt32>()
    @State private var status = ""
    @State private var folders: [DeviceFolder] = []

    @State private var showPicker = false
    @State private var pickerTitle = ""
    @State private var pickerCopy = false
    @State private var pickerFiles: [DeviceFile] = []

    @State private var showRename = false
    @State private var renameID: UInt32 = 0
    @State private var renameText = ""

    @State private var showNewFolder = false
    @State private var newFolderName = ""

    @State private var showDelete = false
    @State private var pendingDelete: [DeviceFile] = []
    @State private var showUpload = false

    @State private var showMoveToLocal = false
    @State private var pendingLocalMove: [DeviceFile] = []
    @State private var localMoveDir: URL?
    @State private var listHovered = false

    private func t(_ key: String, _ arguments: CVarArg...) -> String {
        store.t(key, arguments)
    }

    var body: some View {
        VStack(spacing: 0) {
            if store.devices.isEmpty && !store.deviceLoading {
                ContentUnavailableView {
                    Label(t("No Kindle Connected"), systemImage: "cable.connector")
                } description: {
                    Text(t("Connect your Kindle with a USB cable."))
                } actions: {
                    Button(t("Refresh")) { refresh() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                deviceHeader
                Divider()
                ZStack {
                    List(tree, children: \.children, selection: $selection) { node in
                        HStack(spacing: 8) {
                            Image(systemName: node.isFolder ? "folder.fill" : "doc")
                                .foregroundStyle(node.isFolder ? Color.accentColor : .secondary)
                                .frame(width: 18)
                            Text(node.name).lineLimit(1)
                            Spacer()
                            if !node.isFolder {
                                Text(byteString(Int64(node.size)))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .tag(node.id)
                        .onDrag {
                            dragProvider(for: node)
                        }
                    }
                    .listStyle(.inset)
                    .onHover { listHovered = $0 }
                    .background(EmptyAreaContextMenu(isActive: listHovered, entries: kindleEmptyEntries))
                    .dropDestination(for: URL.self) { urls, _ in
                        dropUpload(urls)
                    }
                    .contextMenu(forSelectionType: UInt32.self) { ids in
                        deviceMenu(ids: ids)
                    } primaryAction: { ids in
                        devicePrimaryAction(ids)
                    }

                    if store.deviceLoading {
                        ProgressView(t("Loading Kindle…"))
                            .padding()
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .onAppear { rebuild() }
        .onChange(of: store.deviceRevision) { _, _ in rebuild() }
        .sheet(isPresented: $showPicker) {
            DeviceFolderPicker(title: pickerTitle, folders: folders) { target in
                applyTransfer(to: target)
                showPicker = false
            } onCancel: {
                showPicker = false
            }
        }
        .alert(t("New Folder"), isPresented: $showNewFolder) {
            TextField(t("Name"), text: $newFolderName)
            Button(t("Create")) { createFolder() }
            Button(t("Cancel"), role: .cancel) {}
        }
        .alert(t("Rename"), isPresented: $showRename) {
            TextField(t("Name"), text: $renameText)
            Button(t("Rename")) { performRename() }
            Button(t("Cancel"), role: .cancel) {}
        }
        .alert(t("Delete from Kindle?"), isPresented: $showDelete) {
            Button(t("Delete"), role: .destructive) { performDelete() }
            Button(t("Cancel"), role: .cancel) { pendingDelete = [] }
        } message: {
            Text(t("%d item(s) will be permanently deleted from the device.", pendingDelete.count))
        }
        .alert(t("Move to Mac?"), isPresented: $showMoveToLocal) {
            Button(t("Move"), role: .destructive) { performMoveToLocal() }
            Button(t("Cancel"), role: .cancel) {
                pendingLocalMove = []
                localMoveDir = nil
            }
        } message: {
            Text(t("%d file(s) will be copied to your Mac and deleted from Kindle.", pendingLocalMove.count))
        }
        .fileImporter(isPresented: $showUpload, allowedContentTypes: [.data]) { result in
            guard case .success(let url) = result else { return }
            let parent = selectedFolder
            Task {
                status = await store.uploadDeviceFiles(
                    [url.path],
                    parent: parent?.id ?? 0,
                    storage: parent?.storageID ?? 0
                )
            }
        }
    }

    private var deviceName: String {
        store.devices.first(where: { $0.id == store.selectedDeviceKey })?.product ?? "Kindle"
    }

    private var deviceHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "cable.connector")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(deviceName)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Text(status.isEmpty ? store.deviceStatus : status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !selection.isEmpty {
                Text(t("%d selected", selection.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.devices.count > 1 {
                Picker(t("Device"), selection: Binding(
                    get: { store.selectedDeviceKey ?? "" },
                    set: { store.selectDevice($0) }
                )) {
                    ForEach(store.devices) { device in
                        Text(device.product.isEmpty ? device.vendor : device.product)
                            .tag(device.id)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }
            if store.deviceTransferActive {
                if store.deviceTransferBytesTotal > 0 {
                    ProgressView(
                        value: Double(min(store.deviceTransferBytesSent, store.deviceTransferBytesTotal)),
                        total: Double(store.deviceTransferBytesTotal)
                    )
                    .frame(width: 100)
                }
                Button(t("Cancel")) { store.cancelDeviceTransfer() }
            }
            Button { refresh() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(t("Refresh"))
            .disabled(store.deviceLoading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var selectedFiles: [DeviceFile] {
        store.deviceFiles.filter { selection.contains($0.id) }
    }

    private var selectedFolder: DeviceFile? {
        guard selection.count == 1, let f = selectedFiles.first, f.isFolder else { return nil }
        return f
    }

    private var targetFolder: (id: UInt32, storage: UInt32) {
        if let folder = selectedFolder {
            return (folder.id, folder.storageID)
        }
        if selection.count == 1, let f = selectedFiles.first {
            return (f.parentID, f.storageID)
        }
        return (0, 0)
    }

    @ViewBuilder
    private func deviceMenu(ids: Set<UInt32>) -> some View {
        let chosen = store.deviceFiles.filter { ids.contains($0.id) }
        if chosen.isEmpty {
            Button(t("New Folder…")) { newFolderName = t("New Folder"); showNewFolder = true }
            Button(t("Upload File…")) { showUpload = true }
            Button(selectedFolder.map { t("Paste into %@", $0.name) } ?? t("Paste")) { pasteIntoKindle() }
            Divider()
            Button(t("Refresh")) { refresh() }
        } else {
            if chosen.count == 1, let f = chosen.first {
                if !f.isFolder {
                    Button(t("Open")) {
                        Task { status = await store.openDeviceFile(f) }
                    }
                    Button(t("Download…")) { download(f) }
                } else {
                    Button(t("New Folder Here…")) {
                        newFolderName = t("New Folder")
                        showNewFolder = true
                    }
                }
                Button(t("Rename…")) {
                    renameID = f.id
                    renameText = f.name
                    showRename = true
                }
                if f.isFolder {
                    Button(t("Paste Into %@", f.name)) { pasteIntoKindle(into: f) }
                }
                Divider()
            }
            Button(t("Download to Folder…")) { downloadToFolder(chosen) }
            if chosen.contains(where: { !$0.isFolder }) {
                Button(t("Move to Local Folder…")) {
                    beginMoveToLocal(chosen.filter { !$0.isFolder })
                }
            }
            Button(t("Copy To…")) { beginTransfer(chosen, copy: true) }
            Button(t("Move To…")) { beginTransfer(chosen, copy: false) }
            Divider()
            Button(t("Delete…"), role: .destructive) { confirmDelete(chosen) }
        }
    }

    private func devicePrimaryAction(_ ids: Set<UInt32>) {
        guard ids.count == 1,
              let f = store.deviceFiles.first(where: { $0.id == ids.first! }),
              !f.isFolder else { return }
        Task { status = await store.openDeviceFile(f) }
    }

    private func dragProvider(for node: TreeNode) -> NSItemProvider {
        guard !node.isFolder,
              let file = store.deviceFiles.first(where: { $0.id == node.id }) else {
            return NSItemProvider()
        }

        let box = DeviceDragBox(store: store, file: file)
        let ext = (file.name as NSString).pathExtension
        let type = UTType(filenameExtension: ext)?.identifier ?? UTType.data.identifier
        let provider = NSItemProvider()
        provider.registerFileRepresentation(
            forTypeIdentifier: type,
            fileOptions: [],
            visibility: .all
        ) { completion in
            Task { @MainActor in
                do {
                    let destination = try FileSafety.temporaryDownloadURL(for: box.file.name)
                    let result = await box.store.downloadDeviceFile(box.file.id, to: destination.path)
                    if isOK(result) {
                        completion(destination, true, nil)
                    } else {
                        completion(nil, false, APIError.message(errorText(result)))
                    }
                } catch {
                    completion(nil, false, error)
                }
            }
            return nil
        }
        return provider
    }

    private func rebuild() {
        tree = buildDeviceTree(from: store.deviceFiles)
        folders = deviceFolders(store.deviceFiles, rootLabel: t("Kindle (root)"))
        selection = selection.intersection(Set(store.deviceFiles.map(\.id)))
    }

    private func refresh() {
        store.refreshDevice()
    }

    private func kindleEmptyEntries() -> [ContextMenuEntry] {
        [
            .item(t("New Folder…")) {
                newFolderName = t("New Folder")
                showNewFolder = true
            },
            .item(t("Upload File…")) { showUpload = true },
            .item(selectedFolder.map { t("Paste into %@", $0.name) } ?? t("Paste")) {
                pasteIntoKindle()
            },
            .separator,
            .item(t("Refresh")) { refresh() },
        ]
    }

    private func pasteIntoKindle(into folder: DeviceFile? = nil) {
        let urls = pasteboardFileURLs().filter { !$0.hasDirectoryPath }
        guard !urls.isEmpty else {
            status = t("Clipboard has no files")
            return
        }
        let moving = pasteboardIsCut()
        let target: (id: UInt32, storage: UInt32) = folder.map { ($0.id, $0.storageID) } ?? targetFolder
        let count = urls.count
        status = moving ? t("Moving %d file(s)…", count) : t("Uploading %d file(s)…", count)
        Task {
            let result = await store.uploadDeviceFilesChecked(
                urls.map(\.path),
                parent: target.id,
                storage: target.storage
            )
            if result.ok && moving {
                let trash = await Task.detached(priority: .userInitiated) {
                    LocalFileService.trash(urls)
                }.value
                NSPasteboard.general.clearContents()
                status = trash.errors.isEmpty
                    ? t("Moved %d file(s) to Kindle", trash.trashed)
                    : trash.errors.joined(separator: "; ")
            } else {
                status = result.message
            }
        }
    }

    private func dropUpload(_ urls: [URL]) -> Bool {
        let items = urls.filter(\.isFileURL)
        guard !items.isEmpty else { return false }
        let directories = items.filter(\.hasDirectoryPath)
        let files = items.filter { !$0.hasDirectoryPath }
        let target = targetFolder
        let folder = DeviceFolder(id: target.id, storageID: target.storage, label: t("Kindle"))
        status = t("Uploading %d item(s)…", items.count)
        Task {
            var errors: [String] = []
            for directory in directories {
                let result = await store.uploadFolderToKindle(directory, target: folder)
                if !result.ok { errors.append(result.message) }
            }
            if !files.isEmpty {
                let result = await store.uploadDeviceFiles(
                    files.map(\.path),
                    parent: target.id,
                    storage: target.storage
                )
                if !isOK(result) { errors.append(errorText(result)) }
            }
            status = errors.isEmpty
                ? t("Uploaded %d item(s)", items.count)
                : errors.joined(separator: "; ")
        }
        return true
    }

    private func downloadSelectedToFolder() {
        downloadToFolder(selectedFiles)
    }

    private func downloadToFolder(_ roots: [DeviceFile]) {
        guard !roots.isEmpty else { return }
        guard let dir = chooseDirectory(prompt: t("Download")) else { return }
        let items = DevicesView.flattenFiles(roots, all: store.deviceFiles)
        guard !items.isEmpty else {
            status = t("Nothing to download")
            return
        }
        store.beginDeviceTransfer(total: items.count)
        status = t("Downloading %d file(s)…", items.count)
        Task {
            defer { store.finishDeviceTransfer() }
            var errors: [String] = []
            var done = 0
            for (index, item) in items.enumerated() {
                if store.deviceTransferCancelled {
                    errors.append(t("Cancelled"))
                    break
                }
                let relative = item.components.joined(separator: "/")
                let parent: URL
                do {
                    let safe = try FileSafety.safeDestination(base: dir, components: item.components)
                    parent = safe.deletingLastPathComponent()
                    try FileManager.default.createDirectory(
                        at: parent,
                        withIntermediateDirectories: true
                    )
                } catch {
                    errors.append("\(relative): \(error.localizedDescription)")
                    continue
                }

                let temporary: URL
                do {
                    temporary = try FileSafety.temporaryDownloadURL(for: item.file.name)
                } catch {
                    errors.append("\(relative): \(error.localizedDescription)")
                    continue
                }

                let r = await store.downloadDeviceFile(item.file.id, to: temporary.path)
                if isOK(r) {
                    do {
                        _ = try FileSafety.moveUnique(temporary, into: parent)
                        done += 1
                    } catch {
                        errors.append("\(relative): \(error.localizedDescription)")
                    }
                } else {
                    errors.append("\(relative): \(r)")
                }
                try? FileManager.default.removeItem(at: temporary.deletingLastPathComponent())
                store.deviceTransferDone = index + 1
            }
            status = errors.isEmpty
                ? t("Downloaded %d file(s) to %@", done, dir.lastPathComponent)
                : errors.joined(separator: "; ")
        }
    }

    private func beginMoveToLocal(_ files: [DeviceFile]) {
        guard !files.isEmpty else {
            status = t("Select file(s) to move")
            return
        }
        guard let dir = chooseDirectory(prompt: t("Move")) else { return }
        pendingLocalMove = files
        localMoveDir = dir
        showMoveToLocal = true
    }

    private func performMoveToLocal() {
        let files = pendingLocalMove
        let dir = localMoveDir
        pendingLocalMove = []
        localMoveDir = nil
        guard let dir, !files.isEmpty else { return }
        store.beginDeviceTransfer(total: files.count)
        status = t("Moving %d file(s)…", files.count)
        Task {
            defer { store.finishDeviceTransfer() }
            var downloaded: [DeviceFile] = []
            var errors: [String] = []
            for (index, f) in files.enumerated() {
                if store.deviceTransferCancelled {
                    errors.append(t("Cancelled"))
                    break
                }
                let parent: URL
                do {
                    let safe = try FileSafety.safeDestination(base: dir, components: [f.name])
                    parent = safe.deletingLastPathComponent()
                } catch {
                    errors.append("\(f.name): \(error.localizedDescription)")
                    continue
                }

                let temporary: URL
                do {
                    temporary = try FileSafety.temporaryDownloadURL(for: f.name)
                } catch {
                    errors.append("\(f.name): \(error.localizedDescription)")
                    continue
                }

                let r = await store.downloadDeviceFile(f.id, to: temporary.path)
                if isOK(r) {
                    do {
                        _ = try FileSafety.moveUnique(temporary, into: parent)
                        downloaded.append(f)
                    } catch {
                        errors.append("\(f.name): \(error.localizedDescription)")
                    }
                } else {
                    errors.append("\(f.name): \(r)")
                }
                try? FileManager.default.removeItem(at: temporary.deletingLastPathComponent())
                store.deviceTransferDone = index + 1
            }
            if !store.deviceTransferCancelled && !downloaded.isEmpty {
                let result = await store.deleteDeviceObjectsChecked(downloaded.map(\.id))
                if !result.ok { errors.append(result.message) }
            }
            status = errors.isEmpty
                ? t("Moved %d file(s) to %@", downloaded.count, dir.lastPathComponent)
                : errors.joined(separator: "; ")
        }
    }

    nonisolated private static func flattenFiles(
        _ roots: [DeviceFile],
        all: [DeviceFile]
    ) -> [(file: DeviceFile, components: [String])] {
        var byParent: [UInt32: [DeviceFile]] = [:]
        for f in all { byParent[f.parentID, default: []].append(f) }
        var out: [(DeviceFile, [String])] = []
        var seen = Set<UInt32>()
        func walk(_ f: DeviceFile, prefix: [String]) {
            guard !seen.contains(f.id) else { return }
            seen.insert(f.id)
            let path = prefix + [f.name]
            if f.isFolder {
                for child in byParent[f.id] ?? [] { walk(child, prefix: path) }
            } else {
                out.append((f, path))
            }
        }
        for root in roots { walk(root, prefix: []) }
        return out.map { (file: $0.0, components: $0.1) }
    }

    private func download(_ f: DeviceFile) {
        guard !f.isFolder else { return }
        guard let dest = chooseSaveURL(name: FileSafety.sanitizeFileName(f.name)) else { return }
        Task { status = await store.downloadDeviceFile(f.id, to: dest.path) }
    }

    private func downloadSelected() {
        let files = selectedFiles.filter { !$0.isFolder }
        guard !files.isEmpty else { return }
        var destinations: [(UInt32, String)] = []
        for f in files {
            guard let dest = chooseSaveURL(name: FileSafety.sanitizeFileName(f.name)) else { return }
            destinations.append((f.id, dest.path))
        }
        Task {
            var errors: [String] = []
            for (id, path) in destinations {
                let r = await store.downloadDeviceFile(id, to: path)
                if !isOK(r) { errors.append(r) }
            }
            status = errors.isEmpty ? t("Downloaded %d file(s)", destinations.count) : errors.joined(separator: "; ")
        }
    }

    private func beginTransfer(_ files: [DeviceFile], copy: Bool) {
        guard !files.isEmpty else { return }
        pickerFiles = files
        pickerCopy = copy
        pickerTitle = copy ? t("Copy %d item(s) to…", files.count) : t("Move %d item(s) to…", files.count)
        folders = deviceFolders(store.deviceFiles, rootLabel: t("Kindle (root)"))
        showPicker = true
    }

    private func applyTransfer(to target: DeviceFolder) {
        let folderIDs = Set(pickerFiles.filter(\.isFolder).map(\.id))
        if !folderIDs.isEmpty && isDeviceDescendant(target.id, of: folderIDs) {
            status = t("Cannot move or copy a folder into itself")
            return
        }
        let ids = pickerFiles.map(\.id)
        let copy = pickerCopy
        pickerFiles = []
        Task { status = await store.moveDeviceObjects(ids, to: target, copy: copy) }
    }

    private func isDeviceDescendant(_ targetID: UInt32, of sourceIDs: Set<UInt32>) -> Bool {
        var parents: [UInt32: UInt32] = [:]
        for file in store.deviceFiles where file.isFolder {
            parents[file.id] = file.parentID
        }
        var current = targetID
        var steps = 0
        while current != 0 && steps < 128 {
            if sourceIDs.contains(current) { return true }
            guard let parent = parents[current] else { return false }
            current = parent
            steps += 1
        }
        return false
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let parent = targetFolder
        Task {
            status = await store.createDeviceFolder(
                name,
                parent: parent.id,
                storage: parent.storage
            )
        }
    }

    private func performRename() {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let id = renameID
        Task { status = await store.renameDeviceObject(id, to: name) }
    }

    private func confirmDelete(_ files: [DeviceFile]) {
        guard !files.isEmpty else { return }

        var byParent: [UInt32: [DeviceFile]] = [:]
        for file in store.deviceFiles {
            byParent[file.parentID, default: []].append(file)
        }
        var seen = Set<UInt32>()
        var ordered: [DeviceFile] = []
        func collect(_ file: DeviceFile) {
            guard seen.insert(file.id).inserted else { return }
            for child in byParent[file.id] ?? [] {
                collect(child)
            }
            ordered.append(file)
        }
        for file in files {
            collect(file)
        }

        pendingDelete = ordered
        showDelete = true
    }

    private func performDelete() {
        let ids = pendingDelete.map(\.id)
        let count = ids.count
        pendingDelete = []
        Task {
            status = await store.deleteDeviceObjects(ids)
            _ = count
        }
    }
}

final class DeviceDragBox: @unchecked Sendable {
    let store: AppStore
    let file: DeviceFile

    init(store: AppStore, file: DeviceFile) {
        self.store = store
        self.file = file
    }
}

struct DeviceFolderPicker: View {
    @Environment(\.appLanguage) private var language
    let title: String
    let folders: [DeviceFolder]
    var onPick: (DeviceFolder) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text(title).font(.headline)
            List(folders) { folder in
                Button {
                    onPick(folder)
                } label: {
                    HStack {
                        Image(systemName: "folder.fill").foregroundStyle(.secondary)
                        Text(folder.label)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 320)
            HStack {
                Spacer()
                Button(L10n.text("Cancel", language), action: onCancel)
            }
        }
        .padding()
        .frame(width: 480, height: 440)
    }
}

// MARK: - Local Finder-style browser

struct FilesView: View {
    @ObservedObject var store: AppStore

    @State private var currentURL = FileManager.default.homeDirectoryForCurrentUser
    @State private var entries: [LocalEntry] = []
    @State private var selection = Set<String>()
    @State private var backStack: [URL] = []
    @State private var forwardStack: [URL] = []
    @State private var search = ""
    @State private var status = ""

    @State private var clipboard: [URL] = []
    @State private var clipboardCut = false
    @State private var clipboardChangeCount = -1

    @State private var showImporter = false
    @State private var pendingDelete: [URL] = []
    @State private var showDelete = false
    @State private var listHovered = false

    @State private var reloadToken = UUID()
    @State private var showKindlePicker = false
    @State private var pendingUploadURLs: [URL] = []
    @State private var pendingUploadMove = false
    @State private var pendingKindleTarget: DeviceFolder?
    @State private var showMoveToKindleConfirm = false

    @State private var renameTarget: URL?
    @State private var renameText = ""
    @State private var showRename = false

    @State private var newFolderName = ""
    @State private var showNewFolder = false

    private func t(_ key: String, _ arguments: CVarArg...) -> String {
        store.t(key, arguments)
    }

    private var favorites: [Place] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            Place(name: t("Home"), icon: "house", url: home, group: "favorites"),
            Place(name: t("Desktop"), icon: "menubar.dock.rectangle", url: home.appendingPathComponent("Desktop"), group: "favorites"),
            Place(name: t("Documents"), icon: "doc.text", url: home.appendingPathComponent("Documents"), group: "favorites"),
            Place(name: t("Downloads"), icon: "arrow.down.circle", url: home.appendingPathComponent("Downloads"), group: "favorites"),
            Place(name: t("Applications"), icon: "app", url: URL(fileURLWithPath: "/Applications"), group: "favorites"),
        ].filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }

    private var volumes: [Place] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"), includingPropertiesForKeys: nil) else { return [] }
        return urls.map { Place(name: $0.lastPathComponent, icon: "externaldrive", url: $0, group: "volumes") }
    }

    private var filtered: [LocalEntry] {
        var list = entries
        if !search.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(search) }
        }
        return list
    }

    private var breadcrumbs: [(String, URL)] {
        var out: [(String, URL)] = []
        var acc = URL(fileURLWithPath: "/")
        for component in currentURL.pathComponents where component != "/" {
            acc = acc.appendingPathComponent(component)
            out.append((component, acc))
        }
        return out
    }

    var body: some View {
        HSplitView {
            sidebar
                .frame(idealWidth: 185, maxWidth: 240)

            VStack(spacing: 0) {
                navigationBar
                Divider()
                fileList
                Divider()
                statusBar
            }

        }
        .onAppear { reload() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data]) { result in
            guard case .success(let url) = result else { return }
            let ok = url.startAccessingSecurityScopedResource()
            beginUploadToKindle([url], move: false)
            if ok { url.stopAccessingSecurityScopedResource() }
        }
        .sheet(isPresented: $showKindlePicker) {
            DeviceFolderPicker(
                title: pendingUploadMove
                    ? t("Move %d file(s) to…", pendingUploadURLs.count)
                    : t("Upload %d file(s) to…", pendingUploadURLs.count),
                folders: deviceFolders(store.deviceFiles, rootLabel: t("Kindle (root)"))
            ) { target in
                applyKindleTarget(target)
            } onCancel: {
                showKindlePicker = false
                pendingUploadURLs = []
            }
        }
        .alert(t("Move to Kindle?"), isPresented: $showMoveToKindleConfirm) {
            Button(t("Move"), role: .destructive) {
                if let target = pendingKindleTarget {
                    performUpload(target, move: true)
                }
            }
            Button(t("Cancel"), role: .cancel) {
                pendingUploadURLs = []
                pendingKindleTarget = nil
            }
        } message: {
            Text(t("The local copy of %d file(s) will be moved to Trash after a successful upload.", pendingUploadURLs.count))
        }
    }

    private var sidebar: some View {
        List {
            Section(t("Favorites")) {
                ForEach(favorites) { place in
                    sidebarRow(place)
                }
            }
            Section(t("Volumes")) {
                ForEach(volumes) { place in
                    sidebarRow(place)
                }
            }
        }
        .listStyle(.inset)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func sidebarRow(_ place: Place) -> some View {
        Button {
            go(place.url)
        } label: {
            Label(place.name, systemImage: place.icon)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }

    private var navigationBar: some View {
        HStack(spacing: 8) {
            Button { goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(backStack.isEmpty)
                .help(t("Back"))
            Button { goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(forwardStack.isEmpty)
                .help(t("Forward"))
            Button { goUp() } label: { Image(systemName: "arrow.up") }
                .disabled(currentURL.path == "/")
                .help(t("Parent folder"))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(Array(breadcrumbs.enumerated()), id: \.element.1) { index, item in
                        if index > 0 {
                            Text("/").foregroundStyle(.tertiary)
                        }
                        Button(item.0) { go(item.1) }
                            .buttonStyle(.plain)
                            .font(.callout)
                    }
                }
            }
            Spacer(minLength: 8)

            TextField(t("Search"), text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .alert(t("New Folder"), isPresented: $showNewFolder) {
            TextField(t("Name"), text: $newFolderName)
            Button(t("Create")) { createFolder() }
            Button(t("Cancel"), role: .cancel) {}
        }
    }

    private var fileList: some View {
        List(selection: $selection) {
            ForEach(filtered) { entry in
                HStack(spacing: 8) {
                    Image(systemName: icon(for: entry))
                        .foregroundStyle(entry.isDir ? Color.accentColor : .secondary)
                        .frame(width: 18)
                    Text(entry.name).lineLimit(1)
                    Spacer()
                    if !entry.isDir {
                        Text(byteString(entry.size))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .trailing)
                    }
                    if let modified = entry.modified {
                        Text(dateString(modified))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(width: 135, alignment: .trailing)
                    }
                }
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .tag(entry.path)
                .onDrag {
                    NSItemProvider(contentsOf: entry.url) ?? NSItemProvider(object: entry.url as NSURL)
                }
            }
        }
        .listStyle(.inset)
        .onHover { listHovered = $0 }
        .background(EmptyAreaContextMenu(isActive: listHovered, entries: localEmptyEntries))
        .contextMenu(forSelectionType: String.self) { ids in
            localMenu(ids: ids)
        } primaryAction: { ids in
            localPrimaryAction(ids)
        }
        .alert(t("Rename"), isPresented: $showRename) {
            TextField(t("Name"), text: $renameText)
            Button(t("Rename")) { performRename() }
            Button(t("Cancel"), role: .cancel) { renameTarget = nil }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let fileURLs = urls.filter { $0.isFileURL }
            guard !fileURLs.isEmpty else { return false }
            importExternal(fileURLs)
            return true
        }
    }

    private var statusBar: some View {
        HStack {
            Text(status.isEmpty ? currentURL.path : status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text(t("%d items", filtered.count))
                .font(.caption)
                .foregroundStyle(.secondary)
            if !selection.isEmpty {
                Text("· " + t("%d selected", selection.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var selectedEntries: [LocalEntry] {
        entries.filter { selection.contains($0.path) }
    }

    private var selectionURLs: [URL] {
        selectedEntries.map(\.url)
    }

    @ViewBuilder
    private func localMenu(ids: Set<String>) -> some View {
        let chosen = entries.filter { ids.contains($0.path) }
        if chosen.isEmpty {
            Button(t("New Folder…")) {
                newFolderName = t("untitled folder")
                showNewFolder = true
            }
            Button(t("Upload File…")) { showImporter = true }
            Button(t("Paste")) { paste() }
            Divider()
            Button(t("Refresh")) { reload() }
        } else {
            let urls = chosen.map(\.url)
            if chosen.count == 1, let entry = chosen.first {
                Button(t("Open")) {
                    openEntry(entry)
                }
                Button(t("Open in Finder")) {
                    if entry.isDir {
                        NSWorkspace.shared.open(entry.url)
                    } else {
                        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
                    }
                }
                if entry.isDir {
                    Button(t("Paste Into %@", entry.name)) { paste(into: entry.url) }
                }
                Divider()
            }
            Button(t("Copy")) { copySelection(ids) }
            Button(t("Cut")) { cutSelection(ids) }
            Button(t("Paste")) { paste() }
            Divider()
            Button(t("Move to…")) { moveTo(urls) }
            Button(t("Copy to…")) { copyTo(urls) }
            if chosen.count == 1, let entry = chosen.first {
                Button(t("Rename…")) { beginRename(entry.url) }
                Button(t("Duplicate")) { duplicate(urls) }
            }
            Divider()
            if !chosen.isEmpty {
                let items = chosen.map(\.url)
                Button(t("Upload to Kindle…")) {
                    beginUploadToKindle(items, move: false)
                }
                Button(t("Move to Kindle…")) {
                    beginUploadToKindle(items, move: true)
                }
            }
            Button(t("Copy Path")) { copyPath(urls) }
            Divider()
            Button(t("Move to Trash"), role: .destructive) { confirmDelete(urls) }
        }
    }

    private func localPrimaryAction(_ ids: Set<String>) {
        guard let id = ids.first, let entry = entries.first(where: { $0.path == id }) else { return }
        openEntry(entry)
    }

    private func openEntry(_ entry: LocalEntry) {
        if entry.isDir {
            go(entry.url)
        } else {
            NSWorkspace.shared.open(entry.url)
        }
    }

    private func reload() {
        let token = UUID()
        reloadToken = token
        let directory = currentURL
        Task {
            let loaded = await Task.detached(priority: .userInitiated) {
                listLocal(directory, showHidden: false)
            }.value
            guard token == reloadToken,
                  directory.standardizedFileURL.path == currentURL.standardizedFileURL.path else {
                return
            }
            entries = loaded
            let valid = Set(loaded.map(\.path))
            selection = selection.intersection(valid)
        }
    }

    private func go(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard standardized.path != currentURL.standardizedFileURL.path else { return }
        backStack.append(currentURL)
        forwardStack.removeAll()
        currentURL = standardized
        selection.removeAll()
        search = ""
        reload()
    }

    private func goBack() {
        guard let url = backStack.popLast() else { return }
        forwardStack.append(currentURL)
        currentURL = url
        selection.removeAll()
        reload()
    }

    private func goForward() {
        guard let url = forwardStack.popLast() else { return }
        backStack.append(currentURL)
        currentURL = url
        selection.removeAll()
        reload()
    }

    private func goUp() {
        let parent = currentURL.deletingLastPathComponent()
        if parent.path != currentURL.path { go(parent) }
    }

    private func copySelection(_ ids: Set<String>? = nil) {
        let urls = selectedURLs(for: ids)
        guard !urls.isEmpty else { return }
        clipboard = urls
        clipboardCut = false
        writeFileURLsToPasteboard(urls, cut: false)
        clipboardChangeCount = NSPasteboard.general.changeCount
        status = t("Copied %d item(s)", urls.count)
    }

    private func cutSelection(_ ids: Set<String>? = nil) {
        let urls = selectedURLs(for: ids)
        guard !urls.isEmpty else { return }
        clipboard = urls
        clipboardCut = true
        writeFileURLsToPasteboard(urls, cut: true)
        clipboardChangeCount = NSPasteboard.general.changeCount
        status = t("Cut %d item(s)", urls.count)
    }

    private func selectedURLs(for ids: Set<String>? = nil) -> [URL] {
        if let ids { return entries.filter { ids.contains($0.path) }.map(\.url) }
        return selectionURLs
    }

    private func paste(into destination: URL? = nil) {
        let dest = destination ?? currentURL
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        var sources = pasteboardFileURLs()
        var moving = pasteboardIsCut()
        var fromInternal = false
        if sources.isEmpty {
            guard clipboardChangeCount == changeCount else {
                status = t("Clipboard has no files")
                return
            }
            sources = clipboard
            moving = clipboardCut
            fromInternal = true
        }
        guard !sources.isEmpty else {
            status = t("Clipboard has no files")
            return
        }
        Task {
            let result = await performTransfer(sources, to: dest, copy: !moving)
            if moving && result.ok {
                let unchanged = fromInternal || NSPasteboard.general.changeCount == changeCount
                if unchanged {
                    clipboard = []
                    clipboardCut = false
                    clipboardChangeCount = -1
                    if !fromInternal {
                        NSPasteboard.general.clearContents()
                    }
                }
            }
        }
    }

    private func moveTo(_ urls: [URL]) {
        guard let dest = chooseDirectory(prompt: t("Move")) else { return }
        Task { _ = await performTransfer(urls, to: dest, copy: false) }
    }

    private func copyTo(_ urls: [URL]) {
        guard let dest = chooseDirectory(prompt: t("Copy")) else { return }
        Task { _ = await performTransfer(urls, to: dest, copy: true) }
    }

    private func moveSelectionTo() {
        guard !selectionURLs.isEmpty else { return }
        moveTo(selectionURLs)
    }

    private func duplicate(_ urls: [URL]) {
        Task { _ = await performTransfer(urls, to: currentURL, copy: true) }
    }

    @discardableResult
    private func performTransfer(_ urls: [URL], to destDir: URL, copy: Bool) async -> LocalTransferResult {
        let result = await Task.detached(priority: .userInitiated) {
            LocalFileService.transfer(urls, to: destDir, copy: copy)
        }.value

        reload()
        if result.ok {
            status = t(copy ? "Copied %d item(s) to %@" : "Moved %d item(s) to %@", result.succeeded, destDir.lastPathComponent)
        } else {
            status = result.errors.joined(separator: "; ")
        }
        return result
    }

    private func confirmDelete(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        pendingDelete = urls
        showDelete = true
    }

    private func performDelete() {
        let urls = pendingDelete
        pendingDelete = []
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                LocalFileService.trash(urls)
            }.value
            reload()
            status = result.errors.isEmpty
                ? t("Moved %d item(s) to Trash", result.trashed)
                : result.errors.joined(separator: "; ")
        }
    }

    private func beginRename(_ url: URL) {
        renameTarget = url
        renameText = url.lastPathComponent
        showRename = true
    }

    private func performRename() {
        guard let target = renameTarget else { return }
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        renameTarget = nil
        guard !name.isEmpty, name != target.lastPathComponent else { return }
        let dest = target.deletingLastPathComponent().appendingPathComponent(name)
        do {
            try FileManager.default.moveItem(at: target, to: dest)
            status = t("Renamed to %@", name)
        } catch {
            status = error.localizedDescription
        }
        reload()
    }

    private func createFolder() {
        var name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = t("untitled folder") }
        do {
            let dest = try FileSafety.createDirectoryUnique(in: currentURL, name: name)
            reload()
            selection = [dest.path]
            status = t("Created %@", dest.lastPathComponent)
        } catch {
            status = error.localizedDescription
        }
    }

    private func copyPath(_ urls: [URL]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
        status = t("Copied path(s)")
    }

    private func localEmptyEntries() -> [ContextMenuEntry] {
        [
            .item(t("New Folder…")) {
                newFolderName = t("untitled folder")
                showNewFolder = true
            },
            .item(t("Upload File…")) { showImporter = true },
            .item(t("Paste")) { paste() },
            .separator,
            .item(t("Refresh")) { reload() },
        ]
    }

    private func beginUploadToKindle(_ urls: [URL], move: Bool) {
        let items = urls.filter(\.isFileURL)
        guard !items.isEmpty else {
            status = t("Select file(s) or folder(s) to upload")
            return
        }
        pendingUploadURLs = items
        pendingUploadMove = move
        status = move ? t("Choose a Kindle folder to move to") : t("Choose a Kindle folder to upload to")
        showKindlePicker = true
    }

    private func applyKindleTarget(_ target: DeviceFolder) {
        showKindlePicker = false
        if pendingUploadMove {
            pendingKindleTarget = target
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                showMoveToKindleConfirm = true
            }
        } else {
            performUpload(target, move: false)
        }
    }

    private func performUpload(_ target: DeviceFolder, move: Bool) {
        let urls = pendingUploadURLs
        pendingUploadURLs = []
        pendingKindleTarget = nil
        guard !urls.isEmpty else { return }
        let directories = urls.filter(\.hasDirectoryPath)
        let files = urls.filter { !$0.hasDirectoryPath }
        let count = urls.count
        status = t("Uploading %d item(s)…", count)
        Task {
            var errors: [String] = []

            for directory in directories {
                let result = await store.uploadFolderToKindle(directory, target: target)
                if !result.ok {
                    errors.append(result.message)
                }
            }

            if !files.isEmpty {
                let result = await store.uploadDeviceFilesChecked(
                    files.map(\.path),
                    parent: target.id,
                    storage: target.storageID
                )
                if !result.ok {
                    errors.append(result.message)
                }
            }

            if move && errors.isEmpty {
                let trash = await Task.detached(priority: .userInitiated) {
                    LocalFileService.trash(urls)
                }.value
                reload()
                status = trash.errors.isEmpty
                    ? t("Moved %d item(s) to Kindle", trash.trashed)
                    : trash.errors.joined(separator: "; ")
            } else if errors.isEmpty {
                reload()
                status = t("Uploaded %d item(s) to Kindle", count)
            } else {
                status = errors.joined(separator: "; ")
            }
        }
    }

    private func importExternal(_ urls: [URL]) {
        let dest = currentURL
        let count = urls.count
        status = t("Copying %d item(s)…", count)
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                FilesView.copyIntoLocal(urls, destination: dest)
            }.value
            reload()
            status = result.errors.isEmpty
                ? t("Copied %d item(s)", result.copied)
                : result.errors.joined(separator: "; ")
        }
    }

    nonisolated private static func copyIntoLocal(_ urls: [URL], destination: URL) -> ImportResult {
        var copied = 0
        var errors: [String] = []
        for src in urls where src.isFileURL {
            let access = src.startAccessingSecurityScopedResource()
            defer { if access { src.stopAccessingSecurityScopedResource() } }
            do {
                _ = try FileSafety.copyUnique(src, into: destination)
                copied += 1
            } catch {
                errors.append("\(src.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return ImportResult(copied: copied, errors: errors)
    }
}

// MARK: - Empty-area context menu

struct ContextMenuEntry {
    enum Kind {
        case item
        case separator
    }

    let kind: Kind
    let title: String
    let enabled: Bool
    let action: @MainActor () -> Void

    static func item(
        _ title: String,
        enabled: Bool = true,
        _ action: @escaping @MainActor () -> Void
    ) -> ContextMenuEntry {
        ContextMenuEntry(kind: .item, title: title, enabled: enabled, action: action)
    }

    static var separator: ContextMenuEntry {
        ContextMenuEntry(kind: .separator, title: "", enabled: false, action: {})
    }
}

final class EmptyAreaMenuAction: NSObject, @unchecked Sendable {
    private let handler: @MainActor () -> Void

    init(_ handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    @objc func run() {
        MainActor.assumeIsolated {
            handler()
        }
    }
}

struct EmptyAreaContextMenu: NSViewRepresentable {
    let isActive: Bool
    let entries: @MainActor () -> [ContextMenuEntry]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.install(on: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isActive = isActive
        context.coordinator.entries = entries
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: @unchecked Sendable {
        var isActive = false
        var entries: @MainActor () -> [ContextMenuEntry] = { [] }
        private var monitor: Any?
        private var actions: [EmptyAreaMenuAction] = []
        private weak var view: NSView?

        func install(on view: NSView) {
            self.view = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event in
                guard let self, self.isActive, let anchor = self.view else { return event }
                let box = RightClickEvent(event: event, view: anchor)
                let consumed = MainActor.assumeIsolated {
                    self.handle(box)
                }
                return consumed ? nil : event
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            stop()
        }

        @MainActor
        private func handle(_ box: RightClickEvent) -> Bool {
            guard let window = box.view.window,
                  box.event.window === window,
                  let content = window.contentView,
                  let table = Self.findTable(in: content, at: box.event.locationInWindow)
            else { return false }

            let point = table.convert(box.event.locationInWindow, from: nil)
            guard table.row(at: point) < 0 else { return false }

            return showMenu(box)
        }

        @MainActor
        private func showMenu(_ box: RightClickEvent) -> Bool {
            let items = entries()
            guard !items.isEmpty else { return false }

            actions.removeAll()
            let menu = NSMenu()
            for entry in items {
                switch entry.kind {
                case .separator:
                    menu.addItem(.separator())
                case .item:
                    let action = EmptyAreaMenuAction(entry.action)
                    actions.append(action)
                    let item = NSMenuItem(
                        title: entry.title,
                        action: #selector(EmptyAreaMenuAction.run),
                        keyEquivalent: ""
                    )
                    item.target = action
                    item.isEnabled = entry.enabled
                    menu.addItem(item)
                }
            }
            NSMenu.popUpContextMenu(menu, with: box.event, for: box.view)
            return true
        }

        @MainActor
        private static func findTable(in view: NSView, at windowPoint: NSPoint) -> NSTableView? {
            if let table = view as? NSTableView {
                let point = table.convert(windowPoint, from: nil)
                if table.bounds.contains(point) {
                    return table
                }
            }
            for subview in view.subviews {
                if let found = findTable(in: subview, at: windowPoint) {
                    return found
                }
            }
            return nil
        }
    }
}

final class RightClickEvent: @unchecked Sendable {
    let event: NSEvent
    let view: NSView

    init(event: NSEvent, view: NSView) {
        self.event = event
        self.view = view
    }
}
