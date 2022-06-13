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

import XCTest
@testable import WireDataModel

class KeychainManagerTests: XCTestCase {

    var account: Account!

    override func setUpWithError() throws {
        account = Account(userName: "John Doe", userIdentifier: UUID())
    }

    override func tearDownWithError() throws {
        try EncryptionKeys.deleteKeys(for: account)
        account = nil
    }

    func testEncryptionKeyGenerateSuccessfully() throws {

        // Given
        let numberOfBytes: UInt = 32

        // When
        let result = try KeychainManager.generateKey(numberOfBytes: numberOfBytes)

        // Then
        XCTAssertNoThrow(result, "Key generation should complete successfully.")
    }

    func testPublicPrivateKeyPairIsGeneratedSuccessfully() throws {

        #if targetEnvironment(simulator) && swift(>=5.4)
        if #available(iOS 15, *) {
            XCTExpectFailure("Expect to fail on iOS 15 simulator. ref: https://wearezeta.atlassian.net/browse/SQCORE-1188")
        }
        #endif

        // Given
        let item = EncryptionKeys.KeychainItem.databaseKey(account)
        let identifier = item.uniqueIdentifier

        // Then
        XCTAssertNoThrow(try KeychainManager.generatePublicPrivateKeyPair(identifier: identifier), "Public Private KeyPair should be created successfully.")
    }

    func testKeychainItemsStoreSuccessfully() throws {
        #if targetEnvironment(simulator) && swift(>=5.4)
        if #available(iOS 15, *) {
            XCTExpectFailure("Expect to fail on iOS 15 simulator. ref: https://wearezeta.atlassian.net/browse/SQCORE-1188")
        }
        #endif

        // Given
        let item = EncryptionKeys.KeychainItem.databaseKey(account)
        let value = try KeychainManager.generateKey()

        // Then
        XCTAssertNoThrow(value, "Key generation should complete successfully.")
        XCTAssertNoThrow(try KeychainManager.storeItem(item, value: value), "Item should be store successfully.")
    }

    func testKeychainItemsFetchedSuccessfully() throws {
        #if targetEnvironment(simulator) && swift(>=5.4)
        if #available(iOS 15, *) {
            XCTExpectFailure("Expect to fail on iOS 15 simulator. ref: https://wearezeta.atlassian.net/browse/SQCORE-1188")
        }
        #endif

        // Given
        let item = EncryptionKeys.KeychainItem.databaseKey(account)

        // Then
        do {
            let item: Data = try KeychainManager.fetchItem(item)
            XCTAssertNotNil(item, "Item should be fetch successfully.")

        } catch {
            XCTFail("Failed to fetch the fetch item.")
        }
    }

    func testKeychainItemsDeleteSuccessfully() throws {
        #if targetEnvironment(simulator) && swift(>=5.4)
        if #available(iOS 15, *) {
            XCTExpectFailure("Expect to fail on iOS 15 simulator. ref: https://wearezeta.atlassian.net/browse/SQCORE-1188")
        }
        #endif

        // Given
        let item = EncryptionKeys.KeychainItem.databaseKey(account)
        let value = try KeychainManager.generateKey()

        // When
        XCTAssertNoThrow(value, "Key generation should complete successfully.")
        XCTAssertNoThrow(try KeychainManager.storeItem(item, value: value), "Item should be store successfully.")

        // Then
        XCTAssertNoThrow(try KeychainManager.deleteItem(item))
        let fetchItem: Data = try KeychainManager.fetchItem(item)
        XCTAssertNil(fetchItem, "Deleted item should not supposed to fetch again.")
    }
}
