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

class MLSControllerTests: ZMConversationTestsBase {

    var sut: MLSController!
    var mockCoreCrypto: MockCoreCrypto!
    var mockActionsProvider: MockMLSActionsProvider!
    var mockConversationEventProcessor: MockConversationEventProcessor!
    var userDefaultsTestSuite: UserDefaults!

    let groupID = MLSGroupID([1, 2, 3])

    override func setUp() {
        super.setUp()
        mockCoreCrypto = MockCoreCrypto()
        mockActionsProvider = MockMLSActionsProvider()
        mockConversationEventProcessor = MockConversationEventProcessor()
        userDefaultsTestSuite = UserDefaults(suiteName: "com.wire.mls-test-suite")!

        sut = MLSController(
            context: uiMOC,
            coreCrypto: mockCoreCrypto,
            conversationEventProcessor: mockConversationEventProcessor,
            actionsProvider: mockActionsProvider,
            userDefaults: userDefaultsTestSuite
        )
    }

    override func tearDown() {
        sut = nil
        mockCoreCrypto = nil
        mockActionsProvider = nil
        super.tearDown()
    }

    // MARK: - Message Encryption

    typealias EncryptionError = MLSController.MLSMessageEncryptionError

    func test_Encrypt_IsSuccessful() {
        do {
            // Given
            let groupID = MLSGroupID([1, 1, 1])
            let unencryptedMessage: Bytes = [2, 2, 2]
            let encryptedMessage: Bytes = [3, 3, 3]

            // Mock
            mockCoreCrypto.mockEncryptMessage = encryptedMessage

            // When
            let result = try sut.encrypt(message: unencryptedMessage, for: groupID)

            // Then
            let call = mockCoreCrypto.calls.encryptMessage.element(atIndex: 0)
            XCTAssertEqual(mockCoreCrypto.calls.encryptMessage.count, 1)
            XCTAssertEqual(call?.0, groupID.bytes)
            XCTAssertEqual(call?.1, unencryptedMessage)
            XCTAssertEqual(result, encryptedMessage)

        } catch {
            XCTFail("Unexpected error: \(String(describing: error))")
        }
    }

    func test_Encrypt_Fails() {
        // Given
        let groupID = MLSGroupID([1, 1, 1])
        let unencryptedMessage: Bytes = [2, 2, 2]

        // Mock
        mockCoreCrypto.mockEncryptError = CryptoError.InvalidByteArrayError(message: "bad bytes!")

        // When / Then
        assertItThrows(error: EncryptionError.failedToEncryptMessage) {
            _ = try sut.encrypt(message: unencryptedMessage, for: groupID)
        }
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

    func test_CreateGroup_IsSuccessful() throws {
        // Given
        let groupID = MLSGroupID(Data([1, 2, 3]))

        // When
        XCTAssertNoThrow(try sut.createGroup(for: groupID))

        // Then
        let createConversationCalls = mockCoreCrypto.calls.createConversation
        XCTAssertEqual(createConversationCalls.count, 1)
        XCTAssertEqual(createConversationCalls[0].0, groupID.bytes)
        XCTAssertEqual(createConversationCalls[0].1, ConversationConfiguration(ciphersuite: .mls128Dhkemx25519Aes128gcmSha256Ed25519))
    }

    func test_CreateGroup_ThrowsError() throws {
        // Given
        let groupID = MLSGroupID(Data([1, 2, 3]))
        mockCoreCrypto.mockCreateConversationError = CryptoError.MalformedIdentifier(message: "bad id")

        // When
        XCTAssertThrowsError(try sut.createGroup(for: groupID)) { error in
            switch error {
            case MLSController.MLSGroupCreationError.failedToCreateGroup:
                break

            default:
                XCTFail("Unexpected error: \(String(describing: error))")
            }
        }

        // Then
        let createConversationCalls = mockCoreCrypto.calls.createConversation
        XCTAssertEqual(createConversationCalls.count, 1)
        XCTAssertEqual(createConversationCalls[0].0, groupID.bytes)
        XCTAssertEqual(createConversationCalls[0].1, ConversationConfiguration(ciphersuite: .mls128Dhkemx25519Aes128gcmSha256Ed25519))
    }

    // MARK: - Adding participants

    func test_AddingMembersToConversation_Successfully() async {
        // Given
        let domain = "example.com"
        let id = UUID.create()
        let mlsGroupID = MLSGroupID(Data([1, 2, 3]))
        let mlsUser: [MLSUser] = [MLSUser(id: id, domain: domain)]

        // Mock key package.
        var keyPackage: KeyPackage!

        mockActionsProvider.claimKeyPackagesMocks.append({ userID, _, _ in
            keyPackage = KeyPackage(
                client: "client",
                domain: domain,
                keyPackage: Data([1, 2, 3]).base64EncodedString(),
                keyPackageRef: "keyPackageRef",
                userID: userID
            )

            return [keyPackage]
        })

        // Mock return value for adding clients to conversation.
        mockCoreCrypto.mockAddClientsToConversation = MemberAddedMessages(
            message: [0, 0, 0, 0],
            welcome: [1, 1, 1, 1]
        )

        // Mock update event for member joins the conversation
        var updateEvent: ZMUpdateEvent!

        // Mock sending message.
        mockActionsProvider.sendMessageMocks.append({ message in
            XCTAssertEqual(message, Data([0, 0, 0, 0]))

            let mockPayload: NSDictionary = [
                "type": "conversation.member-join",
                "data": message
            ]

            updateEvent = ZMUpdateEvent(fromEventStreamPayload: mockPayload, uuid: nil)!

            return [updateEvent]
        })

        // Mock sending welcome message.
        mockActionsProvider.sendWelcomeMessageMocks.append({ message in
            XCTAssertEqual(message, Data([1, 1, 1, 1]))
        })

        do {
            // When
            try await sut.addMembersToConversation(with: mlsUser, for: mlsGroupID)

        } catch let error {
            XCTFail("Unexpected error: \(String(describing: error))")
        }

        let processConversationEventsCalls = self.mockConversationEventProcessor.calls.processConversationEvents
        XCTAssertEqual(processConversationEventsCalls.count, 1)
        XCTAssertEqual(processConversationEventsCalls[0], [updateEvent])

        let addClientsToConversationCalls = mockCoreCrypto.calls.addClientsToConversation
        XCTAssertEqual(addClientsToConversationCalls.count, 1)
        XCTAssertEqual(addClientsToConversationCalls[0].0, mlsGroupID.bytes)

        let invitee = Invitee(from: keyPackage)
        let actualInvitees = addClientsToConversationCalls[0].1
        XCTAssertEqual(actualInvitees.count, 1)
        XCTAssertTrue(actualInvitees.contains(invitee))
    }

    func test_AddingMembersToConversation_ThrowsNoParticipantsToAdd() async {
        // Given
        let mlsGroupID = MLSGroupID(Data([1, 2, 3]))
        let mlsUser = [MLSUser]()

        do {
            // When
            try await sut.addMembersToConversation(with: mlsUser, for: mlsGroupID)

        } catch let error {
            // Then
            switch error {
            case MLSController.MLSGroupCreationError.noParticipantsToAdd:
                break

            default:
                XCTFail("Unexpected error: \(String(describing: error))")
            }
        }
    }

    func test_AddingMembersToConversation_ThrowsFailedToClaimKeyPackages() async {
        // Given
        let domain = "example.com"
        let id = UUID.create()
        let mlsGroupID = MLSGroupID(Data([1, 2, 3]))
        let mlsUser: [MLSUser] = [MLSUser(id: id, domain: domain)]

        do {
            // When
            try await sut.addMembersToConversation(with: mlsUser, for: mlsGroupID)

        } catch let error {
            // Then
            switch error {
            case MLSController.MLSGroupCreationError.failedToClaimKeyPackages:
                break

            default:
                XCTFail("Unexpected error: \(String(describing: error))")
            }
        }
    }

    func test_AddingMembersToConversation_ThrowsFailedToSendHandshakeMessage() async {
        // Given
        let domain = "example.com"
        let id = UUID.create()
        let mlsGroupID = MLSGroupID(Data([1, 2, 3]))
        let mlsUser: [MLSUser] = [MLSUser(id: id, domain: domain)]

        // Mock key package.
        var keyPackage: KeyPackage!

        mockActionsProvider.claimKeyPackagesMocks.append({ userID, _, _ in
            keyPackage = KeyPackage(
                client: "client",
                domain: domain,
                keyPackage: Data([1, 2, 3]).base64EncodedString(),
                keyPackageRef: "keyPackageRef",
                userID: userID
            )

            return [keyPackage]
        })

        // Mock return value for adding clients to conversation.
        mockCoreCrypto.mockAddClientsToConversation = MemberAddedMessages(
            message: [0, 0, 0, 0],
            welcome: [1, 1, 1, 1]
        )

        do {
            // When
            try await sut.addMembersToConversation(with: mlsUser, for: mlsGroupID)

        } catch let error {
            // Then
            switch error {
            case MLSController.MLSGroupCreationError.failedToSendHandshakeMessage:
                break

            default:
                XCTFail("Unexpected error: \(String(describing: error))")
            }
        }
    }

    func test_AddingMembersToConversation_ThrowsFailedToSendWelcomeMessage() async {
        // Given
        let domain = "example.com"
        let id = UUID.create()
        let mlsGroupID = MLSGroupID(Data([1, 2, 3]))
        let mlsUser: [MLSUser] = [MLSUser(id: id, domain: domain)]

        // Mock key package.
        var keyPackage: KeyPackage!

        mockActionsProvider.claimKeyPackagesMocks.append({ userID, _, _ in
            keyPackage = KeyPackage(
                client: "client",
                domain: domain,
                keyPackage: Data([1, 2, 3]).base64EncodedString(),
                keyPackageRef: "keyPackageRef",
                userID: userID
            )

            return [keyPackage]
        })

        // Mock return value for adding clients to conversation.
        mockCoreCrypto.mockAddClientsToConversation = MemberAddedMessages(
            message: [0, 0, 0, 0],
            welcome: [1, 1, 1, 1]
        )

        // Mock update event for member joins the conversation
        var updateEvent: ZMUpdateEvent!

        // Mock sending message.
        mockActionsProvider.sendMessageMocks.append({ message in
            XCTAssertEqual(message, Data([0, 0, 0, 0]))

            let mockPayload: NSDictionary = [
                "type": "conversation.member-join",
                "data": message
            ]

            updateEvent = ZMUpdateEvent(fromEventStreamPayload: mockPayload, uuid: nil)!

            return [updateEvent]
        })

        do {
            // When
            try await sut.addMembersToConversation(with: mlsUser, for: mlsGroupID)

        } catch let error {
            // Then
            switch error {
            case MLSController.MLSGroupCreationError.failedToSendWelcomeMessage:

                let processConversationEventsCalls = self.mockConversationEventProcessor.calls.processConversationEvents
                XCTAssertEqual(processConversationEventsCalls.count, 1)
                XCTAssertEqual(processConversationEventsCalls[0], [updateEvent])

            default:
                XCTFail("Unexpected error: \(String(describing: error))")
            }
        }
    }

    // MARK: - Remove participants

    func test_RemoveMembersFromConversation_IsSuccessful() async {
        // Given
        let domain = "example.com"
        let id = UUID.create().uuidString
        let clientID = UUID.create().uuidString
        let mlsGroupID = MLSGroupID(Data([1, 2, 3]))
        let mlsClientID = MLSClientID(userID: id, clientID: clientID, domain: domain)

        // Mock return value for removing clients to conversation.
        mockCoreCrypto.mockRemoveClientsFromConversation = [0, 0, 0, 0]

        // Mock update event for member leaves from conversation
        var updateEvent: ZMUpdateEvent!

        // Mock sending message.
        mockActionsProvider.sendMessageMocks.append({ message in
            XCTAssertEqual(message, Data([0, 0, 0, 0]))

            let mockPayload: NSDictionary = [
                "type": "conversation.member-leave",
                "data": message
            ]

            updateEvent = ZMUpdateEvent(fromEventStreamPayload: mockPayload, uuid: nil)!

            return [updateEvent]
        })

        do {
            // When
            try await sut.removeMembersFromConversation(with: [mlsClientID], for: mlsGroupID)

        } catch let error {
            XCTFail("Unexpected error: \(String(describing: error))")
        }

        // Then
        let processConversationEventsCalls = self.mockConversationEventProcessor.calls.processConversationEvents
        XCTAssertEqual(processConversationEventsCalls.count, 1)
        XCTAssertEqual(processConversationEventsCalls[0], [updateEvent])

        let removeMembersFromConversationCalls = mockCoreCrypto.calls.removeClientsFromConversation
        XCTAssertEqual(removeMembersFromConversationCalls.count, 1)
        XCTAssertEqual(removeMembersFromConversationCalls[0].0, mlsGroupID.bytes)

        let mlsClientIDBytes = mlsClientID.string.data(using: .utf8)!.bytes
        XCTAssertEqual(removeMembersFromConversationCalls[0].1, [mlsClientIDBytes])
    }

    func test_RemovingMembersToConversation_ThrowsNoClientsToRemove() async {
        // Given
        let mlsGroupID = MLSGroupID(Data([1, 2, 3]))

        do {
            // When
            try await sut.removeMembersFromConversation(with: [], for: mlsGroupID)

        } catch let error {
            // Then
            switch error {
            case MLSController.MLSRemoveParticipantsError.noClientsToRemove:
                break

            default:
                XCTFail("Unexpected error: \(String(describing: error))")
            }
        }
    }

    func test_RemovingMembersToConversation_FailsToSendHandShakeMessage() async {
        // Given
        let domain = "example.com"
        let id = UUID.create().uuidString
        let clientID = UUID.create().uuidString
        let mlsGroupID = MLSGroupID(Data([1, 2, 3]))
        let mlsClientID = MLSClientID(userID: id, clientID: clientID, domain: domain)

        // Mock return value for removing clients to conversation.
        mockCoreCrypto.mockRemoveClientsFromConversation = [0, 0, 0, 0]

        do {
            // When
            try await sut.removeMembersFromConversation(with: [mlsClientID], for: mlsGroupID)

        } catch let error {
            // Then
            switch error {
            case MLSController.MLSGroupCreationError.failedToSendHandshakeMessage:
                break

            default:
                XCTFail("Unexpected error: \(String(describing: error))")
            }
        }
    }

    func test_upload_100_KeyPackages_successfully() {
        // Given
        let clientID = self.createSelfClient(onMOC: uiMOC).remoteIdentifier
        let keyPackages: [Bytes] = [
            [1, 2, 3],
            [4, 5, 6]
        ]

        // expectation
        let countUnclaimedKeyPackages = self.expectation(description: "Count unclaimed key packages")
        let uploadKeyPackages = self.expectation(description: "Upload key packages")

        mockCoreCrypto.mockClientKeyPackages = keyPackages

        // Mock return value for unclaimed key packages count.
        mockActionsProvider.countUnclaimedKeyPackagesMocks.append { cid in
            XCTAssertEqual(cid, clientID)
            countUnclaimedKeyPackages.fulfill()

            return 0
        }

        mockActionsProvider.uploadKeyPackagesMocks.append { cid, kp in
            let keyPackages = keyPackages.map { $0.base64EncodedString }

            XCTAssertEqual(cid, clientID)
            XCTAssertEqual(kp, keyPackages)

            uploadKeyPackages.fulfill()
        }

        // When
        sut.uploadKeyPackagesIfNeeded()

        // Then
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 5))
        let clientKeypackagesCalls = mockCoreCrypto.calls.clientKeypackages
        XCTAssertEqual(clientKeypackagesCalls.count, 1)
        XCTAssertEqual(clientKeypackagesCalls[0], 100)
    }
}
