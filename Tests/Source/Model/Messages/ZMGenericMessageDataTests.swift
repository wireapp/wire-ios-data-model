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

class ZMGenericMessageDataTests: ModelObjectsTests {

    // MARK: - Set Up

    override func setUp() {
        super.setUp()
        
        createSelfClient(onMOC: uiMOC)
        uiMOC.encryptMessagesAtRest = false
        uiMOC.encryptionKeys = nil
    }
    
    // MARK: - Positive Tests

    func test_ItDoesNotEncryptProtobufData_IfEncryptionAtRest_IsDisabled() throws {
        // Given
        let sut = ZMGenericMessageData.insertNewObject(in: uiMOC)
        let genericMessage = createGenericMessage(text: "Hello, world")
        let messageData = try genericMessage.serializedData()

        uiMOC.encryptMessagesAtRest = false

        // When
        sut.setProtobuf(messageData)

        // Then
        XCTAssertFalse(sut.isEncrypted)
        XCTAssertNil(sut.nonce)
        XCTAssertEqual(sut.underlyingMessage, genericMessage)
    }

    func test_ItEncryptsAndDecryptsProtobufData_IfEncryptionAtRest_IsEnabled() throws {
        // Given
        let sut = ZMGenericMessageData.insertNewObject(in: uiMOC)
        let genericMessage = createGenericMessage(text: "Hello, world")
        let messageData = try genericMessage.serializedData()

        uiMOC.encryptMessagesAtRest = true
        uiMOC.encryptionKeys = validEncryptionKeys

        // When
        sut.setProtobuf(messageData)

        // Then
        XCTAssertTrue(sut.isEncrypted)
        XCTAssertNotNil(sut.nonce)
        XCTAssertEqual(sut.underlyingMessage, genericMessage)
    }

    // MARK: - Negative Tests

    func test_ItDoesNotStoreData_IfDatabaseKeyIsMissing_WhenEncrypting() throws {
        // Given
        let sut = ZMGenericMessageData.insertNewObject(in: uiMOC)
        let oldGenericMessage = try createAndStoreEncryptedData(sut: sut, text: "Hello, world")
        let encryptionKeys = uiMOC.encryptionKeys

        // When
        let newGenericMessage = createGenericMessage(text: "Goodbye!")
        let newMessageData = try newGenericMessage.serializedData()

        uiMOC.encryptionKeys = nil

        sut.setProtobuf(newMessageData)

        // Then
        uiMOC.encryptionKeys = encryptionKeys

        XCTAssertEqual(sut.underlyingMessage, oldGenericMessage)
    }

    func test_ItDoesNotReturnData_IfDatabaseKeyIsMissing_WhenDecrypting() throws {
        // Given
        let sut = ZMGenericMessageData.insertNewObject(in: uiMOC)
        try createAndStoreEncryptedData(sut: sut, text: "Hello, world")

        // When
        uiMOC.encryptionKeys = nil

        // Then
        XCTAssertNil(sut.underlyingMessage)
    }

    func test_ItDoesNotStoreData_IfEncryptionFails_WhenEncrypting() throws {
        // Given
        let sut = ZMGenericMessageData.insertNewObject(in: uiMOC)
        let oldGenericMessage = try createAndStoreEncryptedData(sut: sut, text: "Hello, world")
        let encryptionKeys = uiMOC.encryptionKeys

        // When
        let newGenericMessage = createGenericMessage(text: "Goodbye!")
        let newMessageData = try newGenericMessage.serializedData()

        uiMOC.encryptionKeys = malformedEncryptionKeys

        sut.setProtobuf(newMessageData)

        // Then
        uiMOC.encryptionKeys = encryptionKeys

        XCTAssertEqual(sut.underlyingMessage, oldGenericMessage)
    }

    func test_ItDoesNotReturnData_IfDecryptionFails_WhenDecrypting() throws {
        // Given
        let sut = ZMGenericMessageData.insertNewObject(in: uiMOC)
        try createAndStoreEncryptedData(sut: sut, text: "Hello, world")

        // When
        uiMOC.encryptionKeys = malformedEncryptionKeys

        // Then
        XCTAssertNil(sut.underlyingMessage)
    }

    // MARK: - Helpers

    private func createGenericMessage(text: String) -> GenericMessage {
        return GenericMessage(content: Text(content: text))
    }

    @discardableResult
    private func createAndStoreEncryptedData(sut: ZMGenericMessageData, text: String) throws -> GenericMessage {
        let genericMessage = createGenericMessage(text: text)
        let messageData = try genericMessage.serializedData()

        uiMOC.encryptMessagesAtRest = true
        uiMOC.encryptionKeys = validEncryptionKeys

        sut.setProtobuf(messageData)

        XCTAssertEqual(sut.underlyingMessage, genericMessage)

        return genericMessage
    }

}
