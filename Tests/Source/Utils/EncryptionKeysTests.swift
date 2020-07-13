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

class EncryptionKeysTests: XCTestCase {
    
    var account: Account!

    override func setUpWithError() throws {
        account = Account(userName: "John Doe", userIdentifier: UUID())
    }

    override func tearDownWithError() throws {
        try EncryptionKeys.deleteKeys(for: account)
        account = nil
    }
    
    func testThatEncryptionKeysThrowsIfKeysDontExist() {
        XCTAssertThrowsError(try EncryptionKeys(account: account))
    }
    
    func testThatPublicAccountKeyThrowsIfItDoesNotExist() throws {
        XCTAssertThrowsError(try EncryptionKeys.publicKey(for: account))
    }
    
    func testThatPublicAccountKeyIsReturnedIfItExists() throws {
        // given
        try EncryptionKeys.createKeys(for: account)
        
        // when
        let publicKey = try EncryptionKeys.publicKey(for: account)
        
        // then
        XCTAssertNotNil(publicKey)
    }

    func testThatEncryptionKeysAreSuccessfullyCreated() throws {
        // when
        try EncryptionKeys.createKeys(for: account)
        
        // then
        let encryptionkeys = try EncryptionKeys(account: account)
        XCTAssertEqual(encryptionkeys.databaseKey.count, 256)
    }
    
    func testThatEncryptionKeysAreSuccessfullyDeleted() throws {
        // given
        try EncryptionKeys.createKeys(for: account)
        
        // when
        try EncryptionKeys.deleteKeys(for: account)
        
        // then
        XCTAssertThrowsError(try EncryptionKeys(account: account))
    }
    
    func testThatAsymmetricKeysWorksWithExpectedAlgorithm() throws {
        // given
        let data = "Hello world".data(using: .utf8)!
        try EncryptionKeys.createKeys(for: account)
        
        // when
        let encryptionkeys = try EncryptionKeys(account: account)
        
        let encryptedData = SecKeyCreateEncryptedData(encryptionkeys.publicKey,
                                                      .eciesEncryptionCofactorX963SHA256AESGCM,
                                                      data as CFData,
                                                      nil)!
        
        let decryptedData = SecKeyCreateDecryptedData(encryptionkeys.privateKey,
                                                      .eciesEncryptionCofactorX963SHA256AESGCM,
                                                      encryptedData,
                                                      nil)!
        
        XCTAssertEqual(decryptedData as Data, data)
    }
    
}
