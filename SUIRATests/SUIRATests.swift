//
//  SUIRATests.swift
//  SUIRATests
//
//  Created by Павел Калинин on 09.03.2026.
//

import XCTest
@testable import SUIRA

final class SUIRATests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testRecompositionStoreRecordAndReset() throws {
        let store = RecompositionStore()
        store.isEnabled = true
        store.record(viewLabel: "A", bodyDuration: 0.001)
        store.record(viewLabel: "A", bodyDuration: nil)
        store.record(viewLabel: "B", bodyDuration: 0.002)

        XCTAssertEqual(store.countsByLabel["A"], 2)
        XCTAssertEqual(store.countsByLabel["B"], 1)
        XCTAssertEqual(store.totalCount, 3)
        XCTAssertEqual(store.events.count, 3)

        store.reset()
        XCTAssertTrue(store.events.isEmpty)
        XCTAssertTrue(store.countsByLabel.isEmpty)
    }

    @MainActor
    func testRecompositionStoreDisabledSkipsRecords() throws {
        let store = RecompositionStore()
        store.isEnabled = false
        store.record(viewLabel: "X")
        XCTAssertTrue(store.events.isEmpty)
        XCTAssertTrue(store.countsByLabel.isEmpty)
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
