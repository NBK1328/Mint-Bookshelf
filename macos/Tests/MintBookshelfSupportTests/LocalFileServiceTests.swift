import Foundation
import XCTest
import MintBookshelfSupport

final class LocalFileServiceTests: XCTestCase {
    private let fm = FileManager.default

    private func makeTemporaryDirectory() throws -> URL {
        let url = fm.temporaryDirectory.appendingPathComponent(
            "MintBookshelfLocalTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testCopyTransferCreatesUniqueDestination() throws {
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

        let result = LocalFileService.transfer([source], to: destDir, copy: true)
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.succeeded, 1)
        XCTAssertEqual(try Data(contentsOf: existing), Data("old".utf8))
        XCTAssertEqual(
            Set(try fm.contentsOfDirectory(atPath: destDir.path)),
            Set(["book.epub", "book 1.epub"])
        )
    }

    func testMoveTransferSkipsSameParent() throws {
        let root = try makeTemporaryDirectory()
        defer { try? fm.removeItem(at: root) }

        let source = root.appendingPathComponent("book.epub")
        try Data("data".utf8).write(to: source)

        let result = LocalFileService.transfer([source], to: root, copy: false)
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.succeeded, 0)
        XCTAssertTrue(fm.fileExists(atPath: source.path))
    }

    func testTransferRejectsDestinationInsideSourceTree() throws {
        let root = try makeTemporaryDirectory()
        defer { try? fm.removeItem(at: root) }

        let sourceDir = root.appendingPathComponent("source", isDirectory: true)
        let child = sourceDir.appendingPathComponent("child", isDirectory: true)
        try fm.createDirectory(at: child, withIntermediateDirectories: true)

        let result = LocalFileService.transfer([sourceDir], to: child, copy: true)
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.succeeded, 0)
        XCTAssertTrue(fm.fileExists(atPath: sourceDir.path))
    }
}
