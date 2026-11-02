import Foundation
import XCTest
import KindleManagerSupport

private final class TransferResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var urls: [URL] = []
    private(set) var errors: [Error] = []

    func add(url: URL) {
        lock.lock()
        urls.append(url)
        lock.unlock()
    }

    func add(error: Error) {
        lock.lock()
        errors.append(error)
        lock.unlock()
    }
}

final class FileSafetyTests: XCTestCase {
    private let fm = FileManager.default

    private func makeTemporaryDirectory() throws -> URL {
        let url = fm.temporaryDirectory.appendingPathComponent(
            "KindleManagerTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testSanitizeFileName() {
        XCTAssertEqual(FileSafety.sanitizeFileName("../evil.txt"), ".._evil.txt")
        XCTAssertEqual(FileSafety.sanitizeFileName("a/b.txt"), "a_b.txt")
        XCTAssertEqual(FileSafety.sanitizeFileName("a\\b.txt"), "a_b.txt")
        XCTAssertEqual(FileSafety.sanitizeFileName("file:name.txt"), "file_name.txt")
        XCTAssertEqual(FileSafety.sanitizeFileName(".."), "unnamed")
        XCTAssertEqual(FileSafety.sanitizeFileName("."), "unnamed")
        XCTAssertEqual(FileSafety.sanitizeFileName("   "), "unnamed")
        XCTAssertEqual(FileSafety.sanitizeFileName("Книга.epub"), "Книга.epub")
    }

    func testSafeDestinationStaysInsideBase() throws {
        let base = try makeTemporaryDirectory()
        defer { try? fm.removeItem(at: base) }

        let destination = try FileSafety.safeDestination(
            base: base,
            components: ["../../evil.txt"]
        )
        let standardizedBase = base.standardizedFileURL.path
        let prefix = standardizedBase + "/"
        XCTAssertTrue(destination.standardizedFileURL.path.hasPrefix(prefix))
        XCTAssertFalse(destination.standardizedFileURL.path.contains("/../"))
    }

    func testSafeDestinationBuildsNestedPath() throws {
        let base = try makeTemporaryDirectory()
        defer { try? fm.removeItem(at: base) }

        let destination = try FileSafety.safeDestination(
            base: base,
            components: ["folder", "book.epub"]
        )
        XCTAssertEqual(
            destination.standardizedFileURL.path,
            base.appendingPathComponent("folder/book.epub").standardizedFileURL.path
        )
    }

    func testSafeDestinationRejectsEmptyComponents() throws {
        let base = try makeTemporaryDirectory()
        defer { try? fm.removeItem(at: base) }

        XCTAssertThrowsError(try FileSafety.safeDestination(base: base, components: [])) { error in
            XCTAssertEqual(error as? FileSafetyError, .invalidName)
        }
    }

    func testUniqueDestinationPreservesExtension() throws {
        let base = try makeTemporaryDirectory()
        defer { try? fm.removeItem(at: base) }

        let first = base.appendingPathComponent("book.epub")
        try Data("one".utf8).write(to: first)

        let second = FileSafety.uniqueDestination(in: base, name: "book.epub")
        XCTAssertEqual(second.lastPathComponent, "book 1.epub")

        try Data("two".utf8).write(to: second)
        let third = FileSafety.uniqueDestination(in: base, name: "book.epub")
        XCTAssertEqual(third.lastPathComponent, "book 2.epub")
    }

    func testUniqueDirectoryDoesNotSplitExtension() throws {
        let base = try makeTemporaryDirectory()
        defer { try? fm.removeItem(at: base) }

        try fm.createDirectory(
            at: base.appendingPathComponent("v1.2"),
            withIntermediateDirectories: false
        )
        let next = FileSafety.uniqueDestination(
            in: base,
            name: "v1.2",
            preserveExtension: false
        )
        XCTAssertEqual(next.lastPathComponent, "v1.2 1")
    }

    func testCopyUniqueDoesNotOverwrite() throws {
        let root = try makeTemporaryDirectory()
        defer { try? fm.removeItem(at: root) }

        let sourceDir = root.appendingPathComponent("source", isDirectory: true)
        let destDir = root.appendingPathComponent("dest", isDirectory: true)
        try fm.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        let source = sourceDir.appendingPathComponent("book.epub")
        try Data("new".utf8).write(to: source)

        let existing = destDir.appendingPathComponent("book.epub")
        try Data("old".utf8).write(to: existing)

        let copied = try FileSafety.copyUnique(source, into: destDir)
        XCTAssertEqual(copied.lastPathComponent, "book 1.epub")
        XCTAssertEqual(try Data(contentsOf: existing), Data("old".utf8))
        XCTAssertEqual(try Data(contentsOf: copied), Data("new".utf8))
        XCTAssertTrue(fm.fileExists(atPath: source.path))
    }

    func testMoveUniqueDoesNotOverwrite() throws {
        let root = try makeTemporaryDirectory()
        defer { try? fm.removeItem(at: root) }

        let sourceDir = root.appendingPathComponent("source", isDirectory: true)
        let destDir = root.appendingPathComponent("dest", isDirectory: true)
        try fm.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        let source = sourceDir.appendingPathComponent("book.epub")
        try Data("new".utf8).write(to: source)

        let existing = destDir.appendingPathComponent("book.epub")
        try Data("old".utf8).write(to: existing)

        let moved = try FileSafety.moveUnique(source, into: destDir)
        XCTAssertEqual(moved.lastPathComponent, "book 1.epub")
        XCTAssertEqual(try Data(contentsOf: existing), Data("old".utf8))
        XCTAssertEqual(try Data(contentsOf: moved), Data("new".utf8))
        XCTAssertFalse(fm.fileExists(atPath: source.path))
    }

    func testCreateDirectoryUniqueDoesNotReuseExisting() throws {
        let base = try makeTemporaryDirectory()
        defer { try? fm.removeItem(at: base) }

        try fm.createDirectory(
            at: base.appendingPathComponent("untitled folder"),
            withIntermediateDirectories: false
        )
        let created = try FileSafety.createDirectoryUnique(in: base, name: "untitled folder")
        XCTAssertEqual(created.lastPathComponent, "untitled folder 1")
        XCTAssertTrue(fm.fileExists(atPath: created.path))
    }

    func testTemporaryDownloadURLIsIsolated() throws {
        let first = try FileSafety.temporaryDownloadURL(for: "../../book.epub")
        defer { try? fm.removeItem(at: first.deletingLastPathComponent()) }
        let second = try FileSafety.temporaryDownloadURL(for: "../../book.epub")
        defer { try? fm.removeItem(at: second.deletingLastPathComponent()) }

        XCTAssertEqual(first.lastPathComponent, ".._.._book.epub")
        XCTAssertNotEqual(
            first.deletingLastPathComponent().path,
            second.deletingLastPathComponent().path
        )
        XCTAssertTrue(
            fm.fileExists(atPath: first.deletingLastPathComponent().path),
            "temporary directory must exist"
        )
    }

    func testSafeDestinationResolvesSymlinkedBase() throws {
        let root = try makeTemporaryDirectory()
        defer { try? fm.removeItem(at: root) }

        let real = root.appendingPathComponent("real", isDirectory: true)
        let link = root.appendingPathComponent("link", isDirectory: true)
        try fm.createDirectory(at: real, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: link, withDestinationURL: real)

        let destination = try FileSafety.safeDestination(
            base: link,
            components: ["book.epub"]
        )
        XCTAssertEqual(
            destination.standardizedFileURL.path,
            real.appendingPathComponent("book.epub").standardizedFileURL.path
        )
    }

    func testConcurrentCopyUniqueCreatesDistinctFiles() throws {
        let root = try makeTemporaryDirectory()
        defer { try? fm.removeItem(at: root) }

        let sourceDir = root.appendingPathComponent("source", isDirectory: true)
        let destDir = root.appendingPathComponent("dest", isDirectory: true)
        try fm.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        let source = sourceDir.appendingPathComponent("book.epub")
        try Data("data".utf8).write(to: source)

        let box = TransferResultBox()
        let group = DispatchGroup()
        for _ in 0..<8 {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                do {
                    box.add(url: try FileSafety.copyUnique(source, into: destDir))
                } catch {
                    box.add(error: error)
                }
            }
        }
        group.wait()

        XCTAssertTrue(box.errors.isEmpty, "copy errors: \(box.errors)")
        XCTAssertEqual(box.urls.count, 8)
        XCTAssertEqual(Set(box.urls.map(\.lastPathComponent)).count, 8)
    }
}
