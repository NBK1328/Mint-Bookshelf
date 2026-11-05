import SwiftUI
@preconcurrency import AppKit
import MintBookshelfSupport

@MainActor
class AppStore: ObservableObject {
    @Published var books: [Book] = []
    @Published var libraryRoot: String? = UserDefaults.standard.string(forKey: "libraryRoot") {
        didSet {
            if let root = libraryRoot {
                UserDefaults.standard.set(root, forKey: "libraryRoot")
            } else {
                UserDefaults.standard.removeObject(forKey: "libraryRoot")
            }
        }
    }
    @Published var language: AppLanguage = AppLanguage(
        rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? ""
    ) ?? AppLanguage.preferred {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "appLanguage") }
    }
    @Published var theme: AppTheme = AppTheme(
        rawValue: UserDefaults.standard.string(forKey: "appTheme") ?? ""
    ) ?? .dark {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "appTheme") }
    }
    @Published var devices: [RawDevice] = []
    @Published var legacyKindleVolume: URL?
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
    @Published var selectedDeviceKey: String?
    @Published var deviceState: String = "disconnected"
    @Published var deviceTransferActive = false
    @Published var deviceTransferCancelled = false
    @Published var deviceTransferDone = 0
    @Published var deviceTransferTotal = 0
    @Published var deviceTransferBytesSent: UInt64 = 0
    @Published var deviceTransferBytesTotal: UInt64 = 0

    private let deviceQueue = DispatchQueue(label: "com.mintbookshelf.device", qos: .userInitiated)
    private let progressQueue = DispatchQueue(label: "com.mintbookshelf.progress", qos: .utility)
    private var monitorTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?
    private let libraryQueue = DispatchQueue(label: "com.mintbookshelf.library", qos: .userInitiated)
    private var refreshInFlight = false

    private func migrateLegacyPreferences() {
        guard let legacy = UserDefaults(suiteName: "com.kindlemanager.app") else { return }
        let current = UserDefaults.standard
        if current.object(forKey: "libraryRoot") == nil,
           let root = legacy.string(forKey: "libraryRoot") {
            libraryRoot = root
        }
        if current.object(forKey: "appLanguage") == nil,
           let raw = legacy.string(forKey: "appLanguage"),
           let value = AppLanguage(rawValue: raw) {
            language = value
        }
        if current.object(forKey: "appTheme") == nil,
           let raw = legacy.string(forKey: "appTheme"),
           let value = AppTheme(rawValue: raw) {
            theme = value
        }
    }

    init() {
        migrateLegacyPreferences()
        FileSafety.cleanupTemporaryDownloads()
        let initRaw = kmString(KM_Initialize(nil))
        if let data = initRaw.data(using: .utf8),
           let payload = try? JSONDecoder().decode(InitPayload.self, from: data) {
            if !payload.ok {
                lastError = payload.error.map { localizedError($0) } ?? t("Initialization failed")
            }
        } else {
            lastError = t("Initialization failed")
        }
        reloadBooks()
        reloadOperations()
        refreshDevice()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self else { return }
                if self.devices.isEmpty {
                    self.refreshDevice()
                }
            }
        }
    }

    deinit {
        monitorTask?.cancel()
        progressTask?.cancel()
    }

    func t(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.text(key, language, arguments: arguments)
    }

    func localizedError(_ text: String) -> String {
        L10n.error(text, language)
    }

    func toggleTheme() {
        theme = theme == .dark ? .light : .dark
    }

    func reloadBooks() {
        guard let root = libraryRoot, root.hasPrefix("/"), root != "/" else {
            books = []
            return
        }
        do {
            books = try loadBooks().filter { book in
                guard let path = book.path else { return false }
                return pathIsUnderRoot(path, root: root)
            }
        } catch {
            lastError = localizedError(error.localizedDescription)
        }
    }

    func rescanLibrary() async -> ScanResult? {
        guard let root = libraryRoot else { return nil }
        return await scanLibrary(root)
    }

    func openLibrary(at url: URL) async -> ScanResult {
        let root = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard root != "/" else {
            let message = t("The filesystem root cannot be used as the library.")
            lastError = message
            libraryStatus = message
            return ScanResult(ok: false, added: 0, error: message)
        }
        libraryRoot = root
        selectedBook = nil
        return await scanLibrary(root)
    }

    func reloadOperations(silent: Bool = false) {
        do {
            operations = try loadOperations()
        } catch {
            if !silent {
                lastError = localizedError(error.localizedDescription)
            }
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

        do {
            let payload = try decodeEnvelope(raw, as: ScanData.self)
            reloadBooks()
            let added = payload.added ?? 0
            let scanned = payload.scanned ?? added
            let updated = payload.updated ?? 0
            let moved = payload.moved ?? 0
            let removed = payload.deleted ?? 0
            let message = t(
                "Scanned %@ · added %@ · updated %@ · moved %@ · removed %@",
                String(scanned), String(added), String(updated), String(moved), String(removed)
            )
            libraryStatus = message
            return ScanResult(ok: true, added: added, error: nil)
        } catch {
            let message = localizedError(error.localizedDescription)
            lastError = message
            libraryStatus = message
            return ScanResult(ok: false, added: 0, error: message)
        }
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

    func beginDeviceTransfer(total: Int) {
        deviceTransferActive = true
        deviceTransferCancelled = false
        deviceTransferDone = 0
        deviceTransferTotal = total
        deviceTransferBytesSent = 0
        deviceTransferBytesTotal = 0

        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard let self, self.deviceTransferActive else { return }
                if let payload = await self.fetchTransferProgress() {
                    self.deviceTransferBytesSent = payload.sent
                    self.deviceTransferBytesTotal = payload.total
                }
            }
        }
    }

    func finishDeviceTransfer() {
        progressTask?.cancel()
        progressTask = nil
        deviceTransferActive = false
        deviceTransferCancelled = false
        deviceTransferDone = 0
        deviceTransferTotal = 0
        deviceTransferBytesSent = 0
        deviceTransferBytesTotal = 0
    }

    func cancelDeviceTransfer() {
        if deviceTransferActive {
            deviceTransferCancelled = true
            progressQueue.async {
                _ = kmString(KM_DeviceCancelTransfer())
            }
        }
    }

    private func fetchTransferProgress() async -> TransferProgressPayload? {
        let raw = await withCheckedContinuation { continuation in
            progressQueue.async {
                continuation.resume(returning: kmString(KM_DeviceTransferProgress()))
            }
        }
        return try? decodeEnvelope(raw, as: TransferProgressPayload.self)
    }

    func selectDevice(_ key: String) {
        guard selectedDeviceKey != key else { return }
        selectedDeviceKey = key
        refreshDevice()
    }

    func refreshDevice() {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        deviceLoading = true
        deviceState = "discovering"
        Task {
            let loaded = await runOnDeviceQueue { loadDevicesResult() }
            let legacy = await Task.detached(priority: .utility) {
                AppStore.findLegacyKindleVolume()
            }.value
            legacyKindleVolume = legacy
            if let error = loaded.error {
                devices = []
                deviceFiles = []
                let message = localizedError(error)
                deviceStatus = t("Discovery failed: %@", message)
                deviceState = "error"
                lastError = message
                deviceLoading = false
                refreshInFlight = false
                return
            }

            let kindleDevices = loaded.devices.filter { $0.vendorID == 0x1949 }
            devices = kindleDevices
            deviceRevision += 1

            let selected = kindleDevices.first { $0.id == selectedDeviceKey } ?? kindleDevices.first
            selectedDeviceKey = selected?.id

            guard let device = selected else {
                deviceFiles = []
                if legacy != nil {
                    deviceStatus = t("Kindle mounted as USB storage")
                    deviceState = "legacy"
                } else {
                    deviceStatus = t("No Kindle connected")
                    deviceState = "disconnected"
                }
                deviceLoading = false
                refreshInFlight = false
                return
            }

            deviceStatus = t("Opening Kindle…")
            deviceState = "opening"
            let language = self.language
            let (files, status) = await runOnDeviceQueue {
                AppStore.openAndListDevice(device, language: language)
            }
            deviceFiles = files
            deviceStatus = status
            deviceState = files.isEmpty ? "error" : "ready"
            deviceLoading = false
            refreshInFlight = false
            deviceRevision += 1
        }
    }

    nonisolated private static func openAndListDevice(_ device: RawDevice, language: AppLanguage) -> ([DeviceFile], String) {
        let info = connectDevice(device)
        guard isOK(info) else {
            return ([], L10n.text("Connect failed: %@", language, L10n.error(errorText(info), language)))
        }
        let (files, error) = loadDeviceFilesResult()
        if let error {
            return (files, L10n.text("Kindle connected, listing failed: %@", language, L10n.error(error, language)))
        }
        return (files, L10n.text("Kindle connected · %d objects", language, files.count))
    }

    nonisolated private static func findLegacyKindleVolume() -> URL? {
        let fm = FileManager.default
        let volumes = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        guard let urls = try? fm.contentsOfDirectory(
            at: volumes,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for url in urls {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            guard resolved.path != "/" else { continue }
            if looksLikeKindleVolume(resolved) {
                return resolved
            }
        }
        return nil
    }

    nonisolated private static func looksLikeKindleVolume(_ url: URL) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.appendingPathComponent("system/version.txt").path) {
            return true
        }
        let name = url.lastPathComponent.lowercased()
        return name == "kindle"
            && fm.fileExists(atPath: url.appendingPathComponent("documents", isDirectory: true).path)
    }

    func reloadDeviceFiles() async {
        let (files, error) = await runOnDeviceQueue { loadDeviceFilesResult() }
        deviceFiles = files
        deviceRevision += 1
        if let error {
            let message = localizedError(error)
            deviceStatus = t("Listing failed: %@", message)
            lastError = message
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
        beginDeviceTransfer(total: paths.count)
        defer { finishDeviceTransfer() }

        var errors: [String] = []
        for (index, path) in paths.enumerated() {
            if deviceTransferCancelled {
                return OpResult(ok: false, message: t("Transfer cancelled"))
            }
            let response = await runOnDeviceQueue { () -> String in
                kmString(withCStr(path) { KM_DeviceUploadBook($0, parent, storage) })
            }
            if !isOK(response) {
                errors.append("\(path): \(localizedError(errorText(response)))")
            }
            deviceTransferDone = index + 1
            deviceStatus = t("Uploading %d/%d…", deviceTransferDone, paths.count)
        }

        await reloadDeviceFiles()
        let result = OpResult(
            ok: errors.isEmpty,
            message: errors.isEmpty
                ? t("Uploaded %d file(s) to Kindle", paths.count)
                : errors.joined(separator: "; ")
        )
        deviceStatus = result.message
        return result
    }

    nonisolated private static func folderEntries(root: URL) -> [FolderUploadEntry] {
        let fm = FileManager.default
        let rootPath = root.standardizedFileURL.path
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var result: [FolderUploadEntry] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else {
                continue
            }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(rootPath + "/") else {
                continue
            }
            let relative = String(path.dropFirst(rootPath.count + 1))
            let components = relative.split(separator: "/").map(String.init)
            guard !components.isEmpty else { continue }
            if values.isDirectory == true {
                result.append(FolderUploadEntry(url: url, components: components, isDirectory: true))
            } else if values.isRegularFile == true {
                result.append(FolderUploadEntry(url: url, components: components, isDirectory: false))
            }
        }
        return result
    }

    func uploadFolderToKindle(_ root: URL, target: DeviceFolder) async -> OpResult {
        let entries = await Task.detached(priority: .userInitiated) {
            AppStore.folderEntries(root: root)
        }.value

        let rootName = FileSafety.sanitizeFileName(root.lastPathComponent)
        let successMessage = t("Uploaded folder %@", root.lastPathComponent)
        let existingFiles = deviceFiles
        let language = self.language
        let result = await runOnDeviceQueue { () -> OpResult in
            var errors: [String] = []
            var folderIDs: [String: UInt32] = [:]
            var byParent: [UInt32: [String: UInt32]] = [:]
            for file in existingFiles where file.isFolder {
                byParent[file.parentID, default: [:]][file.name] = file.id
            }

            func ensureFolder(parent: UInt32, name: String, key: String) -> UInt32? {
                if let existing = byParent[parent]?[name] {
                    folderIDs[key] = existing
                    return existing
                }
                let raw = kmString(withCStr(name) { KM_DeviceCreateFolder($0, parent, target.storageID) })
                guard let data = raw.data(using: .utf8),
                      let payload = try? JSONDecoder().decode(CreateFolderPayload.self, from: data),
                      payload.ok,
                      let id = payload.id else {
                    errors.append("\(name): \(L10n.error(errorText(raw), language))")
                    return nil
                }
                folderIDs[key] = id
                byParent[parent, default: [:]][name] = id
                return id
            }

            guard let rootID = ensureFolder(parent: target.id, name: rootName, key: "") else {
                return OpResult(ok: false, message: errors.joined(separator: "; "))
            }

            for entry in entries where entry.isDirectory {
                var parent = rootID
                var parts: [String] = []
                for component in entry.components {
                    parts.append(component)
                    let key = parts.joined(separator: "/")
                    guard let child = ensureFolder(
                        parent: parent,
                        name: FileSafety.sanitizeFileName(component),
                        key: key
                    ) else {
                        break
                    }
                    parent = child
                }
            }

            for entry in entries where !entry.isDirectory {
                var parent = rootID
                var parts: [String] = []
                for component in entry.components.dropLast() {
                    parts.append(component)
                    let key = parts.joined(separator: "/")
                    if let existing = folderIDs[key] {
                        parent = existing
                    } else if let child = ensureFolder(
                        parent: parent,
                        name: FileSafety.sanitizeFileName(component),
                        key: key
                    ) {
                        parent = child
                    }
                }
                let raw = kmString(withCStr(entry.url.path) {
                    KM_DeviceUploadBook($0, parent, target.storageID)
                })
                if !isOK(raw) {
                    errors.append("\(entry.components.joined(separator: "/")): \(L10n.error(errorText(raw), language))")
                }
            }

            let message = errors.isEmpty
                ? successMessage
                : errors.joined(separator: "; ")
            return OpResult(ok: errors.isEmpty, message: message)
        }

        await reloadDeviceFiles()
        deviceStatus = result.message
        return result
    }

    func downloadDeviceFile(_ id: UInt32, to path: String) async -> String {
        let result = await runOnDeviceQueue { () -> String in
            kmString(withCStr(path) { KM_DeviceDownloadBook(id, $0) })
        }
        let message = localizedError(result)
        deviceStatus = message
        return message
    }

    func openDeviceFile(_ file: DeviceFile) async -> String {
        let tmp: URL
        do {
            tmp = try FileSafety.temporaryDownloadURL(for: file.name)
        } catch {
            let message = t("Open failed: %@", L10n.error(error.localizedDescription, language))
            deviceStatus = message
            return message
        }
        let id = file.id
        let result = await runOnDeviceQueue { () -> String in
            kmString(withCStr(tmp.path) { KM_DeviceDownloadBook(id, $0) })
        }
        if isOK(result) {
            NSWorkspace.shared.open(tmp)
            deviceStatus = t("Opened %@", file.name)
            return t("Opened %@", file.name)
        }
        let message = localizedError(result)
        deviceStatus = message
        return message
    }

    func deleteDeviceObjects(_ ids: [UInt32]) async -> String {
        await deleteDeviceObjectsChecked(ids).message
    }

    func deleteDeviceObjectsChecked(_ ids: [UInt32]) async -> OpResult {
        let deletedMessage = t("Deleted %d item(s)", ids.count)
        let language = self.language
        let result = await runOnDeviceQueue { () -> OpResult in
            var errors: [String] = []
            for id in ids {
                let r = kmString(KM_DeviceDeleteBook(id))
                if !isOK(r) { errors.append(L10n.error(errorText(r), language)) }
            }
            return OpResult(
                ok: errors.isEmpty,
                message: errors.isEmpty ? deletedMessage : errors.joined(separator: "; ")
            )
        }
        await reloadDeviceFiles()
        deviceStatus = result.message
        return result
    }

    func moveDeviceObjects(_ ids: [UInt32], to folder: DeviceFolder, copy: Bool = false) async -> String {
        let successMessage = t(copy ? "Copied %d item(s) to %@" : "Moved %d item(s) to %@", ids.count, folder.label)
        let language = self.language
        let result = await runOnDeviceQueue { () -> String in
            var errors: [String] = []
            for id in ids {
                let r = copy
                    ? kmString(KM_DeviceCopyBook(id, folder.storageID, folder.id))
                    : kmString(KM_DeviceMoveBook(id, folder.storageID, folder.id))
                if !isOK(r) { errors.append(L10n.error(errorText(r), language)) }
            }
            return errors.isEmpty
                ? successMessage
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
        let message = localizedError(result)
        deviceStatus = message
        return message
    }

    func renameDeviceObject(_ id: UInt32, to name: String) async -> String {
        let result = await runOnDeviceQueue { () -> String in
            kmString(withCStr(name) { KM_DeviceRenameBook(id, $0) })
        }
        await reloadDeviceFiles()
        let message = localizedError(result)
        deviceStatus = message
        return message
    }
}

private func pathIsUnderRoot(_ path: String, root: String) -> Bool {
    let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
    let standardizedRoot = URL(fileURLWithPath: root).standardizedFileURL.path
    if standardizedPath == standardizedRoot { return false }
    let prefix = standardizedRoot.hasSuffix("/") ? standardizedRoot : standardizedRoot + "/"
    return standardizedPath.hasPrefix(prefix)
}
