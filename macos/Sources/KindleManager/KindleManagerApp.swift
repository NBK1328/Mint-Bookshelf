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
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 960, minHeight: 600)
        }
    }
}

@MainActor
class AppStore: ObservableObject {
    @Published var books: [Book] = []
    @Published var devices: [RawDevice] = []
    @Published var deviceFiles: [DeviceFile] = []
    @Published var section: String = "library"
    @Published var convertInput: String = ""
    @Published var convertOutput: String = ""
    @Published var convertResult: String = ""
    @Published var selectedBook: Book?
    @Published var operations: [Operation] = []
    @Published var deviceStatus: String = ""
    @Published var deviceLoading = false
    @Published var deviceRevision = 0
    @Published var libraryScanning = false
    @Published var lastError: String?
    @Published var libraryStatus: String = ""

    private let deviceQueue = DispatchQueue(label: "com.kindlemanager.device", qos: .userInitiated)
    private let libraryQueue = DispatchQueue(label: "com.kindlemanager.library", qos: .userInitiated)
    private var refreshInFlight = false

    init() {
        let initRaw = kmString(KM_Initialize(nil))
        if let data = initRaw.data(using: .utf8),
           let payload = try? JSONDecoder().decode(InitPayload.self, from: data) {
            if !payload.ok {
                lastError = payload.error ?? "Initialization failed"
            }
        } else {
            lastError = "Initialization failed"
        }
        reloadBooks()
        reloadOperations()
        refreshDevice()
    }

    func reloadBooks() {
        do {
            books = try loadBooks()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func reloadOperations() {
        do {
            operations = try loadOperations()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func scanLibrary(_ path: String) async -> ScanResult {
        libraryScanning = true
        let raw = await withCheckedContinuation { continuation in
            libraryQueue.async {
                continuation.resume(returning: kmString(withCStr(path) { KM_LibraryScan($0) }))
            }
        }
        libraryScanning = false

        guard let data = raw.data(using: .utf8),
              let payload = try? JSONDecoder().decode(ScanPayload.self, from: data) else {
            let message = "Scan failed: invalid response"
            lastError = message
            libraryStatus = message
            return ScanResult(ok: false, added: 0, error: message)
        }
        guard payload.ok else {
            let message = payload.error ?? "Scan failed"
            lastError = message
            libraryStatus = message
            return ScanResult(ok: false, added: 0, error: message)
        }

        reloadBooks()
        let added = payload.added ?? 0
        let message = "Scanned \(payload.scanned ?? added) · added \(added) · updated \(payload.updated ?? 0) · removed \(payload.deleted ?? 0)"
        libraryStatus = message
        return ScanResult(ok: true, added: added, error: nil)
    }

    func cancelOperation(_ id: String) async -> String {
        let result = await withCheckedContinuation { continuation in
            libraryQueue.async {
                continuation.resume(returning: kmString(withCStr(id) { KM_OperationCancel($0) }))
            }
        }
        reloadOperations()
        return result
    }

    func startConversion(input: String, output: String, format: String) async -> String {
        let result = await withCheckedContinuation { continuation in
            libraryQueue.async {
                continuation.resume(returning: kmString(withCStr(input) { inputPtr in
                    withCStr(output) { outputPtr in
                        withCStr(format) { formatPtr in
                            KM_ConvertBook(inputPtr, outputPtr, formatPtr)
                        }
                    }
                }))
            }
        }
        reloadOperations()
        return result
    }

    func refreshDevice() {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        deviceLoading = true
        Task {
            let loaded = await runOnDeviceQueue { loadDevicesResult() }
            if let error = loaded.error {
                devices = []
                deviceFiles = []
                deviceStatus = "Discovery failed: \(error)"
                lastError = error
                deviceLoading = false
                refreshInFlight = false
                return
            }

            let kindleDevices = loaded.devices.filter { $0.vendorID == 0x1949 }
            devices = kindleDevices
            deviceRevision += 1

            guard let device = kindleDevices.first else {
                deviceFiles = []
                deviceStatus = "No Kindle connected"
                deviceLoading = false
                refreshInFlight = false
                return
            }

            deviceStatus = "Opening Kindle…"
            let (files, status) = await runOnDeviceQueue {
                AppStore.openAndListDevice(device)
            }
            deviceFiles = files
            deviceStatus = status
            deviceLoading = false
            refreshInFlight = false
            deviceRevision += 1
        }
    }

    nonisolated private static func openAndListDevice(_ device: RawDevice) -> ([DeviceFile], String) {
        let info = connectDevice(device)
        guard isOK(info) else { return ([], "Connect failed: \(info)") }
        let (files, error) = loadDeviceFilesResult()
        if let error {
            return (files, "Kindle connected, listing failed: \(error)")
        }
        return (files, "Kindle connected · \(files.count) objects")
    }

    func reloadDeviceFiles() async {
        let (files, error) = await runOnDeviceQueue { loadDeviceFilesResult() }
        deviceFiles = files
        deviceRevision += 1
        if let error {
            deviceStatus = "Listing failed: \(error)"
            lastError = error
        }
    }

    private func runOnDeviceQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            deviceQueue.async {
                continuation.resume(returning: work())
            }
        }
    }

    func uploadDeviceFiles(_ paths: [String], parent: UInt32, storage: UInt32) async -> String {
        await uploadDeviceFilesChecked(paths, parent: parent, storage: storage).message
    }

    func uploadDeviceFilesChecked(_ paths: [String], parent: UInt32, storage: UInt32) async -> OpResult {
        let result = await runOnDeviceQueue { () -> OpResult in
            var errors: [String] = []
            for path in paths {
                let r = kmString(withCStr(path) { KM_DeviceUploadBook($0, parent, storage) })
                if !isOK(r) { errors.append("\(path): \(r)") }
            }
            return OpResult(
                ok: errors.isEmpty,
                message: errors.isEmpty
                    ? "Uploaded \(paths.count) file(s) to Kindle"
                    : errors.joined(separator: "; ")
            )
        }
        await reloadDeviceFiles()
        deviceStatus = result.message
        return result
    }

    func downloadDeviceFile(_ id: UInt32, to path: String) async -> String {
        let result = await runOnDeviceQueue { () -> String in
            kmString(withCStr(path) { KM_DeviceDownloadBook(id, $0) })
        }
        deviceStatus = result
        return result
    }

    func openDeviceFile(_ file: DeviceFile) async -> String {
        let tmp: URL
        do {
            tmp = try FileSafety.temporaryDownloadURL(for: file.name)
        } catch {
            let message = "Open failed: \(error.localizedDescription)"
            deviceStatus = message
            return message
        }
        let id = file.id
        let result = await runOnDeviceQueue { () -> String in
            kmString(withCStr(tmp.path) { KM_DeviceDownloadBook(id, $0) })
        }
        if isOK(result) {
            NSWorkspace.shared.open(tmp)
            deviceStatus = "Opened \(file.name)"
            return "Opened \(file.name)"
        }
        deviceStatus = result
        return result
    }

    func deleteDeviceObjects(_ ids: [UInt32]) async -> String {
        await deleteDeviceObjectsChecked(ids).message
    }

    func deleteDeviceObjectsChecked(_ ids: [UInt32]) async -> OpResult {
        let result = await runOnDeviceQueue { () -> OpResult in
            var errors: [String] = []
            for id in ids {
                let r = kmString(KM_DeviceDeleteBook(id))
                if !isOK(r) { errors.append(r) }
            }
            return OpResult(
                ok: errors.isEmpty,
                message: errors.isEmpty ? "Deleted \(ids.count) item(s)" : errors.joined(separator: "; ")
            )
        }
        await reloadDeviceFiles()
        deviceStatus = result.message
        return result
    }

    func moveDeviceObjects(_ ids: [UInt32], to folder: DeviceFolder, copy: Bool = false) async -> String {
        let result = await runOnDeviceQueue { () -> String in
            var errors: [String] = []
            for id in ids {
                let r = copy
                    ? kmString(KM_DeviceCopyBook(id, folder.storageID, folder.id))
                    : kmString(KM_DeviceMoveBook(id, folder.storageID, folder.id))
                if !isOK(r) { errors.append(r) }
            }
            return errors.isEmpty
                ? "\(copy ? "Copied" : "Moved") \(ids.count) item(s) to \(folder.label)"
                : errors.joined(separator: "; ")
        }
        await reloadDeviceFiles()
        deviceStatus = result
        return result
    }

    func createDeviceFolder(_ name: String, parent: UInt32, storage: UInt32) async -> String {
        let result = await runOnDeviceQueue { () -> String in
            kmString(withCStr(name) { KM_DeviceCreateFolder($0, parent, storage) })
        }
        await reloadDeviceFiles()
        deviceStatus = result
        return result
    }

    func renameDeviceObject(_ id: UInt32, to name: String) async -> String {
        let result = await runOnDeviceQueue { () -> String in
            kmString(withCStr(name) { KM_DeviceRenameBook(id, $0) })
        }
        await reloadDeviceFiles()
        deviceStatus = result
        return result
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

struct ScanPayload: Decodable {
    let ok: Bool
    let scanned: Int?
    let added: Int?
    let updated: Int?
    let deleted: Int?
    let error: String?
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
    let format: String
    let size: Int64
    let path: String?
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
    var url: URL { URL(fileURLWithPath: path) }
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

let bookExtensions: Set<String> = [
    "epub", "mobi", "azw", "azw3", "pdf", "fb2", "txt", "djvu",
    "cbz", "cbr", "kepub", "doc", "docx", "rtf", "html", "htm", "lit", "pdb"
]

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

func deviceFolders(_ files: [DeviceFile]) -> [DeviceFolder] {
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
    out.insert(DeviceFolder(id: 0, storageID: 0, label: "Kindle (root)"), at: 0)
    return out
}

struct ContentView: View {
    @ObservedObject var store: AppStore
    var body: some View {
        NavigationSplitView {
            List(selection: $store.section) {
                Label("Library", systemImage: "books.vertical").tag("library")
                Label("Kindle", systemImage: "cable.connector").tag("devices")
                Label("Files", systemImage: "folder").tag("files")
                Label("Convert", systemImage: "arrow.2.circlepath").tag("convert")
                Label("Queue", systemImage: "list.bullet").tag("queue")
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            switch store.section {
            case "library": LibraryView(store: store)
            case "devices": DevicesView(store: store)
            case "convert": ConvertView(store: store)
            case "files": FilesView(store: store)
            default: QueueView(store: store)
            }
        }
        .alert("Kindle Manager", isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
    }
}

struct LibraryView: View {
    @ObservedObject var store: AppStore
    @State private var search = ""
    @State private var sortAscending = true

    private var filteredBooks: [Book] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        var list = store.books
        if !query.isEmpty {
            list = list.filter {
                $0.title.localizedCaseInsensitiveContains(query)
                    || $0.author.localizedCaseInsensitiveContains(query)
                    || $0.format.localizedCaseInsensitiveContains(query)
            }
        }
        return list.sorted {
            let result = $0.title.localizedCaseInsensitiveCompare($1.title)
            return sortAscending ? result == .orderedAscending : result == .orderedDescending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            List(filteredBooks, selection: $store.selectedBook) { book in
                HStack {
                    Image(systemName: "book.closed.fill").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(book.title).font(.headline).lineLimit(1)
                        Text("\(book.author.isEmpty ? "Unknown author" : book.author) · \(book.format.uppercased())")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if let p = book.path {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)])
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                        .help("Reveal in Finder")
                    }
                }
                .padding(.vertical, 2)
            }
            .searchable(text: $search, prompt: "Search books")
            if !store.libraryStatus.isEmpty {
                Divider()
                Text(store.libraryStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
            }
        }
        .toolbar {
            Button("Add Folder…") {
                guard let url = chooseDirectory(prompt: "Scan") else { return }
                Task { _ = await store.scanLibrary(url.path) }
            }
            .disabled(store.libraryScanning)
            Button(sortAscending ? "Sort A–Z" : "Sort Z–A") {
                sortAscending.toggle()
            }
            Button("Reload") { store.reloadBooks() }
        }
    }
}

struct QueueView: View {
    @ObservedObject var store: AppStore
    var body: some View {
        List(store.operations) { op in
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(op.title).font(.headline)
                    Text("\(op.type) · \(op.status) · \(Int(op.progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if op.status == "pending" || op.status == "running" {
                    Button("Cancel") {
                        Task { _ = await store.cancelOperation(op.id) }
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .toolbar {
            Button("Refresh") { store.reloadOperations() }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                store.reloadOperations()
            }
        }
    }
}

struct ConvertView: View {
    @ObservedObject var store: AppStore
    @State private var format = "azw3"
    @State private var busy = false

    private let formats = ["azw3", "epub", "mobi", "pdf", "txt"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Input") {
                HStack {
                    Text(store.convertInput.isEmpty ? "No file selected" : store.convertInput)
                        .lineLimit(1)
                    Spacer()
                    Button("Choose…") {
                        guard let url = chooseOpenFile(prompt: "Input") else { return }
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
            }

            GroupBox("Output") {
                HStack {
                    Text(store.convertOutput.isEmpty ? "No output selected" : store.convertOutput)
                        .lineLimit(1)
                    Spacer()
                    Button("Choose…") {
                        let base = store.convertInput.isEmpty
                            ? "book"
                            : URL(fileURLWithPath: store.convertInput).deletingPathExtension().lastPathComponent
                        guard let url = chooseSaveURL(name: "\(base).\(format)") else { return }
                        store.convertOutput = url.path
                    }
                }
            }

            Picker("Format", selection: $format) {
                ForEach(formats, id: \.self) { value in
                    Text(value.uppercased()).tag(value)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Button("Convert") { start() }
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
            Spacer()
        }
        .padding()
    }

    private func start() {
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
                store.convertResult = "Conversion queued"
                store.section = "queue"
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
    @State private var newFolderName = "New Folder"

    @State private var showDelete = false
    @State private var pendingDelete: [DeviceFile] = []
    @State private var showUpload = false

    @State private var showMoveToLocal = false
    @State private var pendingLocalMove: [DeviceFile] = []
    @State private var localMoveDir: URL?
    @State private var listHovered = false

    var body: some View {
        VStack(spacing: 0) {
            if store.devices.isEmpty && !store.deviceLoading {
                ContentUnavailableView(
                    "No Kindle Connected",
                    systemImage: "cable.connector",
                    description: Text("Connect your Kindle with a USB cable and press Refresh.")
                )
            } else {
                actionBar
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
                        .padding(.vertical, 1)
                        .tag(node.id)
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
                        ProgressView("Loading Kindle…")
                            .padding()
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            Divider()
            HStack {
                if store.deviceLoading {
                    ProgressView().controlSize(.small)
                }
                Text(status.isEmpty ? store.deviceStatus : status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if !store.devices.isEmpty {
                    Text("\(selection.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .toolbar {
            Button("Refresh") { refresh() }
            Button("New Folder…") { newFolderName = "New Folder"; showNewFolder = true }
            Button("Upload…") { showUpload = true }
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
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Name", text: $newFolderName)
            Button("Create") { createFolder() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename", isPresented: $showRename) {
            TextField("Name", text: $renameText)
            Button("Rename") { performRename() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete from Kindle?", isPresented: $showDelete) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) { pendingDelete = [] }
        } message: {
            Text("\(pendingDelete.count) item(s) will be permanently deleted from the device.")
        }
        .alert("Move to Mac?", isPresented: $showMoveToLocal) {
            Button("Move", role: .destructive) { performMoveToLocal() }
            Button("Cancel", role: .cancel) {
                pendingLocalMove = []
                localMoveDir = nil
            }
        } message: {
            Text("\(pendingLocalMove.count) file(s) will be copied to your Mac and deleted from Kindle.")
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

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button {
                newFolderName = "New Folder"
                showNewFolder = true
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            Button {
                showUpload = true
            } label: {
                Label("Upload", systemImage: "arrow.up.doc")
            }
            Button {
                downloadSelected()
            } label: {
                Label("Download", systemImage: "arrow.down.doc")
            }
            .disabled(selection.isEmpty || selectedFiles.allSatisfy { $0.isFolder })
            Button {
                downloadSelectedToFolder()
            } label: {
                Label("Download to Folder", systemImage: "arrow.down.doc.on.clipboard")
            }
            .disabled(selection.isEmpty)
            Button {
                beginTransfer(selectedFiles, copy: false)
            } label: {
                Label("Move", systemImage: "arrow.right.doc.on.clipboard")
            }
            .disabled(selection.isEmpty)
            Button {
                beginTransfer(selectedFiles, copy: true)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .disabled(selection.isEmpty)
            Button {
                pasteIntoKindle()
            } label: {
                Label("Paste", systemImage: "doc.on.clipboard")
            }
            Button(role: .destructive) {
                confirmDelete(selectedFiles)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(selection.isEmpty)
            Spacer()
            Button {
                refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(store.deviceLoading)
        }
        .padding(8)
        .disabled(store.deviceLoading)
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
            Button("New Folder…") { newFolderName = "New Folder"; showNewFolder = true }
            Button("Upload File…") { showUpload = true }
            Button(selectedFolder.map { "Paste into \($0.name)" } ?? "Paste") { pasteIntoKindle() }
            Divider()
            Button("Refresh") { refresh() }
        } else {
            if chosen.count == 1, let f = chosen.first {
                if !f.isFolder {
                    Button("Open") {
                        Task { status = await store.openDeviceFile(f) }
                    }
                    Button("Download…") { download(f) }
                } else {
                    Button("New Folder Here…") {
                        newFolderName = "New Folder"
                        showNewFolder = true
                    }
                }
                Button("Rename…") {
                    renameID = f.id
                    renameText = f.name
                    showRename = true
                }
                if f.isFolder {
                    Button("Paste Into \(f.name)") { pasteIntoKindle(into: f) }
                }
                Divider()
            }
            Button("Download to Folder…") { downloadToFolder(chosen) }
            if chosen.contains(where: { !$0.isFolder }) {
                Button("Move to Local Folder…") {
                    beginMoveToLocal(chosen.filter { !$0.isFolder })
                }
            }
            Button("Copy To…") { beginTransfer(chosen, copy: true) }
            Button("Move To…") { beginTransfer(chosen, copy: false) }
            Divider()
            Button("Delete…", role: .destructive) { confirmDelete(chosen) }
        }
    }

    private func devicePrimaryAction(_ ids: Set<UInt32>) {
        guard ids.count == 1,
              let f = store.deviceFiles.first(where: { $0.id == ids.first! }),
              !f.isFolder else { return }
        Task { status = await store.openDeviceFile(f) }
    }

    private func rebuild() {
        tree = buildDeviceTree(from: store.deviceFiles)
        folders = deviceFolders(store.deviceFiles)
        selection = selection.intersection(Set(store.deviceFiles.map(\.id)))
    }

    private func refresh() {
        store.refreshDevice()
    }

    private func kindleEmptyEntries() -> [ContextMenuEntry] {
        [
            .item("New Folder…") {
                newFolderName = "New Folder"
                showNewFolder = true
            },
            .item("Upload File…") { showUpload = true },
            .item(selectedFolder.map { "Paste into \($0.name)" } ?? "Paste") {
                pasteIntoKindle()
            },
            .separator,
            .item("Refresh") { refresh() },
        ]
    }

    private func pasteIntoKindle(into folder: DeviceFile? = nil) {
        let urls = pasteboardFileURLs().filter { !$0.hasDirectoryPath }
        guard !urls.isEmpty else {
            status = "Clipboard has no files"
            return
        }
        let moving = pasteboardIsCut()
        let target: (id: UInt32, storage: UInt32) = folder.map { ($0.id, $0.storageID) } ?? targetFolder
        let count = urls.count
        status = moving ? "Moving \(count) file(s)…" : "Uploading \(count) file(s)…"
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
                    ? "Moved \(trash.trashed) file(s) to Kindle"
                    : trash.errors.joined(separator: "; ")
            } else {
                status = result.message
            }
        }
    }

    private func dropUpload(_ urls: [URL]) -> Bool {
        let files = urls.filter { $0.isFileURL && !$0.hasDirectoryPath }
        guard !files.isEmpty else { return false }
        let target = targetFolder
        status = "Uploading \(files.count) file(s)…"
        Task {
            status = await store.uploadDeviceFiles(
                files.map(\.path),
                parent: target.id,
                storage: target.storage
            )
        }
        return true
    }

    private func downloadSelectedToFolder() {
        downloadToFolder(selectedFiles)
    }

    private func downloadToFolder(_ roots: [DeviceFile]) {
        guard !roots.isEmpty else { return }
        guard let dir = chooseDirectory(prompt: "Download") else { return }
        let items = DevicesView.flattenFiles(roots, all: store.deviceFiles)
        guard !items.isEmpty else {
            status = "Nothing to download"
            return
        }
        status = "Downloading \(items.count) file(s)…"
        Task {
            var errors: [String] = []
            var done = 0
            for item in items {
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
            }
            status = errors.isEmpty
                ? "Downloaded \(done) file(s) to \(dir.lastPathComponent)"
                : errors.joined(separator: "; ")
        }
    }

    private func beginMoveToLocal(_ files: [DeviceFile]) {
        guard !files.isEmpty else {
            status = "Select file(s) to move"
            return
        }
        guard let dir = chooseDirectory(prompt: "Move") else { return }
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
        status = "Moving \(files.count) file(s)…"
        Task {
            var downloaded: [DeviceFile] = []
            var errors: [String] = []
            for f in files {
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
            }
            if !downloaded.isEmpty {
                let result = await store.deleteDeviceObjectsChecked(downloaded.map(\.id))
                if !result.ok { errors.append(result.message) }
            }
            status = errors.isEmpty
                ? "Moved \(downloaded.count) file(s) to \(dir.lastPathComponent)"
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
            status = errors.isEmpty ? "Downloaded \(destinations.count) file(s)" : errors.joined(separator: "; ")
        }
    }

    private func beginTransfer(_ files: [DeviceFile], copy: Bool) {
        guard !files.isEmpty else { return }
        pickerFiles = files
        pickerCopy = copy
        pickerTitle = copy ? "Copy \(files.count) item(s) to…" : "Move \(files.count) item(s) to…"
        folders = deviceFolders(store.deviceFiles)
        showPicker = true
    }

    private func applyTransfer(to target: DeviceFolder) {
        let folderIDs = Set(pickerFiles.filter(\.isFolder).map(\.id))
        if !folderIDs.isEmpty && isDeviceDescendant(target.id, of: folderIDs) {
            status = "Cannot move or copy a folder into itself"
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

        let parents = Set(store.deviceFiles.map(\.parentID))
        if files.contains(where: { $0.isFolder && parents.contains($0.id) }) {
            status = "Folder is not empty; delete its contents first"
            return
        }

        pendingDelete = files
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

struct DeviceFolderPicker: View {
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
                Button("Cancel", action: onCancel)
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
    @State private var showHidden = false
    @State private var booksOnly = false
    @State private var search = ""
    @State private var status = ""

    @State private var clipboard: [URL] = []
    @State private var clipboardCut = false

    @State private var showImporter = false
    @State private var pendingDelete: [URL] = []
    @State private var showDelete = false
    @State private var listHovered = false

    @State private var showKindlePicker = false
    @State private var pendingUploadURLs: [URL] = []
    @State private var pendingUploadMove = false
    @State private var pendingKindleTarget: DeviceFolder?
    @State private var showMoveToKindleConfirm = false

    @State private var renameTarget: URL?
    @State private var renameText = ""
    @State private var showRename = false

    @State private var newFolderName = "untitled folder"
    @State private var showNewFolder = false

    private var favorites: [Place] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            Place(name: "Home", icon: "house", url: home, group: "favorites"),
            Place(name: "Desktop", icon: "menubar.dock.rectangle", url: home.appendingPathComponent("Desktop"), group: "favorites"),
            Place(name: "Documents", icon: "doc.text", url: home.appendingPathComponent("Documents"), group: "favorites"),
            Place(name: "Downloads", icon: "arrow.down.circle", url: home.appendingPathComponent("Downloads"), group: "favorites"),
            Place(name: "Applications", icon: "app", url: URL(fileURLWithPath: "/Applications"), group: "favorites"),
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
        if booksOnly {
            list = list.filter { $0.isDir || bookExtensions.contains($0.url.pathExtension.lowercased()) }
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
                .frame(minWidth: 160, idealWidth: 185, maxWidth: 240)

            VStack(spacing: 0) {
                navigationBar
                Divider()
                actionBar
                Divider()
                fileList
                Divider()
                statusBar
            }
            .frame(minWidth: 520)
        }
        .onAppear { reload() }
        .onChange(of: showHidden) { _, _ in reload() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data]) { result in
            guard case .success(let url) = result else { return }
            let ok = url.startAccessingSecurityScopedResource()
            beginUploadToKindle([url], move: false)
            if ok { url.stopAccessingSecurityScopedResource() }
        }
        .sheet(isPresented: $showKindlePicker) {
            DeviceFolderPicker(
                title: pendingUploadMove
                    ? "Move \(pendingUploadURLs.count) file(s) to…"
                    : "Upload \(pendingUploadURLs.count) file(s) to…",
                folders: deviceFolders(store.deviceFiles)
            ) { target in
                applyKindleTarget(target)
            } onCancel: {
                showKindlePicker = false
                pendingUploadURLs = []
            }
        }
        .alert("Move to Kindle?", isPresented: $showMoveToKindleConfirm) {
            Button("Move", role: .destructive) {
                if let target = pendingKindleTarget {
                    performUpload(target, move: true)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingUploadURLs = []
                pendingKindleTarget = nil
            }
        } message: {
            Text("The local copy of \(pendingUploadURLs.count) file(s) will be moved to Trash after a successful upload.")
        }
    }

    private var sidebar: some View {
        List {
            Section("Favorites") {
                ForEach(favorites) { place in
                    sidebarRow(place)
                }
            }
            Section("Volumes") {
                ForEach(volumes) { place in
                    sidebarRow(place)
                }
            }
        }
        .listStyle(.sidebar)
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
                .help("Back")
            Button { goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(forwardStack.isEmpty)
                .help("Forward")
            Button { goUp() } label: { Image(systemName: "arrow.up") }
                .disabled(currentURL.path == "/")
                .help("Parent folder")

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

            TextField("Search", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)

            Toggle("Books", isOn: $booksOnly)
                .toggleStyle(.button)
                .help("Show only book files")
            Toggle("Hidden", isOn: $showHidden)
                .toggleStyle(.button)
                .help("Show hidden files")
        }
        .padding(8)
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Name", text: $newFolderName)
            Button("Create") { createFolder() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button {
                newFolderName = "untitled folder"
                showNewFolder = true
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            Button {
                if selection.isEmpty {
                    showImporter = true
                } else {
                    beginUploadToKindle(selectedEntries.filter { !$0.isDir }.map(\.url), move: false)
                }
            } label: {
                Label("Upload to Kindle", systemImage: "arrow.up.doc")
            }
            Button {
                copySelection()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .disabled(selection.isEmpty)
            Button {
                cutSelection()
            } label: {
                Label("Cut", systemImage: "scissors")
            }
            .disabled(selection.isEmpty)
            Button {
                paste()
            } label: {
                Label("Paste", systemImage: "doc.on.clipboard")
            }
            Button {
                moveSelectionTo()
            } label: {
                Label("Move To…", systemImage: "arrow.right.doc.on.clipboard")
            }
            .disabled(selection.isEmpty)
            Button(role: .destructive) {
                confirmDelete(selectionURLs)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(selection.isEmpty)
            Spacer()
            Button {
                reload()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .alert("Move to Trash?", isPresented: $showDelete) {
            Button("Move to Trash", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) { pendingDelete = [] }
        } message: {
            Text("\(pendingDelete.count) item(s) will be moved to the Trash.")
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
                .padding(.vertical, 1)
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
        .alert("Rename", isPresented: $showRename) {
            TextField("Name", text: $renameText)
            Button("Rename") { performRename() }
            Button("Cancel", role: .cancel) { renameTarget = nil }
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
            Text("\(filtered.count) items")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !selection.isEmpty {
                Text("· \(selection.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
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
            Button("New Folder…") {
                newFolderName = "untitled folder"
                showNewFolder = true
            }
            Button("Paste") { paste() }
            Divider()
            Toggle("Show Hidden Files", isOn: $showHidden)
            Button("Refresh") { reload() }
        } else {
            let urls = chosen.map(\.url)
            if chosen.count == 1, let entry = chosen.first {
                Button(entry.isDir ? "Open" : "Open") {
                    openEntry(entry)
                }
                Button("Open in Finder") {
                    if entry.isDir {
                        NSWorkspace.shared.open(entry.url)
                    } else {
                        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
                    }
                }
                if entry.isDir {
                    Button("Paste Into \(entry.name)") { paste(into: entry.url) }
                }
                Divider()
            }
            Button("Copy") { copySelection(ids) }
            Button("Cut") { cutSelection(ids) }
            Button("Paste") { paste() }
            Divider()
            Button("Move to…") { moveTo(urls) }
            Button("Copy to…") { copyTo(urls) }
            if chosen.count == 1, let entry = chosen.first {
                Button("Rename…") { beginRename(entry.url) }
                Button("Duplicate") { duplicate(urls) }
            }
            Divider()
            if chosen.contains(where: { !$0.isDir }) {
                let files = chosen.filter { !$0.isDir }.map(\.url)
                Button("Upload to Kindle…") {
                    beginUploadToKindle(files, move: false)
                }
                Button("Move to Kindle…") {
                    beginUploadToKindle(files, move: true)
                }
            }
            Button("Copy Path") { copyPath(urls) }
            Divider()
            Button("Move to Trash", role: .destructive) { confirmDelete(urls) }
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
        entries = listLocal(currentURL, showHidden: showHidden)
        let valid = Set(entries.map(\.path))
        selection = selection.intersection(valid)
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
        status = "Copied \(urls.count) item(s)"
    }

    private func cutSelection(_ ids: Set<String>? = nil) {
        let urls = selectedURLs(for: ids)
        guard !urls.isEmpty else { return }
        clipboard = urls
        clipboardCut = true
        writeFileURLsToPasteboard(urls, cut: true)
        status = "Cut \(urls.count) item(s)"
    }

    private func selectedURLs(for ids: Set<String>? = nil) -> [URL] {
        if let ids { return entries.filter { ids.contains($0.path) }.map(\.url) }
        return selectionURLs
    }

    private func paste(into destination: URL? = nil) {
        let dest = destination ?? currentURL
        var sources = pasteboardFileURLs()
        var moving = pasteboardIsCut()
        if sources.isEmpty {
            sources = clipboard
            moving = clipboardCut
        }
        guard !sources.isEmpty else {
            status = "Clipboard has no files"
            return
        }
        Task {
            let result = await performTransfer(sources, to: dest, copy: !moving)
            if moving && result.ok {
                clipboard = []
                clipboardCut = false
                NSPasteboard.general.clearContents()
            }
        }
    }

    private func moveTo(_ urls: [URL]) {
        guard let dest = chooseDirectory(prompt: "Move") else { return }
        Task { _ = await performTransfer(urls, to: dest, copy: false) }
    }

    private func copyTo(_ urls: [URL]) {
        guard let dest = chooseDirectory(prompt: "Copy") else { return }
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
            status = "\(copy ? "Copied" : "Moved") \(result.succeeded) item(s) to \(destDir.lastPathComponent)"
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
                ? "Moved \(result.trashed) item(s) to Trash"
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
            status = "Renamed to \(name)"
        } catch {
            status = error.localizedDescription
        }
        reload()
    }

    private func createFolder() {
        var name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "untitled folder" }
        do {
            let dest = try FileSafety.createDirectoryUnique(in: currentURL, name: name)
            reload()
            selection = [dest.path]
            status = "Created \(dest.lastPathComponent)"
        } catch {
            status = error.localizedDescription
        }
    }

    private func copyPath(_ urls: [URL]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
        status = "Copied path(s)"
    }

    private func localEmptyEntries() -> [ContextMenuEntry] {
        [
            .item("New Folder…") {
                newFolderName = "untitled folder"
                showNewFolder = true
            },
            .item("Paste") { paste() },
            .separator,
            .item("Show Hidden Files") { showHidden.toggle() },
            .item("Refresh") { reload() },
        ]
    }

    private func beginUploadToKindle(_ urls: [URL], move: Bool) {
        let files = urls.filter { $0.isFileURL && !$0.hasDirectoryPath }
        guard !files.isEmpty else {
            status = "Select file(s) to upload"
            return
        }
        pendingUploadURLs = files
        pendingUploadMove = move
        status = move ? "Choose a Kindle folder to move to" : "Choose a Kindle folder to upload to"
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
        let paths = urls.map(\.path)
        let count = urls.count
        status = "Uploading \(count) file(s)…"
        Task {
            let result = await store.uploadDeviceFilesChecked(
                paths,
                parent: target.id,
                storage: target.storageID
            )
            if move && result.ok {
                let trash = await Task.detached(priority: .userInitiated) {
                    LocalFileService.trash(urls)
                }.value
                reload()
                status = trash.errors.isEmpty
                    ? "Moved \(trash.trashed) file(s) to Kindle"
                    : trash.errors.joined(separator: "; ")
            } else {
                status = result.message
            }
        }
    }

    private func importExternal(_ urls: [URL]) {
        let dest = currentURL
        let count = urls.count
        status = "Copying \(count) item(s)…"
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                FilesView.copyIntoLocal(urls, destination: dest)
            }.value
            reload()
            status = result.errors.isEmpty
                ? "Copied \(result.copied) item(s)"
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
