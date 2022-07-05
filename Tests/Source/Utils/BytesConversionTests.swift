//
// Wire
// Copyright (C) 2022 Wire Swiss GmbH
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

import Foundation
@testable import WireDataModel

class BytesConversionTests: XCTestCase {
    func test_stringConversions() {
        // Given
        let string = "Hello World"
        let bytes = string.bytes

        // When
        let converted = String.from(bytes: bytes)

        // Then
        XCTAssertEqual(string, converted)
    }

    func test_uuidConversions() {
        // Given
        let uuid = UUID()
        let bytes = uuid.bytes

        // When
        let converted = UUID.from(bytes: bytes)

        // Then
        XCTAssertEqual(uuid, converted)
    }
}
