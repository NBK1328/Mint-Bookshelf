import SwiftUI
@preconcurrency import AppKit
import KindleManagerSupport

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
    @Published var selectedDeviceKey: String?
    @Published var deviceState: String = "disconnected"
    @Published var deviceTransferActive = false
    @Published var deviceTransferCancelled = false
    @Published var deviceTransferDone = 0
    @Published var deviceTransferTotal = 0

    private let deviceQueue = DispatchQueue(label: "com.kindlemanager.device", qos: .userInitiated)
    private let libraryQueue = DispatchQueue(label: "com.kindlemanager.library", qos: .userInitiated)
    private var refreshInFlight = false

    init() {
        FileSafety.cleanupTemporaryDownloads()
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

    func reloadOperations(silent: Bool = false) {
        do {
            operations = try loadOperations()
        } catch {
            if !silent {
                lastError = error.localizedDescription
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
            let message = "Scanned \(payload.scanned ?? added) · added \(added) · updated \(payload.updated ?? 0) · removed \(payload.deleted ?? 0)"
            libraryStatus = message
            return ScanResult(ok: true, added: added, error: nil)
        } catch {
            let message = error.localizedDescription
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
    }

    func finishDeviceTransfer() {
        deviceTransferActive = false
        deviceTransferCancelled = false
        deviceTransferDone = 0
        deviceTransferTotal = 0
    }

    func cancelDeviceTransfer() {
        if deviceTransferActive {
            deviceTransferCancelled = true
        }
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
            if let error = loaded.error {
                devices = []
                deviceFiles = []
                deviceStatus = "Discovery failed: \(error)"
                deviceState = "error"
                lastError = error
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
                deviceStatus = "No Kindle connected"
                deviceState = "disconnected"
                deviceLoading = false
                refreshInFlight = false
                return
            }

            deviceStatus = "Opening Kindle…"
            deviceState = "opening"
            let (files, status) = await runOnDeviceQueue {
                AppStore.openAndListDevice(device)
            }
            deviceFiles = files
            deviceStatus = status
            deviceState = status.hasPrefix("Kindle connected") ? "ready" : "error"
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
        beginDeviceTransfer(total: paths.count)
        defer { finishDeviceTransfer() }

        var errors: [String] = []
        for (index, path) in paths.enumerated() {
            if deviceTransferCancelled {
                return OpResult(ok: false, message: "Transfer cancelled")
            }
            let response = await runOnDeviceQueue { () -> String in
                kmString(withCStr(path) { KM_DeviceUploadBook($0, parent, storage) })
            }
            if !isOK(response) {
                errors.append("\(path): \(errorText(response))")
            }
            deviceTransferDone = index + 1
            deviceStatus = "Uploading \(deviceTransferDone)/\(paths.count)…"
        }

        await reloadDeviceFiles()
        let result = OpResult(
            ok: errors.isEmpty,
            message: errors.isEmpty
                ? "Uploaded \(paths.count) file(s) to Kindle"
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
        let existingFiles = deviceFiles
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
                    errors.append("\(name): \(errorText(raw))")
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
                    errors.append("\(entry.components.joined(separator: "/")): \(errorText(raw))")
                }
            }

            let message = errors.isEmpty
                ? "Uploaded folder \(root.lastPathComponent)"
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
