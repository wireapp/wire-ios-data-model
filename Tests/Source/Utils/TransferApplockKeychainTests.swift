//
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

class TransferAppLockKeychainTests: DiskDatabaseTest {

    var appLock: AppLockController!

    override func setUp() {
        super.setUp()

        let config = AppLockController.Config(
            useBiometricsOrCustomPasscode: false,
            forceAppLock: false,
            timeOut: 900
        )

        appLock = AppLockController(config: config, selfUser: ZMUser.selfUser(in: moc))
    }
    
    override func tearDown() {
        appLock = nil
        super.tearDown()
    }
    
    func testItMigratesIsActiveStateFromTheKeychainToTheMOC() {
        // Given
        XCTAssertFalse(appLock.isActive)
        
        // When
        let data = "YES".data(using: .utf8)!
        ZMKeychain.setData(data, forAccount: "lockApp")

        TransferApplockKeychain.migrateIsAppLockActiveState(in: moc)
        
        // Then
        XCTAssertTrue(appLock.isActive)
    }
    
    func testItDoesNotMigrateIsActiveStateFromTheKeychainToTheMOC_IfKeychainIsEmpty() {
        // Given
        XCTAssertFalse(appLock.isActive)
        
        // When
        ZMKeychain.deleteAllKeychainItems(withAccountName: "lockApp")
        TransferApplockKeychain.migrateIsAppLockActiveState(in: moc)
        
        // Then
        XCTAssertFalse(appLock.isActive)
    }

    func testItMigratesPasscodes() throws {
        // Given
        let legacyItem = AppLockController.PasscodeKeychainItem.legacyItem
        let passcode = "hello".data(using: .utf8)!

        try Keychain.updateItem(legacyItem, value: passcode)
        XCTAssertEqual(try? Keychain.fetchItem(legacyItem), passcode)

        // When
        TransferApplockKeychain.migrateAppLockPasscode(in: moc)

        // Then
        XCTAssertNil(try? Keychain.fetchItem(legacyItem))

        let item = AppLockController.PasscodeKeychainItem(user: ZMUser.selfUser(in: moc))
        XCTAssertEqual(try Keychain.fetchItem(item), passcode)

        // Clean up
        try Keychain.deleteItem(item)
    }

}
