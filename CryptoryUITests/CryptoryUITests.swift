//
//  CryptoryUITests.swift
//  CryptoryUITests
//
//  Created by Hwangseokbeom on 3/30/26.
//

import XCTest

final class CryptoryUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testKimchiFreshnessBadgesAreVisibleWithFixtureData() throws {
        let app = XCUIApplication()
        app.launchEnvironment["CRYPTORY_UI_TEST_SCENARIO"] = "kimchi_freshness"
        app.launch()

        app.tabBars.buttons["김프"].tap()

        XCTAssertTrue(app.staticTexts["업비트 기준 빠른 비교"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["약간 지연"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["일부 지연"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["업데이트 방금 전"].exists || app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "업데이트")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["fx_rate_delayed"].exists)
        XCTAssertFalse(app.staticTexts["timestamp_skew_detected"].exists)
        XCTAssertFalse(app.staticTexts["freshness_threshold_exceeded"].exists)
        XCTAssertFalse(app.staticTexts["fallback_source"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
