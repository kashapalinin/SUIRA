//
//  SUIRAExampleUITests.swift
//  SUIRAExampleUITests
//
//  Created by Павел Калинин on 09.03.2026.
//

import XCTest

final class SUIRAExampleUITests: XCTestCase {

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
    func testRecompositionProblemsAppearInInspector() throws {
        let app = XCUIApplication()
        app.launch()

        let demoLink = app.buttons["Recomposition Problems Demo"]
        XCTAssertTrue(demoLink.waitForExistence(timeout: 5))
        demoLink.tap()

        let runButton = app.buttons["RunRecompositionProblemsDemoButton"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 5))
        runButton.tap()

        XCTAssertTrue(app.staticTexts["Тиков: 10"].waitForExistence(timeout: 5))

        let inspectorButton = app.buttons["SUIRAInspectorTopBar"]
        XCTAssertTrue(inspectorButton.waitForExistence(timeout: 5))
        inspectorButton.tap()

        XCTAssertTrue(app.staticTexts["Лишние рекомпозиции"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ProblemsDemo.HotCounter"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["P1"].waitForExistence(timeout: 5))

        XCTAssertTrue(reveal(app.staticTexts["Стабильность оптимизаций"], in: app))
        XCTAssertTrue(reveal(app.staticTexts["ProblemsDemo.HotCounter.Identity"], in: app))
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 4) -> Bool {
        if element.waitForExistence(timeout: 1) {
            return true
        }

        for _ in 0..<maxSwipes {
            app.swipeUp()
            if element.waitForExistence(timeout: 1) {
                return true
            }
        }

        return element.exists
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
