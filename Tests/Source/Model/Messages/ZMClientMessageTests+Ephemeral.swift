//
// Wire
// Copyright (C) 2016 Wire Swiss GmbH
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
import WireCryptobox
import WireLinkPreview

@testable import WireDataModel

class ZMClientMessageTests_Ephemeral : BaseZMClientMessageTests {
    
    override func setUp() {
        super.setUp()
        deletionTimer.isTesting = true
        syncMOC.performGroupedBlockAndWait {
            self.obfuscationTimer.isTesting = true
        }
    }
    
    override func tearDown() {
        syncMOC.performGroupedBlockAndWait {
            self.syncMOC.zm_teardownMessageObfuscationTimer()
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        uiMOC.performGroupedBlockAndWait {
            self.uiMOC.zm_teardownMessageDeletionTimer()
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    
        super.tearDown()
    }
    
    var obfuscationTimer : ZMMessageDestructionTimer {
        return syncMOC.zm_messageObfuscationTimer
    }
    
    var deletionTimer : ZMMessageDestructionTimer {
        return uiMOC.zm_messageDeletionTimer
    }
}

// MARK: Sending
extension ZMClientMessageTests_Ephemeral {
    
    func testThatItCreateAEphemeralMessageWhenAutoDeleteTimeoutIs_SetToBiggerThanZero_OnConversation(){
        // given
        let timeout : TimeInterval = 10
        conversation.messageDestructionTimeout = timeout
        
        // when
        let message = conversation.appendMessage(withText: "foo") as! ZMClientMessage
        
        // then
        XCTAssertTrue(message.isEphemeral)
        XCTAssertTrue(message.genericMessage!.ephemeral.hasText())
        XCTAssertEqual(message.deletionTimeout, timeout)
    }
    
    func testThatIt_DoesNot_CreateAnEphemeralMessageWhenAutoDeleteTimeoutIs_SetToZero_OnConversation(){
        // given
        conversation.messageDestructionTimeout = 0
        
        // when
        let message = conversation.appendMessage(withText: "foo") as! ZMMessage
        
        // then
        XCTAssertFalse(message.isEphemeral)
    }
    
    func checkItCreatesAnEphemeralMessage(messageCreationBlock: ((ZMConversation) -> ZMMessage)) {
        // given
        let timeout : TimeInterval = 10
        conversation.messageDestructionTimeout = timeout
        
        // when
        let message = conversation.appendMessage(withText: "foo") as! ZMMessage
        
        // then
        XCTAssertTrue(message.isEphemeral)
        XCTAssertEqual(message.deletionTimeout, timeout)
    }
    
    func testItCreatesAnEphemeralMessageForKnock(){
        checkItCreatesAnEphemeralMessage { (conv) -> ZMMessage in
            let message = conv.appendKnock() as! ZMClientMessage
            XCTAssertTrue(message.genericMessage!.ephemeral.hasKnock())
            return message
        }
    }
    
    func testItCreatesAnEphemeralMessageForLocation(){
        checkItCreatesAnEphemeralMessage { (conv) -> ZMMessage in
            let location = LocationData(latitude: 1.0, longitude: 1.0, name: "foo", zoomLevel: 1)
            let message = conv.appendOTRMessage(with: location, nonce: UUID.create())!
            XCTAssertTrue(message.genericMessage!.ephemeral.hasLocation())
            return message
        }
    }

    func testItCreatesAnEphemeralMessageForImages(){
        checkItCreatesAnEphemeralMessage { (conv) -> ZMMessage in
            let message = conv.appendMessage(withImageData: verySmallJPEGData()) as! ZMAssetClientMessage
            XCTAssertTrue(message.genericAssetMessage!.ephemeral.hasImage())
            return message
        }
    }
    
    func testThatItStartsATimerWhenTheMessageIsMarkedAsSent() {
        self.syncMOC.performGroupedBlockAndWait {
            // given
            let timeout : TimeInterval = 10
            self.syncConversation.messageDestructionTimeout = timeout
            let message = self.syncConversation.appendMessage(withText: "foo") as! ZMClientMessage
            XCTAssertEqual(self.obfuscationTimer.runningTimersCount, 0)

            // when
            message.markAsSent()
            
            // then
            XCTAssertTrue(message.isEphemeral)
            XCTAssertEqual(message.deletionTimeout, timeout)
            XCTAssertNotNil(message.destructionDate)
            XCTAssertEqual(self.obfuscationTimer.runningTimersCount, 1)
        }
    }
    
    func testThatItDoesNotStartATimerWhenTheMessageHasUnsentLinkPreviewAndIsMarkedAsSent() {
        self.syncMOC.performGroupedBlockAndWait {
            // given
            let timeout : TimeInterval = 10
            self.syncConversation.messageDestructionTimeout = timeout
            
            let article = Article(
                originalURLString: "www.example.com/article/original",
                permamentURLString: "http://www.example.com/article/1",
                offset: 12
            )
            article.title = "title"
            article.summary = "summary"
            let linkPreview = article.protocolBuffer.update(withOtrKey: Data(), sha256: Data())
            let genericMessage = ZMGenericMessage.message(text: "foo", linkPreview: linkPreview, nonce: UUID.create().transportString(), expiresAfter: NSNumber(value: timeout))
            guard let message = self.syncConversation.appendClientMessage(with: genericMessage.data()) else { return XCTFail() }
            message.linkPreviewState = .processed
            XCTAssertEqual(message.linkPreviewState, .processed)
            XCTAssertEqual(self.obfuscationTimer.runningTimersCount, 0)
            
            // when
            message.markAsSent()
            
            // then
            XCTAssertTrue(message.isEphemeral)
            XCTAssertEqual(message.deletionTimeout, timeout)
            XCTAssertNil(message.destructionDate)
            XCTAssertEqual(self.obfuscationTimer.runningTimersCount, 0)
            
            // and when
            message.linkPreviewState = .done
            message.markAsSent()
            
            // then 
            XCTAssertNotNil(message.destructionDate)
            XCTAssertEqual(self.obfuscationTimer.runningTimersCount, 1)
        }
    }
    
    func testThatItClearsTheMessageContentWhenTheTimerFiresAndSetsIsObfuscatedToTrue(){
        var message : ZMClientMessage!
        
        self.syncMOC.performGroupedBlockAndWait {
            // given
            let timeout : TimeInterval = 0.1
            self.syncConversation.messageDestructionTimeout = timeout
            message = self.syncConversation.appendMessage(withText: "foo") as! ZMClientMessage
            
            // when
            message.markAsSent()
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        spinMainQueue(withTimeout: 0.5)
        
        self.syncMOC.performGroupedBlock {
            // then
            XCTAssertTrue(message.isEphemeral)
            XCTAssertNil(message.destructionDate)
            XCTAssertTrue(message.isObfuscated)
            XCTAssertNotNil(message.sender)
            XCTAssertNotEqual(message.hiddenInConversation, self.syncConversation)
            XCTAssertEqual(message.visibleInConversation, self.syncConversation)
            XCTAssertNotNil(message.genericMessage)
            XCTAssertNotEqual(message.genericMessage?.textData?.content, "foo")
            XCTAssertEqual(self.obfuscationTimer.runningTimersCount, 0)
        }
    }
    
    
    func testThatItDoesNotStartTheTimerWhenTheMessageExpires(){
        self.syncMOC.performGroupedBlockAndWait {
            // given
            let timeout : TimeInterval = 0.1
            self.syncConversation.messageDestructionTimeout = timeout
            let message = self.syncConversation.appendMessage(withText: "foo") as! ZMClientMessage
            
            // when
            message.expire()
            self.spinMainQueue(withTimeout: 0.5)

            // then
            XCTAssertEqual(self.obfuscationTimer.runningTimersCount, 0)
        }
    }
    
    func testThatItDeletesTheEphemeralMessageWhenItReceivesADeleteForItFromOtherUser(){
        var message : ZMClientMessage!

        self.syncMOC.performGroupedBlockAndWait {
            // given
            let timeout : TimeInterval = 0.1
            self.syncConversation.messageDestructionTimeout = timeout
            message = self.syncConversation.appendMessage(withText: "foo") as! ZMClientMessage
            message.markAsSent()
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        spinMainQueue(withTimeout: 0.5)
        
        self.syncMOC.performGroupedBlockAndWait {
            XCTAssertTrue(message.isObfuscated)
            XCTAssertNil(message.destructionDate)

            // when
            let delete = ZMGenericMessage(deleteMessage: message.nonce.transportString(), nonce: UUID.create().transportString())
            let event = self.createUpdateEvent(UUID.create(), conversationID: self.syncConversation.remoteIdentifier!, genericMessage: delete, senderID: self.syncUser1.remoteIdentifier!, eventSource: .download)
            _ = ZMOTRMessage.messageUpdateResult(from: event, in: self.syncMOC, prefetchResult: nil)
            
            // then
            XCTAssertNil(message.sender)
            XCTAssertNil(message.genericMessage)
        }
    }
    
    func testThatItDeletesTheEphemeralMessageWhenItReceivesADeleteFromSelfUser(){
        var message : ZMClientMessage!
        
        self.syncMOC.performGroupedBlockAndWait {
            // given
            let timeout : TimeInterval = 10
            self.syncConversation.messageDestructionTimeout = timeout
            message = self.syncConversation.appendMessage(withText: "foo") as! ZMClientMessage
            message.sender = self.syncUser1
            message.markAsSent()
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        self.syncMOC.performGroupedBlockAndWait {
            // when
            let delete = ZMGenericMessage(deleteMessage: message.nonce.transportString(), nonce: UUID.create().transportString())
            let event = self.createUpdateEvent(UUID.create(), conversationID: self.syncConversation.remoteIdentifier!, genericMessage: delete, senderID: self.selfUser.remoteIdentifier!, eventSource: .download)
            _ = ZMOTRMessage.messageUpdateResult(from: event, in: self.syncMOC, prefetchResult: nil)
            
            // then
            XCTAssertNil(message.sender)
            XCTAssertNil(message.genericMessage)
        }
    }
    
    func testThatItCreatesPayloadForEphemeralMessage() {
        syncMOC.performGroupedBlockAndWait {
            //given
            let conversation = ZMConversation.insertNewObject(in: self.syncMOC)
            conversation.conversationType = .oneOnOne
            conversation.remoteIdentifier = UUID.create()
            conversation.messageDestructionTimeout = 10
            
            let connection = ZMConnection.insertNewObject(in: self.syncMOC)
            connection.to = self.syncUser1
            connection.status = .accepted
            conversation.connection = connection
            conversation.mutableOtherActiveParticipants.add(self.syncUser1)
            self.syncMOC.saveOrRollback()
            
            guard let textMessage = conversation.appendOTRMessage(withText: "foo", nonce: UUID.create(), fetchLinkPreview: true) else { return XCTFail() }
            
            //when
            guard let _ = textMessage.encryptedMessagePayloadData()
                else { return XCTFail()}
        }
    }
}


// MARK: Receiving
extension ZMClientMessageTests_Ephemeral {

    func testThatItStartsATimerIfTheMessageIsAMessageOfTheOtherUser(){
        // given
        conversation.messageDestructionTimeout = 10
        conversation.lastReadServerTimeStamp = Date()
        let sender = ZMUser.insertNewObject(in: uiMOC)
        sender.remoteIdentifier = UUID.create()
        
        let message = conversation.appendMessage(withText: "foo") as! ZMClientMessage
        message.sender = sender
        
        // when
        XCTAssertTrue(message.startSelfDestructionIfNeeded())
        
        // then
        XCTAssertEqual(self.deletionTimer.runningTimersCount, 1)
        XCTAssertTrue(self.deletionTimer.isTimerRunning(for: message))
    }
    
    
    func testThatItDoesNotStartATimerForAMessageOfTheSelfuser(){
        // given
        let timeout : TimeInterval = 0.1
        conversation.messageDestructionTimeout = timeout
        let message = conversation.appendMessage(withText: "foo") as! ZMClientMessage
        
        // when
        XCTAssertFalse(message.startDestructionIfNeeded())
        
        // then
        XCTAssertEqual(self.deletionTimer.runningTimersCount, 0)
    }
    
    func testThatItCreatesADeleteForAllMessageWhenTheTimerFires(){
        // given
        let timeout : TimeInterval = 0.1
        conversation.messageDestructionTimeout = timeout
        conversation.conversationType = .oneOnOne
        let message = conversation.appendMessage(withText: "foo") as! ZMClientMessage
        message.sender = ZMUser.insertNewObject(in: uiMOC)
        message.sender?.remoteIdentifier = UUID.create()

        // when
        XCTAssertTrue(message.startDestructionIfNeeded())
        XCTAssertEqual(self.deletionTimer.runningTimersCount, 1)
        
        spinMainQueue(withTimeout: 0.5)
        
        // then
        guard let deleteMessage = conversation.hiddenMessages.firstObject as? ZMClientMessage
        else { return XCTFail()}

        guard let genericMessage = deleteMessage.genericMessage, genericMessage.hasDeleted()
        else {return XCTFail()}

        XCTAssertNotEqual(deleteMessage, message)
        XCTAssertNotNil(message.sender)
        XCTAssertNil(message.genericMessage)
        XCTAssertNil(message.destructionDate)
    }
    
}


extension ZMClientMessageTests_Ephemeral {

    
    func hasDeleteMessage(for message: ZMMessage) -> Bool {
        guard let deleteMessage = (conversation.hiddenMessages.firstObject as? ZMClientMessage)?.genericMessage,
            deleteMessage.hasDeleted(), deleteMessage.deleted.messageId == message.nonce.transportString()
            else { return false }
        return true
    }
    
    func insertEphemeralMessage() -> ZMMessage {
        let timeout : TimeInterval = 1.0
        conversation.messageDestructionTimeout = timeout
        let message = conversation.appendMessage(withText: "foo") as! ZMClientMessage
        message.sender = ZMUser.insertNewObject(in: uiMOC)
        message.sender?.remoteIdentifier = UUID.create()
        uiMOC.saveOrRollback()
        return message
    }
    

    func testThatItRestartsTheTimerWhenTimerHadStartedAndDestructionDateIsInFuture() {
        // given
        let message = insertEphemeralMessage()
        
        // when
        // start timer
        XCTAssertTrue(message.startDestructionIfNeeded())
        XCTAssertNotNil(message.destructionDate)
        
        // stop app (timer stops)
        deletionTimer.stop(for: message)
        XCTAssertNotNil(message.sender)
        
        // restart app
        ZMMessage.deleteOldEphemeralMessages(self.uiMOC)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(conversation.hiddenMessages.count, 0)
        XCTAssertTrue(deletionTimer.isTimerRunning(for: message))
    }

    func testThatItDeletesMessagesFromOtherUserWhenTimerHadStartedAndDestructionDateIsInPast() {
        // given
        conversation.conversationType = .oneOnOne
        let message = insertEphemeralMessage()
        
        // when
        // start timer
        XCTAssertTrue(message.startDestructionIfNeeded())
        XCTAssertNotNil(message.destructionDate)
        
        // stop app (timer stops)
        deletionTimer.stop(for: message)
        XCTAssertNotNil(message.sender)
        // wait for destruction date to be passed
        spinMainQueue(withTimeout: 1.0)
        XCTAssertNotNil(message.sender)
        
        // restart app
        ZMMessage.deleteOldEphemeralMessages(self.uiMOC)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertTrue(hasDeleteMessage(for: message))
        XCTAssertNotNil(message.sender)
        XCTAssertEqual(message.hiddenInConversation, conversation)
    }

    func testThatItObfuscatesMessagesSentFromSelfWhenTimerHadStartedAndDestructionDateIsInPast() {
        // given
        var message: ZMClientMessage!

        syncMOC.performGroupedBlock { 
            self.syncConversation.messageDestructionTimeout = 0.5
            message = self.syncConversation.appendMessage(withText: "foo") as! ZMClientMessage
            message.markAsSent()
            XCTAssertNotNil(message.destructionDate)
        }

        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // Stop app (timer stops)
        deletionTimer.stop(for: message)

        // wait for destruction date to be passed
        spinMainQueue(withTimeout: 1.0)

            // restart app
        ZMMessage.deleteOldEphemeralMessages(uiMOC)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // then
        syncMOC.performGroupedBlock { 
            XCTAssertTrue(message.isObfuscated)
            XCTAssertNotNil(message.sender)
            XCTAssertNil(message.hiddenInConversation)
            XCTAssertEqual(message.visibleInConversation, self.syncConversation)
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }

    func testThatItDoesNotDeleteMessagesFromOtherUserWhenTimerHad_Not_Started(){
        // given
        let message = insertEphemeralMessage()
        
        // when
        ZMMessage.deleteOldEphemeralMessages(self.uiMOC)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(conversation.hiddenMessages.count, 0)
        XCTAssertFalse(deletionTimer.isTimerRunning(for: message))
    }
    
    func obfuscatedMessagesByTheSelfUser(timerHadStarted: Bool) -> Bool {
        var isObfuscated = false
        self.syncMOC.performGroupedBlockAndWait {
            // given
            let timeout : TimeInterval = 10
            self.syncConversation.messageDestructionTimeout = timeout
            let message = self.syncConversation.appendMessage(withText: "foo") as! ZMClientMessage
            
            if timerHadStarted {
                message.markAsSent()
                XCTAssertNotNil(message.destructionDate)
            }
            
            // when
            ZMMessage.deleteOldEphemeralMessages(self.syncMOC)
            isObfuscated = message.isObfuscated
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        return isObfuscated;
    }
    
    func testThatItDoesNotObfuscateTheMessageWhenTheTimerWasStartedAndIsSentBySelf() {
        XCTAssertFalse(obfuscatedMessagesByTheSelfUser(timerHadStarted: true))
    }
    
    func testThatItDoesNotObfuscateTheMessageWhenTheTimerWas_Not_Started() {
        XCTAssertFalse(obfuscatedMessagesByTheSelfUser(timerHadStarted: false))
    }
    
}


