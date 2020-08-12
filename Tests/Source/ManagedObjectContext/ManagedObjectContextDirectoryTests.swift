////
// Wire
// Copyright (C) 2020 Wire Swiss GmbH
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

class ManagedObjectContextDirectoryTests: DatabaseBaseTest {

    func testThatItStoresAndClearsDatabaseKeyOnAllContexts() {
        // Given
        let sut = createStorageStackAndWaitForCompletion()
        let databaseKey = "abc".data(using: .utf8)!

        // When
        sut.storeDatabaseKeyInAllContexts(databaseKey: databaseKey)

        // Then
        sut.uiContext.performGroupedBlockAndWait {
            XCTAssertEqual(sut.uiContext.databaseKey, databaseKey)
        }

        sut.syncContext.performGroupedBlockAndWait {
            XCTAssertEqual(sut.syncContext.databaseKey, databaseKey)
        }

        sut.searchContext.performGroupedBlockAndWait {
            XCTAssertEqual(sut.searchContext.databaseKey, databaseKey)
        }

        // When
        sut.clearDatabaseKeyInAllContexts()

        // Then
        sut.uiContext.performGroupedBlockAndWait {
            XCTAssertNil(sut.uiContext.databaseKey)
        }

        sut.syncContext.performGroupedBlockAndWait {
            XCTAssertNil(sut.syncContext.databaseKey)
        }

        sut.searchContext.performGroupedBlockAndWait {
            XCTAssertNil(sut.searchContext.databaseKey)
        }
    }

}