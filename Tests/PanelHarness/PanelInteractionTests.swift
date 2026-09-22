import XCTest

@MainActor
final class PanelInteractionTests: XCTestCase {
    private var app: XCUIApplication!
    private var field: XCUIElement { app.textFields["drawer.search"] }
    private var handle: XCUIElement { app.otherElements["drawer.handle"] }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-panel-layout-diagnostics"]
        app.launch()
        let found = field.waitForExistence(timeout: 10)
        if !found {
            print("PANEL_ACCESSIBILITY_HIERARCHY\n\(app.debugDescription)")
            snapshot("launch-failure")
        }
        XCTAssertTrue(found)
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0 {
            print("PANEL_FAILURE_HIERARCHY\n\(app.debugDescription)")
            let geometry = app.otherElements["panel.keyboardGeometry"].value
            print("PANEL_KEYBOARD_GEOMETRY \(String(describing: geometry))")
            print("PANEL_SWIFTUI_GEOMETRY \(String(describing: handle.value))")
            snapshot("failure")
        }
    }

    private func waitForHeaderReady() {
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"), object: field
        )
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
    }

    func testKeyboardResultsAreVisible() {
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        snapshot("keyboard-results")
        XCTAssertTrue(app.staticTexts["Result 0"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Result 0"].isHittable)
        XCTAssertTrue(app.scrollViews["search.results"].exists)
        print("PANEL_SWIFTUI_GEOMETRY \(String(describing: handle.value))")
        let geometry = app.otherElements["panel.keyboardGeometry"].value
        print("PANEL_KEYBOARD_GEOMETRY \(String(describing: geometry))")
        XCTAssertGreaterThan(app.scrollViews["search.results"].frame.height, app.frame.height * 0.15)
        let expanded = field.frame
        XCUIDevice.shared.press(.home)
        app.activate()
        waitForHeaderReady()
        assertStableHeader(y: expanded.minY, x: expanded.minX)
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Result 0"].isHittable)

        // SwiftUI extends the backing UIScrollView/AX frame into safe areas.
        // Verify the actual usable viewport: the final result must scroll
        // completely above the keyboard and accept a tap with it still open.
        let results = app.scrollViews["search.results"]
        let last = app.buttons["search.last"]
        for _ in 0..<12 {
            if last.isHittable { break }
            let top = results.frame.minY
            let bottom = min(results.frame.maxY, app.keyboards.firstMatch.frame.minY)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: results.frame.midX, dy: top + (bottom - top) * 0.75))
            let end = origin.withOffset(CGVector(dx: results.frame.midX, dy: top + (bottom - top) * 0.15))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(last.isHittable)
        XCTAssertLessThanOrEqual(last.frame.maxY, app.keyboards.firstMatch.frame.minY)
        assertStableHeader(y: expanded.minY, x: expanded.minX)
        snapshot("last-result-above-keyboard")
        last.tap()
        XCTAssertTrue(app.buttons["drawer.more"].waitForExistence(timeout: 3))
        XCTAssertTrue(field.isHittable)
    }

    private func assertStableHeader(y: CGFloat, x: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<5 {
            XCTAssertTrue(field.isHittable, file: file, line: line)
            XCTAssertEqual(field.frame.minY, y, accuracy: 2, file: file, line: line)
            XCTAssertEqual(field.frame.minX, x, accuracy: 2, file: file, line: line)
        }
    }

    func testSearchCancelKeyboardAndRapidReentry() {
        let collapsed = field.frame
        XCTAssertGreaterThan(collapsed.minY, app.frame.height * 0.70)
        snapshot("collapsed")
        for _ in 0..<12 {
            field.tap()
            XCTAssertTrue(app.buttons["drawer.cancel"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
            XCTAssertLessThan(field.frame.minY, app.frame.height * 0.25)
            XCTAssertEqual(
                field.frame.minX,
                collapsed.minX - 4,
                accuracy: 2
            )
            let expanded = field.frame
            field.typeText("a")
            assertStableHeader(y: expanded.minY, x: expanded.minX)
            app.buttons["drawer.cancel"].tap()
            XCTAssertTrue(app.buttons["drawer.more"].waitForExistence(timeout: 3))
            assertStableHeader(y: collapsed.minY, x: collapsed.minX)
        }
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let expanded = field.frame
        snapshot("searching-keyboard")
        // Drag through the keyboard edge, completing an interactive dismissal.
        // A swipe confined to the list can cancel halfway and leave it visible.
        let results = app.scrollViews["search.results"]
        XCTAssertTrue(results.waitForExistence(timeout: 3))
        results.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 3), .completed)
        assertStableHeader(y: expanded.minY, x: expanded.minX)
        XCTAssertGreaterThan(results.frame.height, app.frame.height * 0.6)
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        assertStableHeader(y: expanded.minY, x: expanded.minX)
        snapshot("search-refocused")
    }

    func testSecondaryNestedSheetsBackgroundAndMapHitTesting() {
        let collapsed = field.frame
        for page in ["settings", "places", "profiles", "route", "timer", "setup"] {
            app.buttons["drawer.more"].tap()
            app.buttons[page].tap()
            XCTAssertTrue(app.buttons["secondary.nested"].waitForExistence(timeout: 3))
            app.buttons["secondary.nested"].tap()
            XCTAssertTrue(app.buttons["nested.done"].waitForExistence(timeout: 3))
            app.buttons["nested.done"].tap()
            app.buttons["secondary.done"].tap()
            XCTAssertTrue(field.waitForExistence(timeout: 3))
            assertStableHeader(y: collapsed.minY, x: collapsed.minX)
        }
        for _ in 0..<3 {
            XCUIDevice.shared.press(.home)
            app.activate()
            waitForHeaderReady()
            assertStableHeader(y: collapsed.minY, x: collapsed.minX)
            app.buttons["map.control"].tap()
            assertStableHeader(y: collapsed.minY, x: collapsed.minX)
        }
        XCTAssertEqual(app.staticTexts["map.taps"].label, "Map taps: 0")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        XCTAssertEqual(app.staticTexts["map.taps"].label, "Map taps: 1")
        assertStableHeader(y: collapsed.minY, x: collapsed.minX)
        snapshot("after-modal-background-cycles")
    }

    func testDragDetentsAndJoystick() {
        // Use the grabber's actual center, not the shared edge with the field.
        let grab = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        grab.press(forDuration: 0.1, thenDragTo: middle)
        XCTAssertTrue(app.buttons["session.update"].waitForExistence(timeout: 3))
        let normal = field.frame
        app.buttons["session.update"].tap()
        field.tap()
        app.buttons["drawer.cancel"].tap()
        assertStableHeader(y: normal.minY, x: normal.minX)
        app.buttons["joystick.enter"].tap()
        XCTAssertTrue(app.buttons["joystick.exit"].waitForExistence(timeout: 3))
        app.buttons["joystick.exit"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertTrue(field.isHittable)
        snapshot("after-joystick")
    }
}
