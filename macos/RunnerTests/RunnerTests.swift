import Cocoa
import FlutterMacOS
import XCTest
@testable import Local_Mind

class RunnerTests: XCTestCase {

  @MainActor
  func testLaunchCreatesUsableStatusItem() throws {
    // Inspect the real app after launch: an exception in the launch callback
    // leaves the Flutter window alive but prevents the status item being made.
    let delegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)
    let item = try XCTUnwrap(delegate.statusItem)
    let button = try XCTUnwrap(item.button)
    XCTAssertTrue(item.isVisible)
    XCTAssertEqual(item.autosaveName, AppDelegate.statusItemName)
    XCTAssertEqual(button.toolTip, "Local Mind")
    XCTAssertTrue(button.image != nil || !button.title.isEmpty)
    XCTAssertTrue(button.target === delegate)
    XCTAssertNotNil(button.action)

    let window = try XCTUnwrap(delegate.mainFlutterWindow)
    window.orderOut(nil)
    button.performClick(nil)
    XCTAssertTrue(window.isVisible)
    button.performClick(nil)
    XCTAssertFalse(window.isVisible)
    XCTAssertTrue(item.isVisible, "Closing the panel must leave the tray available")
  }

  func testInitialPositionIsSeededWithoutOverwritingUserArrangement() throws {
    let suite = "LocalMind.StatusItemTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let key = "NSStatusItem Preferred Position \(AppDelegate.statusItemName)"
    AppDelegate.prepareStatusItemPosition(in: defaults)
    XCTAssertEqual(defaults.integer(forKey: key), 0)
    defaults.set(250, forKey: key)
    AppDelegate.prepareStatusItemPosition(in: defaults)
    XCTAssertEqual(defaults.integer(forKey: key), 250)
  }

}
