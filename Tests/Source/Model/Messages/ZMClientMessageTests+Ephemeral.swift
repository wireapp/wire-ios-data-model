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
        conversation.messageDestructionTimeout = .local(MessageDestructionTimeoutValue(rawValue: timeout))
        
        // when
        let message = conversation.append(text: "foo") as! ZMClientMessage
        
        // then
        XCTAssertTrue(message.isEphemeral)
        XCTAssertTrue(message.genericMessage!.ephemeral.hasText())
        XCTAssertEqual(message.deletionTimeout, timeout)
    }
    
    func testThatIt_DoesNot_CreateAnEphemeralMessageWhenAutoDeleteTimeoutIs_SetToZero_OnConversation(){
        // given
        conversation.messageDestructionTimeout = .local(MessageDestructionTimeoutValue(rawValue: 0))
        
        // when
        let message = conversation.append(text: "foo") as! ZMMessage
        
        // then
        XCTAssertFalse(message.isEphemeral)
    }
    
    func checkItCreatesAnEphemeralMessage(messageCreationBlock: ((ZMConversation) -> ZMMessage)) {
        // given
        let timeout : TimeInterval = 10
        conversation.messageDestructionTimeout = .local(MessageDestructionTimeoutValue(rawValue: timeout))
        
        // when
        let message = conversation.append(text: "foo") as! ZMMessage
        
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
            let message = conv.append(location: location, nonce: UUID.create()) as? ZMClientMessage
            XCTAssertTrue((message?.genericMessage!.ephemeral.hasLocation())!)
            return message!
        }
    }

    func testItCreatesAnEphemeralMessageForImages(){
        checkItCreatesAnEphemeralMessage { (conv) -> ZMMessage in
            let message = conv.append(imageFromData: verySmallJPEGData()) as! ZMAssetClientMessage
            XCTAssertTrue(message.genericAssetMessage!.ephemeral.hasImage())
            return message
        }
    }
    
    func testThatItStartsATimerWhenTheMessageIsMarkedAsSent() {
        self.syncMOC.performGroupedBlockAndWait {
            // given
            let timeout : TimeInterval = 10
            self.syncConversation.messageDestructionTimeout = .local(MessageDestructionTimeoutValue(rawValue: timeout))
            let message = self.syncConversation.append(text: "foo") as! ZMClientMessage
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
    
    func testThatItStartsATimerWhenTheMessageIsMarkedAsSent_IncomingFromOtherDevice() {
        self.syncMOC.performGroupedBlockAndWait {
            // given
            self.syncConversation.messageDestructionTimeout = .local(MessageDestructionTimeoutValue(rawValue: 10))
            self.syncConversation.lastReadServerTimeStamp = Date()
            
            let nonce = UUID()
            let message = ZMAssetClientMessage(nonce: nonce, managedObjectContext: self.syncMOC)
            message.sender = ZMUser.selfUser(in: self.syncMOC)
            message.visibleInConversation = self.syncConversation
            message.senderClientID = "other_client"
            
            let imageData = self.verySmallJPEGData()
            let assetMessage = ZMGenericMessage.message(content: ZMAsset.asset(originalWithImageSize: .zero, mimeType: "", size: UInt64(imageData.count)), nonce: nonce, expiresAfter: 10)
            message.add(assetMessage)
            
            let uploaded = ZMGenericMessage.message(content: ZMAsset.asset(withUploadedOTRKey: .randomEncryptionKey(), sha256: .zmRandomSHA256Key()), nonce: message.nonce!, expiresAfter: self.syncConversation.messageDestructionTimeoutValue)
            message.add(uploaded)
            message.setImageData(imageData, for: .medium, properties: nil)
            
            // when
            message.markAsSent()
            
            // then
            XCTAssertTrue(message.isEphemeral)
            XCTAssertEqual(message.deletionTimeout, 10)
            XCTAssertNotNil(message.destructionDate)
            XCTAssertEqual(self.obfuscationTimer.runningTimersCount, 1)
        }
    }
    
    func testThatItDoesNotStartATimerWhenTheMessageHasUnsentLinkPreviewAndIsMarkedAsSent() {
        self.syncMOC.performGroupedBlockAndWait {
            // given
            let timeout : TimeInterval = 10
            self.syncConversation.messageDestructionTimeout = .local(MessageDestructionTimeoutValue(rawValue: timeout))
            
            let article = Article(
                originalURLString: "www.example.com/article/original",
                permanentURLString: "http://www.example.com/article/1",
                resolvedURLString: "http://www.example.com/article/1",
                offset: 12
            )
            article.title = "title"
            article.summary = "summary"
            let linkPreview = article.protocolBuffer.update(withOtrKey: Data(), sha256: Data())
            let genericMessage = ZMGenericMessage.message(content: ZMText.text(with: "foo", linkPreviews: [linkPreview]), nonce: UUID.create(), expiresAfter: timeout)
            let message = self.syncConversation.appendClientMessage(with: genericMessage)!
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
    
    func testThatItClearsTheMessageContentWhenTheTimerFiresAndSetsIsObfuscatedToTrue() {
        var message : ZMClientMessage!
        
        self.syncMOC.performGroupedBlockAndWait {
            // given
            let timeout : TimeInterval = 0.1
            self.syncConversation.messageDestructionTimeout = .local(MessageDestructionTimeoutValue(rawValue: timeout))
            message = self.syncConversation.append(text: "foo") as? ZMClientMessage
            
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
    
    
    func testThatItDoesNotStartTheTimerWhenTheMessageExpires() {
        self.syncMOC.performGroupedBlockAndWait {
            // given
            let timeout : TimeInterval = 0.1
            self.syncConversation.messageDestructionTimeout = .local(MessageDestructionTimeoutValue(rawValue: timeout))
            let message = self.syncConversation.append(text: "foo") as! ZMClientMessage
            
            // when
            message.expire()
            self.spinMainQueue(withTimeout: 0.5)

            // then
            XCTAssertEqual(self.obfuscationTimer.runningTimersCount, 0)
        }
    }
    
    func testThatItDeletesTheEphemeralMessageWhenItReceivesADeleteForItFromOtherUser() {
        var message : ZMClientMessage!

        self.syncMOC.performGroupedBlockAndWait {
            // given
            let timeout : TimeInterval = 0.1
            self.syncConversation.messageDestructionTimeout = .local(MessageDestructionTimeoutValue(rawValue: timeout))
            message = self.syncConversation.append(text: "foo") as? ZMClientMessage
            message.markAsSent()
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        spinMainQueue(withTimeout: 0.5)
        
        self.syncMOC.performGroupedBlockAndWait {
            XCTAssertTrue(message.isObfuscated)
            XCTAssertNil(message.destructionDate)

            // when
            let delete = ZMGenericMessage.message(content: ZMMessageDelete.delete(messageId: message.nonce!), nonce: UUID.create())
            let event = self.createUpdateEvent(UUID.create(), conversationID: self.syncConversation.remoteIdentifier!, genericMessage: delete, senderID: self.syncUser1.remoteIdentifier!, eventSource: .download)
            _ = ZMOTRMessage.messageUpdateResult(from: event, in: self.syncMOC, prefetchResult: nil)
            
            // then
            XCTAssertNil(message.sender)
            XCTAssertNil(message.genericMessage)
        }
    }
    
    func testThatItDeletesTheEphemeralMessageWhenItReceivesADeleteFromSelfUser() {
        var message : ZMClientMessage!
        
        self.syncMOC.performGroupedBlockAndWait {
            // given
            let timeout : TimeInterval = 10
            self.syncConversation.messageDestructionTimeout = .local(MessageDestructionTimeoutValue(rawValue: timeout))
            message = self.syncConversation.append(text: "foo") as? ZMClientMessage
            message.sender = self.syncUser1
            message.markAsSent()
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        self.syncMOC.performGroupedBlockAndWait {
            // when
            let delete = ZMGenericMessage.message(content: ZMMessageDelete.delete(messageId: message.nonce!), nonce: UUID.create())
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
            conversation.messageDestructionTimeout = .local(MessageDestructionTimeoutValue(rawValue: 10))
            
            let connection = ZMConnection.insertNewObject(in: self.syncMOC)
            connection.to = self.syncUser1
            connection.status = .accepted
            conversation.connection = connection
            conversation.mutableLastServerSyncedActiveParticipants.add(self.syncUser1)
            self.syncMOC.saveOrRollback()
            
            let textMessage = conversation.append(text: "foo", fetchLinkPreview: true, nonce: UUID.create()) as! ZMClientMessage
            
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
        conversation.messageDestructionTimeout = .local(MessageDestructionTimeoutValue(rawValue: 10))
        conversation.lastReadServerTimeStamp = Date()
        let sender = ZMUser.insertNewObject(in: uiMOC)
        sender.remoteIdentifier = UUID.create()
        
        let message = conversation.append(text: "foo") as! ZMClientMessage
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
        conversation.messageDestructionTimeout = .local(MessageDestructionTimeoutValue(rawValue: timeout))
        let message = conversation.append(text: "foo") as! ZMClientMessage
        
        // when
        XCTAssertFalse(message.startDestructionIfNeeded())
        
        // then
        XCTAssertEqual(self.deletionTimer.runningTimersCount, 0)
    }
    
    func testThatItCreatesADeleteForAllMessageWhenTheTimerFires(){
        // given
        let timeout : TimeInterval = 0.1
        conversation.messageDestructionTimeout = .local(MessageDestructionTimeoutValue(rawValue: timeout))
        conversation.conversationType = .oneOnOne
        let message = conversation.append(text: "foo") as! ZMClientMessage
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
            deleteMessage.hasDeleted(), deleteMessage.deleted.messageId == message.nonce!.transportString()
            else { return false }
        return true
    }
    
    func insertEphemeralMessage() -> ZMMessage {
        let timeout : TimeInterval = 1.0
        conversation.messageDestructionTimeout = .local(MessageDestructionTimeoutValue(rawValue: timeout))
        let message = conversation.append(text: "foo") as! ZMClientMessage
        message.sender = ZMUser.insertNewObject(in: uiMOC)
        message.sender?.remoteIdentifier = UUID.create()
        uiMOC.saveOrRollback()
        return message
    }
    

    func testThatItRestartsTheDeletionTimerWhenTimerHadStartedAndDestructionDateIsInFuture() {
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
    
    func testThatItRestartsTheObfuscationTimerWhenTimerHadStartedAndDestructionDateIsInFuture() {
        // given
        var message: ZMClientMessage!
        
        syncMOC.performGroupedBlock {
            self.syncConversation.messageDestructionTimeout = .local(MessageDestructionTimeoutValue(rawValue: 5.0))
            message = self.syncConversation.append(text: "foo") as? ZMClientMessage
            
            // when
            // start timer
            XCTAssertTrue(message.startDestructionIfNeeded())
            XCTAssertNotNil(message.destructionDate)
    
            // stop app (timer stops)
            self.obfuscationTimer.stop(for: message)
            XCTAssertNotNil(message.sender)
            
            // restart app
            ZMMessage.deleteOldEphemeralMessages(self.syncMOC)
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        syncMOC.performGroupedBlock {
            // then
            XCTAssertEqual(self.syncConversation.hiddenMessages.count, 0)
            XCTAssertTrue(self.obfuscationTimer.isTimerRunning(for: message))
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
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
            self.syncConversation.messageDestructionTimeout = .local(MessageDestructionTimeoutValue(rawValue: 0.5))
            message = self.syncConversation.append(text: "foo") as? ZMClientMessage
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
            self.syncConversation.messageDestructionTimeout = .local(MessageDestructionTimeoutValue(rawValue: timeout))
            let message = self.syncConversation.append(text: "foo") as! ZMClientMessage
            
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


