import Flutter
import UIKit
import XCTest

@testable import Runner

class RunnerTests: XCTestCase {

  /// The photo cache's folder is marked to stay out of iCloud backup (#4221).
  func testExcludeFromBackupSetsTheAttribute() throws {
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    try BackupExclusion.exclude(path: folder.path)

    let values = try URL(fileURLWithPath: folder.path)
      .resourceValues(forKeys: [.isExcludedFromBackupKey])
    XCTAssertEqual(values.isExcludedFromBackup, true)
  }

}
