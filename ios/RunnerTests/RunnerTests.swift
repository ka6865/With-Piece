import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testScanDirectoryIsExcludedFromBackup() throws {
    let support = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: support) }
    let directory = try ScanCacheDirectory.prepare(in: support)
    XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
    XCTAssertEqual(
      try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
  }
}
