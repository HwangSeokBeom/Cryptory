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

        XCTAssertTrue(app.staticTexts["업비트 기준 빠른 비교"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["약간 지연"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["일부 지연"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["업데이트 방금 전"].exists || app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "업데이트")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["fx_rate_delayed"].exists)
        XCTAssertFalse(app.staticTexts["timestamp_skew_detected"].exists)
        XCTAssertFalse(app.staticTexts["freshness_threshold_exceeded"].exists)
        XCTAssertFalse(app.staticTexts["fallback_source"].exists)
    }

    @MainActor
    func testChartSettingsSheetSupportsTabsSelectionLimitsAndToggles() throws {
        let app = XCUIApplication()
        app.launchEnvironment["CRYPTORY_UI_TEST_SCENARIO"] = "chart_settings"
        app.launch()

        let settingsButton = app.buttons["차트 설정"].firstMatch
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 6))
        settingsButton.tap()

        XCTAssertTrue(app.staticTexts["차트 설정"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["지표 상세 설정"].waitForExistence(timeout: 2))

        func value(for label: String) -> String? {
            app.buttons[label].firstMatch.value as? String
        }

        let topIndicators = [
            "거래량 겹쳐보기",
            "매물대",
            "볼린저 밴드",
            "엔벨로프",
            "이동평균선",
            "일목균형표",
            "파라볼릭 SAR",
            "피봇"
        ]
        func selectedTopCount() -> Int {
            topIndicators.filter { value(for: $0) == "선택됨" }.count
        }

        for label in topIndicators where selectedTopCount() < 3 && value(for: label) != "선택됨" {
            app.buttons[label].firstMatch.tap()
        }
        XCTAssertEqual(selectedTopCount(), 3)

        let blockedTopIndicator = topIndicators.first { value(for: $0) != "선택됨" }!
        app.buttons[blockedTopIndicator].firstMatch.tap()
        XCTAssertEqual(value(for: blockedTopIndicator), "선택 안 됨")
        XCTAssertEqual(selectedTopCount(), 3)

        app.buttons["차트 형식"].firstMatch.tap()
        XCTAssertTrue(app.buttons["라인"].firstMatch.waitForExistence(timeout: 2))
        app.buttons["라인"].firstMatch.tap()
        XCTAssertEqual(value(for: "라인"), "선택됨")

        app.buttons["보기 설정"].firstMatch.tap()
        XCTAssertTrue(app.buttons["해외거래소 차트 색상 적용"].firstMatch.waitForExistence(timeout: 2))
        app.buttons["해외거래소 차트 색상 적용"].firstMatch.tap()
        app.buttons["협정 세계시(UTC) 적용"].firstMatch.tap()
        XCTAssertEqual(value(for: "해외거래소 차트 색상 적용"), "켬")
        XCTAssertEqual(value(for: "협정 세계시(UTC) 적용"), "켬")
        XCTAssertTrue(app.buttons["종목 비교"].firstMatch.exists)

        app.buttons["종목 비교"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["종목 비교"].waitForExistence(timeout: 2))
        let quickCompareButton = app.buttons["quickCompare_ETH"]
        XCTAssertTrue(quickCompareButton.waitForExistence(timeout: 2))
        quickCompareButton.tap()
        let selectedComparedSymbol = app.otherElements.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "selectedComparedSymbol_")
        ).firstMatch
        XCTAssertTrue(selectedComparedSymbol.waitForExistence(timeout: 2))
        app.buttons["chartSettingsCompareBackButton"].tap()
        XCTAssertTrue(app.staticTexts["차트 설정"].waitForExistence(timeout: 2))

        let sheetTitle = app.staticTexts["차트 설정"].firstMatch
        let start = sheetTitle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92))
        start.press(forDuration: 0.1, thenDragTo: end)
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: sheetTitle)
        waitForExpectations(timeout: 3)

        settingsButton.tap()
        XCTAssertTrue(app.staticTexts["차트 설정"].waitForExistence(timeout: 3))
        app.buttons["지표 상세 설정"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["지표 상세 설정"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["이동평균선"].firstMatch.waitForExistence(timeout: 2))
        app.buttons["chartSettingsDetailListBackButton"].tap()
        XCTAssertTrue(app.staticTexts["차트 설정"].waitForExistence(timeout: 2))

        app.terminate()
        app.launchEnvironment["CRYPTORY_UI_TEST_RESET_DEFAULTS"] = "0"
        app.launch()

        XCTAssertTrue(settingsButton.waitForExistence(timeout: 6))
        settingsButton.tap()
        XCTAssertTrue(app.staticTexts["차트 설정"].waitForExistence(timeout: 3))
        app.buttons["차트 형식"].firstMatch.tap()
        XCTAssertTrue(app.buttons["라인"].firstMatch.waitForExistence(timeout: 2))
        XCTAssertEqual(value(for: "라인"), "선택됨")
        app.buttons["보기 설정"].firstMatch.tap()
        XCTAssertTrue(app.buttons["해외거래소 차트 색상 적용"].firstMatch.waitForExistence(timeout: 2))
        XCTAssertEqual(value(for: "해외거래소 차트 색상 적용"), "켬")
        XCTAssertEqual(value(for: "협정 세계시(UTC) 적용"), "켬")
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
