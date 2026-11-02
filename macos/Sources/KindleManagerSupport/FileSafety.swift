import Foundation

public enum FileSafetyError: LocalizedError, Equatable {
    case invalidName
    case outsideBase
    case notDirectory

    public var errorDescription: String? {
        switch self {
        case .invalidName:
            return "The file name is not valid"
        case .outsideBase:
            return "The destination escapes the selected folder"
        case .notDirectory:
            return "The destination is not a directory"
        }
    }
}

/// Pure path and local-file helpers shared by the app and its tests.
/// Device-provided names are untrusted and must never be used as raw paths.
public enum FileSafety {
    public static func sanitizeFileName(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        name = name.replacingOccurrences(of: "\0", with: "_")
        let forbidden = CharacterSet(charactersIn: "/\\:")
        name = name.components(separatedBy: forbidden).joined(separator: "_")
        if name.isEmpty || name == "." || name == ".." {
            return "unnamed"
        }
        return name
    }

    public static func sanitizeComponents(_ components: [String]) -> [String] {
        components.map(sanitizeFileName)
    }

    /// Builds a destination inside `base` and rejects any result that escapes it.
    public static func safeDestination(base: URL, components: [String]) throws -> URL {
        guard !components.isEmpty else {
            throw FileSafetyError.invalidName
        }

        let baseURL = base.resolvingSymlinksInPath().standardizedFileURL
        var target = baseURL
        for component in components {
            target.appendPathComponent(sanitizeFileName(component))
        }
        target = target.standardizedFileURL

        let basePath = baseURL.path
        let prefix = basePath.hasSuffix("/") ? basePath : basePath + "/"
        guard target.path == basePath || target.path.hasPrefix(prefix) else {
            throw FileSafetyError.outsideBase
        }
        return target
    }

    /// Returns a non-existing path in `directory`.
    /// For files the extension is preserved (`name 1.ext`).
    /// For folders pass `preserveExtension: false` (`name 1`).
    public static func uniqueDestination(
        in directory: URL,
        name: String,
        preserveExtension: Bool = true
    ) -> URL {
        let fm = FileManager.default
        let safeName = sanitizeFileName(name)
        var candidate = directory.appendingPathComponent(safeName)
        if !fm.fileExists(atPath: candidate.path) {
            return candidate
        }

        let ns = safeName as NSString
        let base = preserveExtension ? ns.deletingPathExtension : safeName
        let ext = preserveExtension ? ns.pathExtension : ""
        var index = 1
        while index < 10_000 {
            let next = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            candidate = directory.appendingPathComponent(next)
            if !fm.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
        return directory.appendingPathComponent(UUID().uuidString)
    }

    public static func copyUnique(_ source: URL, into directory: URL) throws -> URL {
        try transferUnique(source, into: directory, move: false)
    }

    public static func moveUnique(_ source: URL, into directory: URL) throws -> URL {
        try transferUnique(source, into: directory, move: true)
    }

    public static func createDirectoryUnique(in directory: URL, name: String) throws -> URL {
        let fm = FileManager.default
        var attempts = 0
        while attempts < 1_000 {
            let destination = uniqueDestination(in: directory, name: name, preserveExtension: false)
            do {
                try fm.createDirectory(at: destination, withIntermediateDirectories: false)
                return destination
            } catch {
                if (destinationExists(error) || fm.fileExists(atPath: destination.path)) {
                    attempts += 1
                    continue
                }
                throw error
            }
        }
        throw FileSafetyError.invalidName
    }

    /// Creates an isolated temporary directory and returns a safe file path in it.
    public static func temporaryDownloadURL(for deviceName: String) throws -> URL {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory
            .appendingPathComponent("KindleManager-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(sanitizeFileName(deviceName))
    }

    private static func transferUnique(_ source: URL, into directory: URL, move: Bool) throws -> URL {
        let fm = FileManager.default
        var attempts = 0
        while attempts < 1_000 {
            let destination = uniqueDestination(in: directory, name: source.lastPathComponent)
            do {
                if move {
                    try fm.moveItem(at: source, to: destination)
                } else {
                    try fm.copyItem(at: source, to: destination)
                }
                return destination
            } catch {
                if (destinationExists(error) || fm.fileExists(atPath: destination.path)) {
                    attempts += 1
                    continue
                }
                throw error
            }
        }
        throw FileSafetyError.invalidName
    }

    private static func destinationExists(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteFileExistsError
    }
}
