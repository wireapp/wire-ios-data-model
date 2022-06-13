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

        // Then
        do {
            let result = try KeychainManager.generateKey(numberOfBytes: numberOfBytes)
            XCTAssertNotNil(result, "Result must have some data bytes.")

        } catch {
            XCTFail("Failed to generate the key successfully.")
        }
    }

    func testPublicPrivateKeyPairIsGeneratedSuccessfully() throws {

        #if targetEnvironment(simulator) && swift(>=5.4)
        if #available(iOS 15, *) {
            XCTExpectFailure("Expect to fail on iOS 15 simulator. ref: https://wearezeta.atlassian.net/browse/SQCORE-1188")
        }
        #endif

        // Given
        let item = EncryptionKeys.KeychainItem.databaseKey(account)

        // Then
        do {
            let result = try KeychainManager.generatePublicPrivateKeyPair(identifier: item.uniqueIdentifier)
            XCTAssertNotNil(result, "Public Private KeyPair should be created successfully.")

        } catch {
            XCTFail("Failed to create Public Private KeyPair.")
        }
    }

    func testKeychainItemsStoreSuccessfully() throws {
        #if targetEnvironment(simulator) && swift(>=5.4)
        if #available(iOS 15, *) {
            XCTExpectFailure("Expect to fail on iOS 15 simulator. ref: https://wearezeta.atlassian.net/browse/SQCORE-1188")
        }
        #endif

        // Given
        let item = EncryptionKeys.KeychainItem.databaseKey(account)

        // Then
        do {
            let key = try KeychainManager.generateKey()
            XCTAssertNotNil(key, "Failed to generate the key.")

            // Store new item
            try KeychainManager.storeItem(item, value: key)

            // Fetching the stored item to ensure its stored successfully
            let fetchItem: Data = try KeychainManager.fetchItem(item)
            XCTAssertNotNil(fetchItem, "Item should be fetch successfully.")

        } catch (let error){
            XCTFail("Failed to store item with error: \(error).")
        }
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
            let key = try KeychainManager.generateKey()
            XCTAssertNotNil(key, "Failed to generate the key.")

            // Store new item
            try KeychainManager.storeItem(item, value: key)

            // Fetching and comparing the stored and fetchItem
            let fetchItem: EncryptionKeys.KeychainItem = try KeychainManager.fetchItem(item)
            XCTAssertEqual(fetchItem, item)

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

        // Then
        do {
            let key = try KeychainManager.generateKey()
            XCTAssertNotNil(key, "Failed to generate the key.")

            // Store new item
            try KeychainManager.storeItem(item, value: key)

            // delete the stored item
            try KeychainManager.deleteItem(item)

        } catch (let error){
            XCTFail("Failed to store item with error: \(error).")
        }

        // Check to ensure the item can't be fetched after deletion.
        XCTAssertThrowsError(try KeychainManager.fetchItem(item) as Data, "Deleted item should not supposed to fetch again.")
    }
}
