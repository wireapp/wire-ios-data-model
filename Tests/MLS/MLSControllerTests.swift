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

    // MARK: - Create group

    @available(iOS 15, *)
    func test_CreateGroup_ThrowsNoGroupID() async {
        // Given
        var conversation: ZMConversation!

        uiMOC.performAndWait {
            conversation = createConversation(in: uiMOC)
            XCTAssertNil(conversation.mlsGroupID)
        }

        do {
            // When
            try await sut.createGroup(for: conversation)

        } catch let error {
            // Then
            switch error {
            case MLSController.MLSGroupCreationError.noGroupID:
                break

            default:
                XCTFail("Unexpected error: \(String(describing: error))")
            }
        }
    }

    @available(iOS 15, *)
    func test_CreateGroup_ThrowsNotAnMLSConversation() async {
        // Given
        var conversation: ZMConversation!

        uiMOC.performAndWait {
            conversation = createConversation(in: uiMOC)
            conversation.mlsGroupID = MLSGroupID(Data([1, 2, 3]))
            conversation.messageProtocol = .proteus
        }

        do {
            // When
            try await sut.createGroup(for: conversation)

        } catch let error {
            // Then
            switch error {
            case MLSController.MLSGroupCreationError.notAnMLSConversation:
                break

            default:
                XCTFail("Unexpected error: \(String(describing: error))")
            }
        }
    }

    @available(iOS 15, *)
    func test_CreateGroup_ThrowsNoParticipantsToAdd() async {
        // Given
        var conversation: ZMConversation!

        uiMOC.performAndWait {
            conversation = createConversation(in: uiMOC)
            conversation.mlsGroupID = MLSGroupID(Data([1, 2, 3]))
            conversation.messageProtocol = .mls
            XCTAssertTrue(conversation.localParticipants.isEmpty)
        }

        do {
            // When
            try await sut.createGroup(for: conversation)

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

    @available(iOS 15, *)
    func test_CreateGroup_IsSuccessful() async {
        // Given
        let user1ID = UUID.create()
        let user2ID = UUID.create()
        let domain = "example.com"
        let mlsGroupID = MLSGroupID(Data([1, 2, 3]))
        var conversation: ZMConversation!

        uiMOC.performAndWait {
            let user1 = createUser(in: uiMOC)
            user1.remoteIdentifier = user1ID
            user1.domain = domain

            let user2 = createUser(in: uiMOC)
            user2.remoteIdentifier = user2ID
            user2.domain = domain

            conversation = createConversation(in: uiMOC, with: [user1, user2])
            conversation.mlsGroupID = mlsGroupID
            conversation.messageProtocol = .mls
        }

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
            XCTAssertEqual(message, Data([0, 0, 0, 0]).base64EncodedString())
        })

        // Mock sending welcome message.
        mockActionsProvider.sendWelcomeMessageMocks.append({ message in
            XCTAssertEqual(message, Data([1, 1, 1, 1]).base64EncodedString())
        })

        do {
            // When
            try await sut.createGroup(for: conversation)

        } catch let error {
            XCTFail("Unexpected error: \(String(describing: error))")
        }

        // Then
        let createConversationCalls = mockCoreCrypto.calls.createConversation
        XCTAssertEqual(createConversationCalls.count, 1)
        XCTAssertEqual(createConversationCalls[0].0, mlsGroupID.bytes)
        XCTAssertEqual(createConversationCalls[0].1, ConversationConfiguration(ciphersuite: .mls128Dhkemx25519Aes128gcmSha256Ed25519))

        let addClientsToConversationCalls = mockCoreCrypto.calls.addClientsToConversation
        XCTAssertEqual(addClientsToConversationCalls.count, 1)
        XCTAssertEqual(addClientsToConversationCalls[0].0, mlsGroupID.bytes)

        let invitee1 = Invitee(from: keyPackage1)
        let invitee2 = Invitee(from: keyPackage2)
        let actualInvitees = addClientsToConversationCalls[0].1
        XCTAssertEqual(actualInvitees.count, 2)
        XCTAssertTrue(actualInvitees.contains(invitee1))
        XCTAssertTrue(actualInvitees.contains(invitee2))
    }

    @available(iOS 15, *)
    func test_AddParticipantsToConversations_IsSuccessful() async {
        // Given
        let domain = "example.com"
        let mlsGroupID = MLSGroupID(Data([1, 2, 3]))
        var conversation: ZMConversation!
        var mlsUser = [ZMUser]()

        uiMOC.performAndWait {
            let user = createUser(in: uiMOC)
            user.remoteIdentifier = UUID.create()
            user.domain = domain

            conversation = createConversation(in: uiMOC, with: [user])
            conversation.mlsGroupID = mlsGroupID
            conversation.messageProtocol = .mls

            let user2 = createUser(in: uiMOC)
            user2.remoteIdentifier = UUID.create()
            user2.domain = domain
            mlsUser.append(user)
        }

        // Mock first key package.
        var keyPackage: KeyPackage!

        mockActionsProvider.claimKeyPackagesMocks.append({ userID, _, _ in
            keyPackage = KeyPackage(
                client: "client1",
                domain: domain,
                keyPackage: Data([1, 2, 3]).base64EncodedString(),
                keyPackageRef: "keyPackageRef1",
                userID: userID
            )

            return [keyPackage]
        })

        // Mock return value for adding clients to conversation.
        mockCoreCrypto.mockAddClientsToConversation = MemberAddedMessages(
            message: [0, 0, 0, 0],
            welcome: [1, 1, 1, 1]
        )

        // Mock sending message.
        mockActionsProvider.sendMessageMocks.append({ message in
            XCTAssertEqual(message, Data([0, 0, 0, 0]).base64EncodedString())
        })

        // Mock sending welcome message.
        mockActionsProvider.sendWelcomeMessageMocks.append({ message in
            XCTAssertEqual(message, Data([1, 1, 1, 1]).base64EncodedString())
        })

        do {
            // When
            try await sut.addParticipants(users: mlsUser, conversation: conversation)

        } catch let error {
            XCTFail("Unexpected error: \(String(describing: error))")
        }

        let addClientsToConversationCalls = mockCoreCrypto.calls.addClientsToConversation
        XCTAssertEqual(addClientsToConversationCalls.count, 1)
        XCTAssertEqual(addClientsToConversationCalls[0].0, mlsGroupID.bytes)

        let invitee1 = Invitee(from: keyPackage)
        let actualInvitees = addClientsToConversationCalls[0].1
        XCTAssertEqual(actualInvitees.count, 1)
        XCTAssertTrue(actualInvitees.contains(invitee1))
    }

}
