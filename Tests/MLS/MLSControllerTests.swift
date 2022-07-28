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
import XCTest
@testable import WireDataModel

@available(iOS 15, *)
class MLSControllerTests: ZMConversationTestsBase {

    var sut: MLSController!
    var mockCoreCrypto: MockCoreCrypto!
    var mockActionsProvider: MockMLSActionsProvider!
    let groupID = MLSGroupID([1, 2, 3])

    override func setUp() {
        super.setUp()
        mockCoreCrypto = MockCoreCrypto()
        mockActionsProvider = MockMLSActionsProvider()

        sut = MLSController(
            context: uiMOC,
            coreCrypto: mockCoreCrypto,
            actionsProvider: mockActionsProvider
        )
    }

    override func tearDown() {
        sut = nil
        mockCoreCrypto = nil
        mockActionsProvider = nil
        super.tearDown()
    }

    // MARK: - Message Decryption

    typealias DecryptionError = MLSController.MLSMessageDecryptionError

    func test_Decrypt_ThrowsFailedToConvertMessageToBytes() {
        syncMOC.performAndWait {
            // Given
            let invalidBase64String = "%"

            // When / Then
            assertItThrows(error: DecryptionError.failedToConvertMessageToBytes) {
                try _ = sut.decrypt(message: invalidBase64String, for: groupID)
            }
        }
    }

    func test_Decrypt_ThrowsFailedToDecryptMessage() {
        syncMOC.performAndWait {
            // Given
            let message = Data([1, 2, 3]).base64EncodedString()
            self.mockCoreCrypto.mockDecryptError = CryptoError.ConversationNotFound(message: "conversation not found")

            // When / Then
            assertItThrows(error: DecryptionError.failedToDecryptMessage) {
                try _ = sut.decrypt(message: message, for: groupID)
            }
        }
    }

    func test_Decrypt_ReturnsNil_WhenCoreCryptoReturnsNil() {
        syncMOC.performAndWait {
            // Given
            let messageBytes: Bytes = [1, 2, 3]
            self.mockCoreCrypto.mockDecryptMessage = .some(.none)

            // When
            var data: Data?
            do {
                data = try sut.decrypt(message: messageBytes.data.base64EncodedString(), for: groupID)
            } catch {
                XCTFail("Unexpected error: \(String(describing: error))")
            }

            // Then
            XCTAssertNil(data)
        }
    }

    func test_Decrypt_IsSuccessful() {
        syncMOC.performAndWait {
            // Given
            let messageBytes: Bytes = [1, 2, 3]
            self.mockCoreCrypto.mockDecryptMessage = .some(messageBytes)

            // When
            var data: Data?
            do {
                data = try sut.decrypt(message: messageBytes.data.base64EncodedString(), for: groupID)
            } catch {
                XCTFail("Unexpected error: \(String(describing: error))")
            }

            // Then
            XCTAssertEqual(data, messageBytes.data)

            let decryptMessageCalls = self.mockCoreCrypto.calls.decryptMessage
            XCTAssertEqual(decryptMessageCalls.first?.0, self.groupID.bytes)
            XCTAssertEqual(decryptMessageCalls.first?.1, messageBytes)
        }
    }

    // MARK: - Create group

    @available(iOS 15, *)
    func test_CreateGroup_ThrowsNoParticipantsToAdd() async {
        // Given
        let groupID = MLSGroupID(Data([1, 2, 3]))
        let users = [MLSUser]()

        // When / Then
        await assertItThrows(error: MLSController.MLSGroupCreationError.noParticipantsToAdd) {
            try await sut.createGroup(for: groupID, with: users)
        }
    }

    @available(iOS 15, *)
    func test_CreateGroup_IsSuccessful() async {
        // Given
        let user1ID = UUID.create()
        let user2ID = UUID.create()
        let domain = "example.com"
        let groupID = MLSGroupID(Data([1, 2, 3]))

        let user1 = MLSUser(id: user1ID, domain: domain)
        let user2 = MLSUser(id: user2ID, domain: domain)

        // Mock first key package.
        var keyPackage1: KeyPackage!

        mockActionsProvider.claimKeyPackagesMocks.append({ userID, _, _ in
            keyPackage1 = KeyPackage(
                client: "client1",
                domain: domain,
                keyPackage: Data([1, 2, 3]).base64EncodedString(),
                keyPackageRef: "keyPackageRef1",
                userID: userID
            )

            return [keyPackage1]
        })

        // Mock second key package.
        var keyPackage2: KeyPackage!

        mockActionsProvider.claimKeyPackagesMocks.append({ userID, _, _ in
            keyPackage2 = KeyPackage(
                client: "client2",
                domain: domain,
                keyPackage: Data([4, 5, 6]).base64EncodedString(),
                keyPackageRef: "keyPackageRef2",
                userID: userID
            )

            return [keyPackage2]
        })

        // Mock return value for adding clients to conversation.
        mockCoreCrypto.mockAddClientsToConversation = MemberAddedMessages(
            message: [0, 0, 0, 0],
            welcome: [1, 1, 1, 1]
        )

        // Mock sending message.
        mockActionsProvider.sendMessageMocks.append({ message in
            XCTAssertEqual(message, Data([0, 0, 0, 0]))
        })

        // Mock sending welcome message.
        mockActionsProvider.sendWelcomeMessageMocks.append({ message in
            XCTAssertEqual(message, Data([1, 1, 1, 1]))
        })

        do {
            // When
            try await sut.createGroup(for: groupID, with: [user1, user2])

        } catch let error {
            XCTFail("Unexpected error: \(String(describing: error))")
        }

        // Then
        let createConversationCalls = mockCoreCrypto.calls.createConversation
        XCTAssertEqual(createConversationCalls.count, 1)
        XCTAssertEqual(createConversationCalls[0].0, groupID.bytes)
        XCTAssertEqual(createConversationCalls[0].1, ConversationConfiguration(ciphersuite: .mls128Dhkemx25519Aes128gcmSha256Ed25519))

        let addClientsToConversationCalls = mockCoreCrypto.calls.addClientsToConversation
        XCTAssertEqual(addClientsToConversationCalls.count, 1)
        XCTAssertEqual(addClientsToConversationCalls[0].0, groupID.bytes)

        let invitee1 = Invitee(from: keyPackage1)
        let invitee2 = Invitee(from: keyPackage2)
        let actualInvitees = addClientsToConversationCalls[0].1
        XCTAssertEqual(actualInvitees.count, 2)
        XCTAssertTrue(actualInvitees.contains(invitee1))
        XCTAssertTrue(actualInvitees.contains(invitee2))
    }

}
