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

class MLSActionExecutorTests: ZMBaseManagedObjectTest {

    var mockCoreCrypto: MockCoreCrypto!
    var mockActionsProvider: MockMLSActionsProvider!
    var sut: MLSActionExecutor!

    override func setUp() {
        super.setUp()
        mockCoreCrypto = MockCoreCrypto()
        mockActionsProvider = MockMLSActionsProvider()
        sut = MLSActionExecutor(
            coreCrypto: mockCoreCrypto,
            context: uiMOC,
            actionsProvider: mockActionsProvider
        )
    }

    override func tearDown() {
        mockCoreCrypto = nil
        mockActionsProvider = nil
        sut = nil
        super.tearDown()
    }

    func mockUpdateEvent() -> ZMUpdateEvent {
        let payload: NSDictionary = [
            "type": "conversation.member-join",
            "data": "foo"
        ]

        return ZMUpdateEvent(fromEventStreamPayload: payload, uuid: nil)!
    }

    // MARK: - Add members

    func test_AddMembers() async throws {
        // Given
        let groupID = MLSGroupID(.random())
        let invitees = [Invitee(id: .random(), kp: .random())]

        let mockCommit = Bytes.random()
        let mockWelcome = Bytes.random()
        let mockUpdateEvent = mockUpdateEvent()

        // Mock add clients.
        var mockAddClientsArguments = [(Bytes, [Invitee])]()
        mockCoreCrypto.mockAddClientsToConversation = {
            mockAddClientsArguments.append(($0, $1))
            return MemberAddedMessages(
                commit: mockCommit,
                welcome: mockWelcome,
                publicGroupState: []
            )
        }

        // Mock send commit.
        var mockSendCommitArguments = [Data]()
        mockActionsProvider.sendMessageMocks.append({
            mockSendCommitArguments.append($0)
            return [mockUpdateEvent]
        })

        // Mock merge commit.
        var mockCommitAcceptedArguments = [Bytes]()
        mockCoreCrypto.mockCommitAccepted = {
            mockCommitAcceptedArguments.append($0)
        }

        // Mock send welcome message.
        var mockSendWelcomeArguments = [Data]()
        mockActionsProvider.sendWelcomeMessageMocks.append({
            mockSendWelcomeArguments.append($0)
        })

        // When
        let updateEvents = try await sut.addMembers(invitees, to: groupID)

        // Then core crypto added the members.
        XCTAssertEqual(mockAddClientsArguments.count, 1)
        XCTAssertEqual(mockAddClientsArguments.first?.0, groupID.bytes)
        XCTAssertEqual(mockAddClientsArguments.first?.1, invitees)

        // Then the commit was sent.
        XCTAssertEqual(mockSendCommitArguments.count, 1)
        XCTAssertEqual(mockSendCommitArguments.first, mockCommit.data)

        // Then the commit was merged.
        XCTAssertEqual(mockCommitAcceptedArguments.count, 1)
        XCTAssertEqual(mockCommitAcceptedArguments.first, groupID.bytes)

        // Then the welcome was sent.
        XCTAssertEqual(mockSendWelcomeArguments.count, 1)
        XCTAssertEqual(mockSendWelcomeArguments.first, mockWelcome.data)

        // Then the update event was returned.
        XCTAssertEqual(updateEvents, [mockUpdateEvent])
    }

    // MARK: - Remove clients

    // MARK: - Update key material

    // MARK: - Commit pending proposals

}
