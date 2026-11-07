import XCTest

/// These tests verify the real Simulator UI and backend. They do not inject microphone audio.
@MainActor
final class ConversationTests: XCTestCase {
    override func tearDownWithError() throws {
        let app = XCUIApplication()
        if app.state == .runningForeground && app.buttons["endSession"].exists {
            app.buttons["endSession"].tap()
        }
        try super.tearDownWithError()
    }
    func testDefaultLaunchHasCenteredStartAndNoVideoFallback() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let start = app.buttons["startSession"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.count, 1, app.debugDescription)
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(start.frame.midX, window.midX, accuracy: 2)
        // Center within the safe area between the status bar and home indicator.
        XCTAssertEqual(start.frame.midY, window.midY, accuracy: 25)
        XCTAssertFalse(app.staticTexts["sceneFrameCount"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Centered camera start button"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        start.press(forDuration: 0.8)
        app.buttons["Connection"].tap()
        XCTAssertTrue(app.textFields["Backend URL"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        start.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<15 {
            if springboard.alerts.firstMatch.exists {
                let allow = springboard.alerts.buttons.matching(NSPredicate(format: "label == 'Allow' OR label == 'OK'")).firstMatch
                if allow.exists { allow.tap() }
            }
            if app.staticTexts["statusMessage"].exists && start.isEnabled { break }
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        XCTAssertTrue(start.isEnabled)
        XCTAssertTrue(app.staticTexts["statusMessage"].label.contains("No rear camera"), app.debugDescription)
        XCTAssertFalse(app.staticTexts["DEVELOPMENT VIDEO"].exists)
        XCTAssertFalse(app.buttons["endSession"].exists)
    }

    func testSceneQuestionAndSessionStop() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--dev-prerecorded-scene"]
        app.launch()
        XCTAssertTrue(app.buttons["startSession"].waitForExistence(timeout: 10))
        app.buttons["startSession"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // First launch may ask for iOS microphone permission. A host macOS prompt is separate.
        for _ in 0..<20 {
            if springboard.alerts.firstMatch.exists {
                let allow = springboard.alerts.buttons.matching(NSPredicate(format: "label == 'Allow' OR label == 'OK' OR label == 'Allow While Using App'")).firstMatch
                if allow.exists { allow.tap() }
            }
            let candidate = app.textFields["questionInput"].exists ? app.textFields["questionInput"] : app.textViews["questionInput"]
            if candidate.exists && candidate.isEnabled { break }
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        let question = app.textFields["questionInput"].exists ? app.textFields["questionInput"] : app.textViews["questionInput"]
        XCTAssertTrue(question.waitForExistence(timeout: 15), app.debugDescription)
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: question)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.staticTexts["DEVELOPMENT VIDEO"].exists)
        let scene = app.descendants(matching: .any).matching(identifier: "scenePreview").firstMatch
        XCTAssertTrue(scene.exists)
        XCTAssertGreaterThanOrEqual(scene.frame.height, app.windows.firstMatch.frame.height * 0.9)
        XCTAssertEqual(scene.frame.width, app.windows.firstMatch.frame.width, accuracy: 2)
        XCTAssertFalse(app.staticTexts["sceneFrameCount"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Sampled views'")).firstMatch.exists)
        for identifier in ["muteMicrophone", "stopSpeaking", "switchCamera", "endSession"] {
            XCTAssertTrue(app.buttons[identifier].exists, identifier)
        }
        // Development video has no physical camera to switch. Never substitute another video.
        XCTAssertFalse(app.buttons["switchCamera"].isEnabled)
        // Isolate output completion from the virtual microphone route. This does not test echo control.
        app.buttons["muteMicrophone"].tap()
        question.tap()
        question.typeText("What color is the cup in the photograph? Answer in one short sentence.")
        app.buttons["sendQuestion"].tap()
        let answer = app.staticTexts.matching(identifier: "assistantReply").firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 35), app.debugDescription)
        XCTAssertTrue(answer.label.lowercased().contains("brown") || answer.label.lowercased().contains("red"), answer.label)
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: answer)
        waitForExpectations(timeout: 5)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Scene question answered in Simulator"
        attachment.lifetime = .keepAlways
        add(attachment)
        // This checks the audio engine's playback lifecycle, not sound heard by a person.
        expectation(for: NSPredicate(format: "value == 'Speech playback completed'"), evaluatedWith: app.staticTexts["assistantState"])
        waitForExpectations(timeout: 20)
        // Dismiss keyboard before tapping a control that may be above the viewport.
        app.swipeDown()
        app.buttons["endSession"].tap()
        XCTAssertTrue(app.buttons["startSession"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["sceneFrameCount"].exists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "assistantReply").count, 0)
    }
}
