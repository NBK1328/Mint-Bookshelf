import Foundation

public struct LocalTransferResult: Sendable {
    public let ok: Bool
    public let succeeded: Int
    public let errors: [String]

    public init(ok: Bool, succeeded: Int, errors: [String]) {
        self.ok = ok
        self.succeeded = succeeded
        self.errors = errors
    }
}

public struct TrashResult: Sendable {
    public let trashed: Int
    public let errors: [String]

    public init(trashed: Int, errors: [String]) {
        self.trashed = trashed
        self.errors = errors
    }
}

public enum LocalFileService {
    public static func transfer(_ urls: [URL], to destination: URL, copy: Bool) -> LocalTransferResult {
        let destination = destination.standardizedFileURL
        var succeeded = 0
        var errors: [String] = []

        for source in urls {
            let source = source.standardizedFileURL
            let sourceGuard = FileSafety.canonicalURL(source)
            let destinationGuard = FileSafety.canonicalURL(destination)
            if sourceGuard.path == destinationGuard.path { continue }
            if destinationGuard.path.hasPrefix(sourceGuard.path + "/") { continue }
            if !copy && sourceGuard.deletingLastPathComponent().path == destinationGuard.path { continue }

            do {
                if copy {
                    _ = try FileSafety.copyUnique(source, into: destination)
                } else {
                    _ = try FileSafety.moveUnique(source, into: destination)
                }
                succeeded += 1
            } catch {
                errors.append("\(source.lastPathComponent): \(error.localizedDescription)")
            }
        }

        return LocalTransferResult(ok: errors.isEmpty, succeeded: succeeded, errors: errors)
    }

    public static func trash(_ urls: [URL]) -> TrashResult {
        var trashed = 0
        var errors: [String] = []
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                trashed += 1
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return TrashResult(trashed: trashed, errors: errors)
    }
}
