//
// Wire
// Copyright (C) 2021 Wire Swiss GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
//

import XCTest
@testable import WireDataModel

class AnalyticsAttributeValueTests: XCTestCase {

    func testRoundedInt() {
        // Given
        let factor = 2
        var countByBucket = [String: Int]()

        // When 500 numbers are rounded.
        for exactValue in 0..<500 {
            let roundedValue = exactValue.rounded(byFactor: factor).analyticsValue
            let existingCount = countByBucket[roundedValue] ?? 0
            countByBucket[roundedValue] = existingCount + 1
        }

        // Then there are 18 buckets with exact frequencies.
        XCTAssertEqual(countByBucket.keys.count, 18)
        XCTAssertEqual(countByBucket["0"], 1)
        XCTAssertEqual(countByBucket["1"], 1)
        XCTAssertEqual(countByBucket["2"], 1)
        XCTAssertEqual(countByBucket["3"], 1)
        XCTAssertEqual(countByBucket["4"], 2)
        XCTAssertEqual(countByBucket["6"], 2)
        XCTAssertEqual(countByBucket["8"], 4)
        XCTAssertEqual(countByBucket["12"], 4)
        XCTAssertEqual(countByBucket["16"], 7)
        XCTAssertEqual(countByBucket["23"], 9)
        XCTAssertEqual(countByBucket["32"], 14)
        XCTAssertEqual(countByBucket["46"], 18)
        XCTAssertEqual(countByBucket["64"], 27)
        XCTAssertEqual(countByBucket["91"], 37)
        XCTAssertEqual(countByBucket["128"], 54)
        XCTAssertEqual(countByBucket["182"], 74)
        XCTAssertEqual(countByBucket["256"], 107)
        XCTAssertEqual(countByBucket["363"], 137)
    }

}
