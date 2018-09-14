//
// Wire
// Copyright (C) 2018 Wire Swiss GmbH
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

class ZMConversationTests_Timestamps: ZMConversationTestsBase {
    
    // MARK: - Unread Count
    
    func testThatLastUnreadKnockDateIsSetWhenMessageInserted() {
        syncMOC.performGroupedBlockAndWait {
            // given
            let timestamp = Date()
            let conversation = ZMConversation.insertNewObject(in: self.syncMOC)
            let knock = ZMGenericMessage.message(content: ZMKnock.knock())
            let message = ZMClientMessage(nonce: UUID(), managedObjectContext: self.syncMOC)
            message.add(knock.data())
            message.serverTimestamp = timestamp
            message.visibleInConversation = conversation
            
            // when
            conversation.updateTimestampsAfterInsertingMessage(message)
            
            // then
            XCTAssertEqual(conversation.lastUnreadKnockDate, timestamp)
            XCTAssertEqual(conversation.estimatedUnreadCount, 1)
        }
    }
    
    func testThatLastUnreadMissedCallDateIsSetWhenMessageInserted() {
        syncMOC.performGroupedBlockAndWait {
            // given
            let timestamp = Date()
            let conversation = ZMConversation.insertNewObject(in: self.syncMOC)
            let message = ZMSystemMessage(nonce: UUID(), managedObjectContext: self.syncMOC)
            message.systemMessageType = .missedCall
            message.serverTimestamp = timestamp
            message.visibleInConversation = conversation
            
            // when
            conversation.updateTimestampsAfterInsertingMessage(message)
            
            // then
            XCTAssertEqual(conversation.lastUnreadMissedCallDate, timestamp)
            XCTAssertEqual(conversation.estimatedUnreadCount, 1)
        }
    }
    
    func testThatUnreadCountIsUpdatedWhenMessageIsInserted() {
        syncMOC.performGroupedBlockAndWait {
            // given
            let timestamp = Date()
            let conversation = ZMConversation.insertNewObject(in: self.syncMOC)
            let message = ZMClientMessage(nonce: UUID(), managedObjectContext: self.syncMOC)
            message.serverTimestamp = timestamp
            message.visibleInConversation = conversation
            
            // when
            conversation.updateTimestampsAfterInsertingMessage(message)
            
            // then
            XCTAssertEqual(conversation.estimatedUnreadCount, 1)
        }
    }
    
    func testThatUnreadCountIsUpdatedWhenMessageIsDeleted() {
        syncMOC.performGroupedBlockAndWait {
            // given
            let timestamp = Date()
            let conversation = ZMConversation.insertNewObject(in: self.syncMOC)
            let message = ZMClientMessage(nonce: UUID(), managedObjectContext: self.syncMOC)
            message.serverTimestamp = timestamp
            message.visibleInConversation = conversation
            conversation.updateTimestampsAfterInsertingMessage(message)
            XCTAssertEqual(conversation.estimatedUnreadCount, 1)
            
            // when
            message.visibleInConversation = nil
            conversation.updateTimestampsAfterDeletingMessage()
            
            // then
            XCTAssertEqual(conversation.estimatedUnreadCount, 0)
        }
    }
    
    // MARK: - Cleared Date
    
    func testThatClearedTimestampIsUpdated() {
        let timestamp = Date()
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        
        // when
        conversation.updateCleared(timestamp)
        
        // then
        XCTAssertEqual(conversation.clearedTimeStamp, timestamp)
    }
    
    func testThatClearedTimestampIsNotUpdatedToAnOlderTimestamp() {
        
        let timestamp = Date()
        let olderTimestamp = timestamp.addingTimeInterval(-100)
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        conversation.clearedTimeStamp = timestamp
        
        // when
        conversation.updateCleared(olderTimestamp)
        
        // then
        XCTAssertEqual(conversation.clearedTimeStamp, timestamp)
    }
    
    // MARK: - Modified Date
    
    func testThatModifiedDateIsUpdatedWhenMessageInserted() {
        // given
        let timestamp = Date()
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        let message = ZMClientMessage(nonce: UUID(), managedObjectContext: uiMOC)
        message.serverTimestamp = timestamp
        
        // when
        conversation.updateTimestampsAfterInsertingMessage(message)
        
        // then
        XCTAssertEqual(conversation.lastModifiedDate, timestamp)
    }
    
    func testThatModifiedDateIsNotUpdatedWhenMessageWhichShouldNotUpdateModifiedDateIsInserted() {
        // given
        let timestamp = Date()
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        let message = ZMSystemMessage(nonce: UUID(), managedObjectContext: uiMOC)
        message.systemMessageType = .participantsRemoved
        message.serverTimestamp = timestamp
        
        // when
        conversation.updateTimestampsAfterInsertingMessage(message)
        
        // then
        XCTAssertNil(conversation.lastModifiedDate)
    }
        
    // MARK: - Last Read Date
    
    func testThatLastReadDateIsNotUpdatedWhenMessageFromSelfUserInserted() {
        // given
        let timestamp = Date()
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        let message = ZMClientMessage(nonce: UUID(), managedObjectContext: uiMOC)
        message.serverTimestamp = timestamp
        message.sender = selfUser
        
        // when
        conversation.updateTimestampsAfterInsertingMessage(message)
        
        // then
        XCTAssertNil(conversation.lastReadServerTimeStamp)
    }
    
    func testThatLastReadDateIsNotUpdatedWhenMessageFromOtherUserInserted() {
        // given
        let otherUser = createUser()
        let timestamp = Date()
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        let message = ZMClientMessage(nonce: UUID(), managedObjectContext: uiMOC)
        message.serverTimestamp = timestamp
        message.sender = otherUser
        
        // when
        conversation.updateTimestampsAfterInsertingMessage(message)
        
        // then
        XCTAssertNil(conversation.lastReadServerTimeStamp)
    }
    
    func testThatItSendsANotificationWhenSettingTheLastRead() {
        // given
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        
        // expect
        expectation(forNotification: ZMConversation.lastReadDidChangeNotificationName, object: nil) { (note) -> Bool in
            return true
        }
        
        // when
        conversation.updateLastRead(Date())
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
    }
    
    // MARK: - First Unread Message
    
    func testThatItReturnsTheFirstUnreadMessageIfWeHaveItLocally() {
        // given
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        
        // when
        let message = ZMClientMessage(nonce: UUID(), managedObjectContext: uiMOC)
        message.visibleInConversation = conversation
        
        // then
        XCTAssertEqual(conversation.firstUnreadMessage as? ZMClientMessage, message)
    }
    
    func testThatItReturnsNilIfTheLastReadServerTimestampIsMoreRecent() {
        // given
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        let message = ZMClientMessage(nonce: UUID(), managedObjectContext: uiMOC)
        message.visibleInConversation = conversation
        
        // when
        conversation.lastReadServerTimeStamp = message.serverTimestamp
        
        // then
        XCTAssertNil(conversation.firstUnreadMessage)
    }
    
    func testThatItSkipsMessagesWhichDoesntGenerateUnreadDotsDirectlyBeforeFirstUnreadMessage() {
        // given
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        
        // when
        let messageWhichDoesntGenerateUnreadDot = ZMSystemMessage(nonce: UUID(), managedObjectContext: uiMOC)
        messageWhichDoesntGenerateUnreadDot.systemMessageType = .participantsAdded
        messageWhichDoesntGenerateUnreadDot.visibleInConversation = conversation
        
        let message = ZMClientMessage(nonce: UUID(), managedObjectContext: uiMOC)
        message.visibleInConversation = conversation
        
        // then
        XCTAssertEqual(conversation.firstUnreadMessage as? ZMClientMessage, message)
    }
    
    func testThatTheParentMessageIsReturnedIfItHasUnreadChildMessages() {
        // given
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        
        let systemMessage1 = ZMSystemMessage(nonce: UUID(), managedObjectContext: uiMOC)
        systemMessage1.systemMessageType = .missedCall
        systemMessage1.visibleInConversation = conversation
        conversation.lastReadServerTimeStamp = systemMessage1.serverTimestamp
        
        // when
        let systemMessage2 = ZMSystemMessage(nonce: UUID(), managedObjectContext: uiMOC)
        systemMessage2.systemMessageType = .missedCall
        systemMessage2.hiddenInConversation = conversation
        systemMessage2.parentMessage = systemMessage1
        
        // then
        XCTAssertEqual(conversation.firstUnreadMessage as? ZMSystemMessage, systemMessage1)
    }
    
    func testThatTheParentMessageIsNotReturnedIfAllChildMessagesAreRead() {
        // given
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        
        let systemMessage1 = ZMSystemMessage(nonce: UUID(), managedObjectContext: uiMOC)
        systemMessage1.systemMessageType = .missedCall
        systemMessage1.visibleInConversation = conversation
        
        let systemMessage2 = ZMSystemMessage(nonce: UUID(), managedObjectContext: uiMOC)
        systemMessage2.systemMessageType = .missedCall
        systemMessage2.hiddenInConversation = conversation
        systemMessage2.parentMessage = systemMessage1
        
        // when
        conversation.lastReadServerTimeStamp = systemMessage2.serverTimestamp
        
        // then
        XCTAssertNil(conversation.firstUnreadMessage)
    }
    
    // MARK: - Relevant Messages
    
    func testThatNotRelevantMessagesDoesntCountTowardsUnreadMessagesAmount() {
        
        syncMOC.performGroupedBlockAndWait {

            // given
            let conversation = ZMConversation.insertNewObject(in: self.syncMOC)
            
            let systemMessage1 = ZMSystemMessage(nonce: UUID(), managedObjectContext: self.syncMOC)
            systemMessage1.systemMessageType = .missedCall
            systemMessage1.visibleInConversation = conversation
            
            let systemMessage2 = ZMSystemMessage(nonce: UUID(), managedObjectContext: self.syncMOC)
            systemMessage2.systemMessageType = .missedCall
            systemMessage2.visibleInConversation = conversation
            systemMessage2.relevantForConversationStatus = false
            
            let textMessage = ZMTextMessage(nonce: UUID(), managedObjectContext: self.syncMOC)
            textMessage.text = "Test"
            textMessage.visibleInConversation = conversation
            
            // when
            conversation.updateTimestampsAfterInsertingMessage(textMessage)
            
            // then
            XCTAssertEqual(conversation.unreadMessages.count, 2)
            XCTAssertTrue(conversation.unreadMessages.contains  { $0.nonce == systemMessage1.nonce} )
            XCTAssertFalse(conversation.unreadMessages.contains { $0.nonce == systemMessage2.nonce} )
            XCTAssertTrue(conversation.unreadMessages.contains  { $0.nonce == textMessage.nonce}    )
        }
    }
    
}
