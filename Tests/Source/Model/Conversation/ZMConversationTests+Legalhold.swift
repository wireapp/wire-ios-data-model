//
//  ZMConversationTests+Legalhold.swift
//  WireDataModelTests
//
//  Created by Jacob Persson on 13.05.19.
//  Copyright © 2019 Wire Swiss GmbH. All rights reserved.
//

import XCTest

class ZMConversationTests_Legalhold: ZMConversationTestsBase {
    
    // MARK - Update legal hold on client changes
    
    func testThatLegalholdIsActivatedForUser_WhenLegalholdClientIsDiscovered() {
        syncMOC.performGroupedBlock {
            // GIVEN
            let user = ZMUser.insertNewObject(in: self.syncMOC)
            XCTAssertFalse(user.isUnderLegalHold)

            // WHEN
            self.createClient(ofType: .legalHold, class: .legalHold, for: user)

            // THEN
            XCTAssertTrue(user.isUnderLegalHold)
        }
    }
    
    func testThatLegalholdIsDeactivatedForUser_WhenLegalholdClientIsDeleted() {
        syncMOC.performGroupedBlock {
            // GIVEN
            let user = ZMUser.insertNewObject(in: self.syncMOC)
            let legalHoldClient = self.createClient(ofType: .legalHold, class: .legalHold, for: user)
            XCTAssertTrue(user.isUnderLegalHold)

            // WHEN
            legalHoldClient.deleteClientAndEndSession()

            // THEN
            XCTAssertFalse(user.isUnderLegalHold)
        }
    }

    func testThatLegalholdIsActivatedForConversation_WhenLegalholdClientIsDiscovered() {
        syncMOC.performGroupedBlock {
            // GIVEN
            let selfUser = ZMUser.selfUser(in: self.syncMOC)
            let otherUser = ZMUser.insertNewObject(in: self.syncMOC)

            self.createSelfClient(onMOC: self.syncMOC)
            self.createClient(ofType: .permanent, class: .phone, for: otherUser)

            let conversation = self.createConversation(in: self.syncMOC)
            conversation.conversationType = .group
            conversation.internalAddParticipants([selfUser, otherUser])

            XCTAssertEqual(conversation.legalHoldStatus, .disabled)

            // WHEN
            let legalHoldClient = self.createClient(ofType: .legalHold, class: .legalHold, for: otherUser)
            conversation.decreaseSecurityLevelIfNeededAfterDiscovering(clients: [legalHoldClient], causedBy: [otherUser])

            // THEN
            XCTAssertEqual(conversation.legalHoldStatus, .pendingApproval)
        }
    }
    
    func testThatLegalholdIsDeactivatedInConversation_OnlyWhenTheLastLegalholdClientIsDeleted() {
        syncMOC.performGroupedBlock {
            // GIVEN
            let selfUser = ZMUser.selfUser(in: self.syncMOC)
            let otherUser = ZMUser.insertNewObject(in: self.syncMOC)

            self.createSelfClient(onMOC: self.syncMOC)
            self.createClient(ofType: .permanent, class: .phone, for: otherUser)
            let legalHoldClient = self.createClient(ofType: .legalHold, class: .legalHold, for: otherUser)

            let conversation = self.createConversation(in: self.syncMOC)
            conversation.conversationType = .group
            conversation.internalAddParticipants([selfUser, otherUser])

            XCTAssertEqual(conversation.legalHoldStatus, .pendingApproval)

            // WHEN
            legalHoldClient.deleteClientAndEndSession()

            // THEN
            XCTAssertEqual(conversation.legalHoldStatus, .disabled)
        }
    }
    
    // MARK - Update legal hold on participant changes
    
    func testThatLegalholdIsInConversation_WhenParticipantIsAdded() {
        syncMOC.performGroupedBlock {
            // GIVEN
            let selfUser = ZMUser.selfUser(in: self.syncMOC)
            let otherUser = ZMUser.insertNewObject(in: self.syncMOC)

            self.createSelfClient(onMOC: self.syncMOC)
            self.createClient(ofType: .permanent, class: .phone, for: otherUser)
            self.createClient(ofType: .legalHold, class: .legalHold, for: otherUser)

            let conversation = self.createConversation(in: self.syncMOC)
            conversation.conversationType = .group
            conversation.internalAddParticipants([selfUser])

            XCTAssertEqual(conversation.legalHoldStatus, .disabled)

            // WHEN
            conversation.internalAddParticipants([otherUser])

            // THEN
            XCTAssertEqual(conversation.legalHoldStatus, .pendingApproval)
        }
    }
    
    func testThatLegalholdIsDeactivatedInConversation_WhenTheLastLegalholdParticipantIsRemoved() {
        syncMOC.performGroupedBlock {
            // GIVEN
            let selfUser = ZMUser.selfUser(in: self.syncMOC)
            let otherUser = ZMUser.insertNewObject(in: self.syncMOC)
            let otherUserB = ZMUser.insertNewObject(in: self.syncMOC)

            self.createSelfClient(onMOC: self.syncMOC)
            self.createClient(ofType: .permanent, class: .phone, for: otherUser)
            self.createClient(ofType: .legalHold, class: .legalHold, for: otherUser)
            self.createClient(ofType: .permanent, class: .phone, for: otherUserB)

            let conversation = self.createConversation(in: self.syncMOC)
            conversation.conversationType = .group
            conversation.internalAddParticipants([selfUser, otherUser, otherUserB])

            XCTAssertEqual(conversation.legalHoldStatus, .pendingApproval)

            // WHEN
            conversation.internalRemoveParticipants([otherUser], sender: selfUser)

            // THEN
            XCTAssertEqual(conversation.legalHoldStatus, .disabled)
        }
    }
    
    func testThatLegalholdIsNotDeactivatedInConversation_WhenParticipantIsRemoved() {
        syncMOC.performGroupedBlock {
            // GIVEN
            let selfUser = ZMUser.selfUser(in: self.syncMOC)
            let otherUser = ZMUser.insertNewObject(in: self.syncMOC)
            let otherUserB = ZMUser.insertNewObject(in: self.syncMOC)

            self.createSelfClient(onMOC: self.syncMOC)
            self.createClient(ofType: .permanent, class: .phone, for: otherUser)
            self.createClient(ofType: .legalHold, class: .legalHold, for: otherUser)
            self.createClient(ofType: .permanent, class: .phone, for: otherUserB)

            let conversation = self.createConversation(in: self.syncMOC)
            conversation.conversationType = .group
            conversation.internalAddParticipants([selfUser, otherUser, otherUserB])

            XCTAssertEqual(conversation.legalHoldStatus, .pendingApproval)

            // WHEN
            conversation.internalRemoveParticipants([otherUserB], sender: selfUser)

            // THEN
            XCTAssertEqual(conversation.legalHoldStatus, .pendingApproval)
        }
    }
    
    // MARK - System messages
    
    func testThatLegalholdSystemMessageIsInserted_WhenUserIsDiscoveredToBeUnderLegalhold() {
        syncMOC.performGroupedBlock {
            // GIVEN
            let selfUser = ZMUser.selfUser(in: self.syncMOC)
            let otherUser = ZMUser.insertNewObject(in: self.syncMOC)

            self.createSelfClient(onMOC: self.syncMOC)
            self.createClient(ofType: .permanent, class: .phone, for: otherUser)

            let conversation = self.createConversation(in: self.syncMOC)
            conversation.conversationType = .group
            conversation.internalAddParticipants([selfUser, otherUser])

            XCTAssertEqual(conversation.legalHoldStatus, .disabled)

            // WHEN
            let legalHoldClient = self.createClient(ofType: .legalHold, class: .legalHold, for: otherUser)
            conversation.decreaseSecurityLevelIfNeededAfterDiscovering(clients: [legalHoldClient], causedBy: [otherUser])

            // THEN
            XCTAssertEqual(conversation.legalHoldStatus, .pendingApproval)

            let lastMessage = conversation.lastMessage as? ZMSystemMessage
            XCTAssertTrue(lastMessage?.systemMessageType == .legalHoldEnabled)
            XCTAssertTrue(lastMessage?.users == [otherUser])
        }
    }
    
    func testThatLegalholdSystemMessageIsInserted_WhenUserIsNoLongerUnderLegalhold() {
        syncMOC.performGroupedBlock {
            // GIVEN
            let selfUser = ZMUser.selfUser(in: self.syncMOC)
            let otherUser = ZMUser.insertNewObject(in: self.syncMOC)
            let otherUserB = ZMUser.insertNewObject(in: self.syncMOC)

            self.createSelfClient(onMOC: self.syncMOC)
            self.createClient(ofType: .permanent, class: .phone, for: otherUser)
            let legalHoldClient = self.createClient(ofType: .legalHold, class: .legalHold, for: otherUser)
            self.createClient(ofType: .permanent, class: .phone, for: otherUserB)

            let conversation = self.createConversation(in: self.syncMOC)
            conversation.conversationType = .group
            conversation.internalAddParticipants([selfUser, otherUser, otherUserB])

            XCTAssertEqual(conversation.legalHoldStatus, .pendingApproval)

            // WHEN
            legalHoldClient.deleteClientAndEndSession()

            // THEN
            XCTAssertEqual(conversation.legalHoldStatus, .disabled)

            let lastMessage = conversation.lastMessage as? ZMSystemMessage
            XCTAssertTrue(lastMessage?.systemMessageType == .legalHoldDisabled)
            XCTAssertEqual(lastMessage?.users, [])
        }
    }

    func testThatLegalholdSystemMessageIsInserted_WhenUserIsRemoved() {
        syncMOC.performGroupedBlock {
            // GIVEN
            let selfUser = ZMUser.selfUser(in: self.syncMOC)
            let otherUser = ZMUser.insertNewObject(in: self.syncMOC)
            let otherUserB = ZMUser.insertNewObject(in: self.syncMOC)

            self.createSelfClient(onMOC: self.syncMOC)
            self.createClient(ofType: .permanent, class: .phone, for: otherUser)
            self.createClient(ofType: .legalHold, class: .legalHold, for: otherUser)
            self.createClient(ofType: .permanent, class: .phone, for: otherUserB)

            let conversation = self.createConversation(in: self.syncMOC)
            conversation.conversationType = .group
            conversation.internalAddParticipants([selfUser, otherUser, otherUserB])

            XCTAssertEqual(conversation.legalHoldStatus, .pendingApproval)

            // WHEN
            conversation.internalRemoveParticipants([otherUser], sender: selfUser)

            // THEN
            XCTAssertEqual(conversation.legalHoldStatus, .disabled)

            let lastMessage = conversation.lastMessage as? ZMSystemMessage
            XCTAssertTrue(lastMessage?.systemMessageType == .legalHoldDisabled)
            XCTAssertTrue(lastMessage?.users == [])
        }
    }


    // MARK - Discovering legal hold
    
    func testThatItExpiresAllPendingMessages_WhenLegalholdIsDiscovered() {
        syncMOC.performGroupedBlock {
            // GIVEN
            let selfUser = ZMUser.selfUser(in: self.syncMOC)
            let otherUser = ZMUser.insertNewObject(in: self.syncMOC)

            self.createSelfClient(onMOC: self.syncMOC)
            self.createClient(ofType: .permanent, class: .phone, for: otherUser)

            let conversation = self.createConversation(in: self.syncMOC)
            conversation.conversationType = .group
            conversation.internalAddParticipants([selfUser, otherUser])

            XCTAssertEqual(conversation.legalHoldStatus, .disabled)

            // WHEN
            let message = conversation.append(text: "Legal hold is coming to town") as! ZMOTRMessage
            Thread.sleep(forTimeInterval: 0.05)

            let legalHoldClient = self.createClient(ofType: .legalHold, class: .legalHold, for: otherUser)
            conversation.decreaseSecurityLevelIfNeededAfterDiscovering(clients: [legalHoldClient], causedBy: message)

            // THEN
            XCTAssertEqual(conversation.legalHoldStatus, .pendingApproval)

            XCTAssertTrue(message.isExpired)
            XCTAssertTrue(message.causedSecurityLevelDegradation)
            XCTAssertEqual(conversation.messagesThatCausedSecurityLevelDegradation, [message])
        }
    }
    
    func testItResendsAllPreviouslyExpiredMessages_WhenConfirmingLegalholdPresence() {
        syncMOC.performGroupedBlock {
            // GIVEN
            let selfUser = ZMUser.selfUser(in: self.syncMOC)
            let otherUser = ZMUser.insertNewObject(in: self.syncMOC)

            self.createSelfClient(onMOC: self.syncMOC)
            self.createClient(ofType: .permanent, class: .phone, for: otherUser)

            let conversation = self.createConversation(in: self.syncMOC)
            conversation.conversationType = .group
            conversation.internalAddParticipants([selfUser, otherUser])

            XCTAssertEqual(conversation.legalHoldStatus, .disabled)

            // WHEN
            let message = conversation.append(text: "Legal hold is coming") as! ZMOTRMessage
            message.sender = otherUser

            let legalHoldClient = self.createClient(ofType: .legalHold, class: .legalHold, for: otherUser)
            conversation.decreaseSecurityLevelIfNeededAfterDiscovering(clients: [legalHoldClient], causedBy: message)
            XCTAssertEqual(conversation.legalHoldStatus, .pendingApproval)

            self.performPretendingSyncMocIsUiMoc {
                conversation.acknowledgePrivacyWarning(withResendIntend: true)
            }
            
            // THEN
            XCTAssertEqual(conversation.legalHoldStatus, .enabled)

            XCTAssertFalse(message.isExpired)
            XCTAssertFalse(message.causedSecurityLevelDegradation)
            XCTAssertTrue(conversation.messagesThatCausedSecurityLevelDegradation.isEmpty)
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func createClient(ofType clientType: DeviceType, class deviceClass: DeviceClass, for user: ZMUser) -> UserClient {
        let client = UserClient.insertNewObject(in: syncMOC)
        client.type = clientType
        client.deviceClass = deviceClass
        client.user = user
        return client
    }

}
