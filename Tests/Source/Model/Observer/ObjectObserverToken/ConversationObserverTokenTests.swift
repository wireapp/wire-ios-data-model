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
import ZMCDataModel

class ConversationObserverTokenTests : ZMBaseManagedObjectTest {
    
    override func setUp() {
        super.setUp()
        XCTAssertNotNil(self.uiMOC.globalManagedObjectContextObserver)
        self.syncMOC.performGroupedBlockAndWait {
            XCTAssertNotNil(self.syncMOC.globalManagedObjectContextObserver)
            self.syncMOC.globalManagedObjectContextObserver.propagateChanges = true
        }
        NotificationCenter.default.post(name: Notification.Name(rawValue: "ZMApplicationDidEnterEventProcessingStateNotification"), object: nil)
        NotificationCenter.default.post(name: NSNotification.Name.UIApplicationDidBecomeActive, object: nil)

        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    class TestConversationObserver : NSObject, ZMConversationObserver {
        
        var receivedChangeInfo : [ConversationChangeInfo] = []
        
        func conversationDidChange(_ changes: ConversationChangeInfo) {
            receivedChangeInfo.append(changes)
        }
        func clearNotifications() {
            receivedChangeInfo = []
        }
    }
    
    func checkThatItNotifiesTheObserverOfAChange(_ conversation : ZMConversation,
        modifier: (ZMConversation, TestConversationObserver) -> Void,
        expectedChangedField : String?,
        expectedChangedKeys: KeySet) {
            
            self.checkThatItNotifiesTheObserverOfAChange(conversation,
                modifier: modifier,
                expectedChangedFields: expectedChangedField != nil ? KeySet(key: expectedChangedField!) : KeySet(),
                expectedChangedKeys: expectedChangedKeys)
    }
    
    func checkThatItNotifiesTheObserverOfAChange(_ conversation : ZMConversation,
        modifier: (ZMConversation, TestConversationObserver) -> Void,
        expectedChangedFields : KeySet,
        expectedChangedKeys: KeySet) {
            
        // given
        let observer = TestConversationObserver()
        let token = conversation.add(observer)

        // when
        modifier(conversation, observer)
        conversation.managedObjectContext!.saveOrRollback()
            
        // then
        let changeCount = observer.receivedChangeInfo.count
        if !expectedChangedFields.isEmpty {
            XCTAssertEqual(changeCount, 1, "Observer expected 1 notification, but received \(changeCount).")
        } else {
            XCTAssertEqual(changeCount, 0, "Observer was notified, but DID NOT expect a notification")
        }
        
        // and when
        self.uiMOC.saveOrRollback()
        
        // then
        XCTAssertEqual(observer.receivedChangeInfo.count, changeCount, "Should have changed only once")
        
        let conversationInfoKeys = [
            "messagesChanged",
            "participantsChanged",
            "nameChanged",
            "lastModifiedDateChanged",
            "unreadCountChanged",
            "connectionStateChanged",
            "isArchivedChanged",
            "isSilencedChanged",
            "conversationListIndicatorChanged"
        ]
        
        if expectedChangedFields.isEmpty {
            return
        }
        
        if let changes = observer.receivedChangeInfo.first {
            for key in conversationInfoKeys {
                if expectedChangedFields.contains(key) {
                    continue
                }
                if let value = changes.value(forKey: key) as? NSNumber {
                    XCTAssertFalse(value.boolValue, "\(key) was supposed to be false")
                }
                else {
                    XCTFail("Can't find key or key is not boolean for '\(key)'")
                }
            }
            XCTAssertEqual(KeySet(Array(changes.changedKeysAndOldValues.keys)), expectedChangedKeys)
        }
        
        ZMConversation.removeObserver(for: token)
    }
    
    
    func testThatItNotifiesTheObserverOfANameChange()
    {
        // given
        let conversation = ZMConversation.insertNewObject(in:self.uiMOC)
        conversation.conversationType = ZMConversationType.group
        conversation.userDefinedName = "George"
        
        
        // when
        self.checkThatItNotifiesTheObserverOfAChange(conversation,
            modifier: { conversation, _ in conversation.userDefinedName = "Phil"},
            expectedChangedField: "nameChanged",
            expectedChangedKeys: KeySet(["displayName"])
        )
        
    }
    
    func notifyNameChange(_ user: ZMUser, name: String) {
        user.name = name
        self.uiMOC.saveOrRollback()
    }

    func testThatItNotifiesTheObserverIfTheVoiceChannelStateChanges()
    {
        // given
        let conversation = ZMConversation.insertNewObject(in:self.uiMOC)
        conversation.conversationType = ZMConversationType.group
        let otherUser = ZMUser.insertNewObject(in:self.uiMOC)
        otherUser.name = "Foo"
        conversation.mutableOtherActiveParticipants.add(otherUser)
        self.uiMOC.saveOrRollback()
        
        // when
        self.checkThatItNotifiesTheObserverOfAChange(conversation,
            modifier: { _ in
                conversation.callDeviceIsActive = true

                self.uiMOC.globalManagedObjectContextObserver.notifyUpdatedCallState(Set(arrayLiteral:conversation), notifyDirectly:true)
            },
            expectedChangedFields: KeySet(["voiceChannelStateChanged", "conversationListIndicatorChanged"]),
            expectedChangedKeys: KeySet(["voiceChannelState", "conversationListIndicator"])
        )
        
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    func testThatItNotifiesTheObserverOfANameChangeBecauseOfActiveParticipants()
    {
        // given
        let conversation = ZMConversation.insertNewObject(in:self.uiMOC)
        conversation.conversationType = ZMConversationType.group
        let otherUser = ZMUser.insertNewObject(in:self.uiMOC)
        otherUser.name = "Foo"
        conversation.mutableOtherActiveParticipants.add(otherUser)
        self.uiMOC.saveOrRollback()
        
        // when
        self.checkThatItNotifiesTheObserverOfAChange(conversation,
            modifier: { _ in
                self.notifyNameChange(otherUser, name: "Phil")
            },
            expectedChangedField: "nameChanged",
            expectedChangedKeys: KeySet(["displayName"])
        )
        
    }
    
    func testThatItNotifiesTheObserverOfANameChangeBecauseAnActiveParticipantWasAdded()
    {
        // given
        let conversation = ZMConversation.insertNewObject(in:self.uiMOC)
        conversation.conversationType = ZMConversationType.group
        
        self.uiMOC.saveOrRollback()
        
        // when
        self.checkThatItNotifiesTheObserverOfAChange(conversation,
            modifier: { _ in
                
                let otherUser = ZMUser.insertNewObject(in:self.uiMOC)
                otherUser.name = "Foo"
                conversation.mutableOtherActiveParticipants.add(otherUser)
                self.updateDisplayNameGenerator(withUsers: [otherUser])
            },
            expectedChangedFields: KeySet(["nameChanged", "participantsChanged"]),
            expectedChangedKeys: KeySet(["displayName", "otherActiveParticipants"])
        )
        
    }
    
    func testThatItNotifiesTheObserverOfANameChangeBecauseOfActiveParticipantsMultipleTimes()
    {
        // given
        let conversation = ZMConversation.insertNewObject(in:self.uiMOC)
        conversation.conversationType = ZMConversationType.group
        let user = ZMUser.insertNewObject(in:self.uiMOC)
        conversation.mutableOtherActiveParticipants.add(user)
        let observer = TestConversationObserver()
        let token = conversation.add(observer)
        self.uiMOC.saveOrRollback()
        
        // when
        user.name = "Boo"
        self.uiMOC.saveOrRollback()
        
        // then
        XCTAssertEqual(observer.receivedChangeInfo.count, 1)
        
        // and when
        user.name = "Bar"
        self.uiMOC.saveOrRollback()
        
        // then
        XCTAssertEqual(observer.receivedChangeInfo.count, 2)
        
        // and when
        self.uiMOC.saveOrRollback()
        ZMConversation.removeObserver(for: token)
    }
    
    
    func testThatItDoesNotNotifyTheObserverBecauseAUsersAccentColorChanged()
    {
        // given
        let conversation = ZMConversation.insertNewObject(in:self.uiMOC)
        conversation.conversationType = ZMConversationType.group
        let otherUser = ZMUser.insertNewObject(in:self.uiMOC)
        otherUser.accentColorValue = .brightOrange
        conversation.mutableOtherActiveParticipants.add(otherUser)
        self.uiMOC.saveOrRollback()
        
        // when
        self.checkThatItNotifiesTheObserverOfAChange(conversation,
            modifier: { _ in
                otherUser.accentColorValue = ZMAccentColor.softPink
            },
            expectedChangedField: nil,
            expectedChangedKeys: KeySet()
        )
    }
    
    func testThatItNotifiesTheObserverOfANameChangeBecauseOfOtherUserNameChange()
    {
        // given
        let conversation = ZMConversation.insertNewObject(in:self.uiMOC)
        conversation.conversationType = .oneOnOne
        
        let otherUser = ZMUser.insertNewObject(in:self.uiMOC)
        otherUser.name = "Foo"
        
        let connection = ZMConnection.insertNewObject(in: self.uiMOC)
        connection.to = otherUser
        connection.status = .accepted
        conversation.connection = connection
        
        self.uiMOC.saveOrRollback()
        
        // when
        self.checkThatItNotifiesTheObserverOfAChange(conversation,
            modifier: { _ in
                self.notifyNameChange(otherUser, name: "Phil")
            },
            expectedChangedField: "nameChanged",
            expectedChangedKeys: KeySet(["displayName"])
        )
        
    }
    
    func testThatItNotifiesTheObserverOfANameChangeBecauseAUserWasAdded()
    {
        // given
        let user1 = ZMUser.insertNewObject(in:self.uiMOC)
        user1.name = "Foo A"
        
        let conversation = ZMConversation.insertNewObject(in:self.uiMOC)
        conversation.conversationType = ZMConversationType.group
        conversation.mutableOtherActiveParticipants.add(user1)
        
        self.uiMOC.saveOrRollback()
        
        XCTAssertTrue(user1.displayName == "Foo")
        
        // when
        self.checkThatItNotifiesTheObserverOfAChange(conversation,
            modifier: { _ in
                let user2 = ZMUser.insertNewObject(in:self.uiMOC)
                user2.name = "Foo B"
                self.uiMOC.saveOrRollback()
                XCTAssertEqual(user1.displayName, "Foo A")
            },
            expectedChangedField: "nameChanged",
            expectedChangedKeys: KeySet(["displayName"])
        )
    }
    
    func testThatItNotifiesTheObserverOfANameChangeBecauseAUserWasAddedAndLaterItsNameChanged()
    {
        // given
        let user1 = ZMUser.insertNewObject(in:self.uiMOC)
        user1.name = "Foo A"
        
        let user2 = ZMUser.insertNewObject(in:self.uiMOC)
        user2.name = "Bar"
        
        let conversation = ZMConversation.insertNewObject(in:self.uiMOC)
        conversation.conversationType = ZMConversationType.group
        conversation.mutableOtherActiveParticipants.add(user1)
        XCTAssertEqual(user1.displayName, "Foo")
        
        // when
        self.checkThatItNotifiesTheObserverOfAChange(conversation,
            modifier: { _ in
                user2.name = "Foo B"
                uiMOC.saveOrRollback()
                XCTAssertEqual(user1.displayName, "Foo A")
            },
            expectedChangedField: "nameChanged",
            expectedChangedKeys: KeySet(["displayName"])
        )
    }
    
    func testThatItDoesNotNotifyTheObserverOfANameChangeBecauseAUserWasRemovedAndLaterItsNameChanged()
    {
        // given
        let user1 = ZMUser.insertNewObject(in:self.uiMOC)
        user1.name = "Foo A"
        
        let conversation = ZMConversation.insertNewObject(in:self.uiMOC)
        conversation.conversationType = ZMConversationType.group
        conversation.mutableOtherActiveParticipants.add(user1)
        
        self.updateDisplayNameGenerator(withUsers: [user1])
        
        XCTAssertTrue(user1.displayName == "Foo")
        XCTAssertTrue(conversation.otherActiveParticipants.contains(user1))
        
        // when
        self.checkThatItNotifiesTheObserverOfAChange(conversation,
            modifier: { conversation, observer in
                conversation.mutableOtherActiveParticipants.remove(user1)
                self.uiMOC.saveOrRollback()
                observer.clearNotifications()
                user1.name = "Bar"
                self.updateDisplayNameGenerator(withUsers: [user1])
            },
            expectedChangedField: nil,
            expectedChangedKeys: KeySet()
        )
    }
    
    func testThatItNotifysTheObserverOfANameChangeBecauseAUserWasAddedLaterAndHisNameChanged()
    {
        // given
        let user1 = ZMUser.insertNewObject(in:self.uiMOC)
        user1.name = "Foo A"
        
        let conversation = ZMConversation.insertNewObject(in:self.uiMOC)
        conversation.conversationType = ZMConversationType.group
        self.uiMOC.saveOrRollback()
        
        XCTAssertTrue(user1.displayName == "Foo")

        // when
        self.checkThatItNotifiesTheObserverOfAChange(conversation,
            modifier: { conversation, observer in
                conversation.mutableOtherActiveParticipants.add(user1)
                self.uiMOC.saveOrRollback()
                observer.clearNotifications()
                self.notifyNameChange(user1, name: "Bar")
            },
            expectedChangedField: "nameChanged",
            expectedChangedKeys: KeySet(["displayName"])
        )
    }
    
    func testThatItNotifiesTheObserverOfAnInsertedMessage()
    {
        // given
        let conversation = ZMConversation.insertNewObject(in:self.uiMOC)
        conversation.lastReadServerTimeStamp = Date()
        self.uiMOC.saveOrRollback()
        
        // when
        self.checkThatItNotifiesTheObserverOfAChange(conversation,
            modifier: { conversation, _ in
                _ = conversation.appendMessage(withText: "foo")
            },
            expectedChangedField: "messagesChanged",
            expectedChangedKeys: KeySet(key: "messages"))
    }
    
    func testThatItNotifiesTheObserverOfAnAddedParticipant()
    {
        // given
        let conversation = ZMConversation.insertNewObject(in:self.uiMOC)
        conversation.conversationType = ZMConversationType.group
        let user = ZMUser.insertNewObject(in:self.uiMOC)
        
        // when
        self.checkThatItNotifiesTheObserverOfAChange(conversation,
            modifier: { conversation, _ in conversation.mutableOtherActiveParticipants.add(user) },
            expectedChangedField: "participantsChanged",
            expectedChangedKeys: KeySet(key: "otherActiveParticipants"))
        
    }
    
    func testThatItNotifiesTheObserverOfAnRemovedParticipant()
    {
        // given
        let conversation = ZMConversation.insertNewObject(in:self.uiMOC)
        conversation.conversationType = ZMConversationType.group
        let user = ZMUser.insertNewObject(in:self.uiMOC)
        conversation.mutableOtherActiveParticipants.add(user)
        self.uiMOC.saveOrRollback()

        // when
        self.checkThatItNotifiesTheObserverOfAChange(conversation,
            modifier: {conversation, _ in conversation.mutableOtherActiveParticipants.remove(user) },
            expectedChangedField: "participantsChanged",
            expectedChangedKeys: KeySet(key: "otherActiveParticipants"))
    }
    
    func testThatItNotifiesTheObserverIfTheSelfUserIsAdded()
    {
        // given
        let conversation = ZMConversation.insertNewObject(in:self.uiMOC)
        conversation.conversationType = ZMConversationType.group
        conversation.isSelfAnActiveMember = false
        self.uiMOC.saveOrRollback()
        
        // when
        self.checkThatItNotifiesTheObserverOfAChange(conversation,
            modifier: {conversation, _ in conversation.isSelfAnActiveMember = true },
            expectedChangedField: "participantsChanged",
            expectedChangedKeys: KeySet(key: "isSelfAnActiveMember"))
        
    }
    
    func testThatItNotifiesTheObserverWhenTheUserLeavesTheConversation()
    {
        // given
        let conversation = ZMConversation.insertNewObject(in:self.uiMOC)
        conversation.conversationType = ZMConversationType.group
        _ = ZMUser.insertNewObject(in:self.uiMOC)
        conversation.isSelfAnActiveMember = true
        
        // when
        self.checkThatItNotifiesTheObserverOfAChange(conversation,
            modifier: {conversation, _ in conversation.isSelfAnActiveMember = false },
            expectedChangedField: "participantsChanged",
            expectedChangedKeys: KeySet(key: "isSelfAnActiveMember"))
        
    }
    
    func testThatItNotifiesTheObserverOfChangedLastModifiedDate()
    {
        // given
        let conversation = ZMConversation.insertNewObject(in:self.uiMOC)
        self.uiMOC.saveOrRollback()

        // when
        self.checkThatItNotifiesTheObserverOfAChange(conversation,
            modifier: { conversation, _ in conversation.lastModifiedDate = Date() },
            expectedChangedField: "lastModifiedDateChanged",
            expectedChangedKeys: KeySet(key: "lastModifiedDate"))
        
    }
    
    func testThatItNotifiesTheObserverOfChangedUnreadCount()
    {
        // given
        self.syncMOC.performGroupedBlockAndWait{
            let conversation = ZMConversation.insertNewObject(in:self.syncMOC)
            conversation.lastReadServerTimeStamp = Date()
            let message = ZMMessage.insertNewObject(in: self.syncMOC)
            message.visibleInConversation = conversation
            message.serverTimestamp = conversation.lastReadServerTimeStamp?.addingTimeInterval(10)
            self.syncMOC.saveOrRollback()
            
            conversation.didUpdateWhileFetchingUnreadMessages()
            self.syncMOC.saveOrRollback()
            XCTAssertEqual(conversation.estimatedUnreadCount, 1)
            
            // when
            self.checkThatItNotifiesTheObserverOfAChange(conversation,
                modifier: { conversation, _ in
                    conversation.lastReadServerTimeStamp = message.serverTimestamp
                    conversation.updateUnread()
                    XCTAssertEqual(conversation.estimatedUnreadCount, 0)
                },
                expectedChangedFields: KeySet(["unreadCountChanged", "conversationListIndicatorChanged"]),
                expectedChangedKeys: KeySet(["estimatedUnreadCount", "conversationListIndicator"]))
        }
    }
    
    func testThatItNotifiesTheObserverOfChangedDisplayName()
    {
        // given
        let conversation = ZMConversation.insertNewObject(in:self.uiMOC)
        conversation.conversationType = ZMConversationType.group
        
        // when
        self.checkThatItNotifiesTheObserverOfAChange(conversation,
            modifier: { conversation, _ in conversation.userDefinedName = "Cacao" },
            expectedChangedField: "nameChanged" ,
            expectedChangedKeys: KeySet(["displayName"]))
        
    }
    
    func testThatItNotifiesTheObserverOfChangedConnectionStatusWhenInsertingAConnection()
    {
        // given
        let conversation = ZMConversation.insertNewObject(in:self.uiMOC)
        conversation.conversationType = ZMConversationType.oneOnOne
        self.uiMOC.saveOrRollback()

        // when
        self.checkThatItNotifiesTheObserverOfAChange(conversation,
            modifier: { conversation, _ in
                conversation.connection = ZMConnection.insertNewObject(in: self.uiMOC)
                conversation.connection!.status = ZMConnectionStatus.pending
            },
            expectedChangedField: "connectionStateChanged" ,
            expectedChangedKeys: KeySet(key: "relatedConnectionState"))
    }
    
    func testThatItNotifiesTheObserverOfChangedConnectionStatusWhenUpdatingAConnection()
    {
        // given
        let conversation = ZMConversation.insertNewObject(in:self.uiMOC)
        conversation.conversationType = ZMConversationType.oneOnOne
        conversation.connection = ZMConnection.insertNewObject(in: self.uiMOC)
        conversation.connection!.status = ZMConnectionStatus.pending
        conversation.connection!.to = ZMUser.insertNewObject(in:self.uiMOC)
        self.uiMOC.saveOrRollback()

        // when
        self.checkThatItNotifiesTheObserverOfAChange(conversation,
            modifier: { conversation, _ in conversation.connection!.status = ZMConnectionStatus.accepted },
            expectedChangedField: "connectionStateChanged" ,
            expectedChangedKeys: KeySet(key: "relatedConnectionState"))
        
    }
    
    
    func testThatItNotifiesTheObserverOfChangedArchivedStatus()
    {
        // given
        let conversation = ZMConversation.insertNewObject(in:self.uiMOC)
        self.uiMOC.saveOrRollback()

        // when
        self.checkThatItNotifiesTheObserverOfAChange(conversation,
            modifier: { conversation, _ in conversation.isArchived = true },
            expectedChangedField: "isArchivedChanged" ,
            expectedChangedKeys: KeySet(key: "isArchived"))
        
    }
    
    func testThatItNotifiesTheObserverOfChangedSilencedStatus()
    {
        // given
        let conversation = ZMConversation.insertNewObject(in:self.uiMOC)
        self.uiMOC.saveOrRollback()

        // when
        self.checkThatItNotifiesTheObserverOfAChange(conversation,
            modifier: { conversation, _ in conversation.isSilenced = true },
            expectedChangedField: "isSilencedChanged" ,
            expectedChangedKeys: KeySet(key: "isSilenced"))
        
    }
    
    func addUnreadMissedCall(_ conversation: ZMConversation) {
        let systemMessage = ZMSystemMessage.insertNewObject(in: conversation.managedObjectContext!)
        systemMessage.systemMessageType = .missedCall;
        systemMessage.serverTimestamp = Date(timeIntervalSince1970:1231234)
        systemMessage.visibleInConversation = conversation
        conversation.updateUnreadMessages(with: systemMessage)
    }
    
    
    func testThatItNotifiesTheObserverOfAChangedListIndicatorBecauseOfAnUnreadMissedCall()
    {
        // given
        self.syncMOC.performGroupedBlockAndWait{
            let conversation = ZMConversation.insertNewObject(in:self.syncMOC)
            self.syncMOC.saveOrRollback()
            
            // when
            self.checkThatItNotifiesTheObserverOfAChange(conversation,
                modifier: { conversation, _ in
                    self.addUnreadMissedCall(conversation)
                },
                expectedChangedFields: KeySet(["conversationListIndicatorChanged", "messagesChanged"]),
                expectedChangedKeys: KeySet(["messages", "conversationListIndicator"]))
        }
    }
    
    func testThatItNotifiesTheObserverOfAChangedClearedTimeStamp()
    {
        // given
        let conversation = ZMConversation.insertNewObject(in:self.uiMOC)
        self.uiMOC.saveOrRollback()

        // when
        self.checkThatItNotifiesTheObserverOfAChange(conversation,
            modifier: { conversation, _ in
                conversation.clearedTimeStamp = Date()
            },
            expectedChangedField: "clearedChanged" ,
            expectedChangedKeys: KeySet(key: "clearedTimeStamp"))
    }
    
    func testThatItNotifiesTheObserverOfASecurityLevelChange() {
        // given
        let conversation = ZMConversation.insertNewObject(in:self.uiMOC)
        self.uiMOC.saveOrRollback()

        // when
        self.checkThatItNotifiesTheObserverOfAChange(conversation,
            modifier: { conversation, _ in
                conversation.securityLevel = .secure
            },
            expectedChangedField: "securityLevelChanged" ,
            expectedChangedKeys: KeySet(key: SecurityLevelKey))
    }
    
    func testThatItStopsNotifyingAfterUnregisteringTheToken() {
        
        // given
        let conversation = ZMConversation.insertNewObject(in:self.uiMOC)
        self.uiMOC.saveOrRollback()
        
        let observer = TestConversationObserver()
        let token = conversation.add(observer)
        ZMConversation.removeObserver(for: token)
        
        
        // when
        conversation.userDefinedName = "Mario!"
        self.uiMOC.saveOrRollback()
        
        // then
        XCTAssertEqual(observer.receivedChangeInfo.count, 0)
    }
    
    func testPerformanceOfCalculatingChangeNotificationsWhenUserChangesName()
    {
        // average: 0.057, relative standard deviation: 13.943%, values: [0.079933, 0.054011, 0.053161, 0.058086, 0.052317, 0.054542, 0.052928, 0.053991, 0.053392, 0.054210],
        let count = 50
        
        self.measureMetrics([XCTPerformanceMetric_WallClockTime], automaticallyStartMeasuring: false) {
            
            let user = ZMUser.insertNewObject(in: self.uiMOC)
            user.name = "foo"
            let conversation = ZMConversation.insertNewObject(in:self.uiMOC)
            conversation.conversationType = .group
            conversation.mutableOtherActiveParticipants.add(user)
            self.uiMOC.saveOrRollback()
            
            let observer = TestConversationObserver()
            let token = conversation.add(observer)
            
            var lastName = "bar"
            self.startMeasuring()
            for _ in 1...count {
                let temp = lastName
                lastName = user.name
                user.name = temp
                self.uiMOC.saveOrRollback()
            }
            XCTAssertEqual(observer.receivedChangeInfo.count, count)
            self.stopMeasuring()
            ZMConversation.removeObserver(for: token)
        }
    }
    
    func testPerformanceOfCalculatingChangeNotificationsWhenANewMessageArrives()
    {
        // measured [Time, seconds] average: 0.058, relative standard deviation: 14.553%, values: [0.082845, 0.054582, 0.053719, 0.053366, 0.053231, 0.055812, 0.053711, 0.058502, 0.056946, 0.059161], 
        let count = 50
        
        self.measureMetrics([XCTPerformanceMetric_WallClockTime], automaticallyStartMeasuring: false) {
            
            let conversation = ZMConversation.insertNewObject(in:self.uiMOC)
            self.uiMOC.saveOrRollback()
            
            let observer = TestConversationObserver()
            let token = conversation.add(observer)
            
            self.startMeasuring()
            for _ in 1...count {
                conversation.appendMessage(withText: "hello")
                self.uiMOC.processPendingChanges()
            }
            XCTAssertEqual(observer.receivedChangeInfo.count, count)
            self.stopMeasuring()
            ZMConversation.removeObserver(for: token)
        }
    }
    
    func testPerformanceOfCalculatingChangeNotificationsWhenANewMessageArrives_AppendingManyMessages()
    {
        // 50: average: 0.018, relative standard deviation: 34.321%, values: [0.035791, 0.017149, 0.015688, 0.016396, 0.015284, 0.015345, 0.015833, 0.015590, 0.015013, 0.014772]
        // 500: average: 0.154, relative standard deviation: 6.143%, values: [0.180784, 0.153532, 0.159269, 0.150676, 0.152488, 0.147645, 0.147971, 0.150903, 0.149406, 0.148501], 
        let count = 500
        
        self.measureMetrics([XCTPerformanceMetric_WallClockTime], automaticallyStartMeasuring: false) {
            
            let conversation = ZMConversation.insertNewObject(in:self.uiMOC)
            self.uiMOC.saveOrRollback()
            
            let observer = TestConversationObserver()
            let token = conversation.add(observer)
            
            self.startMeasuring()
            for _ in 1...count {
                conversation.appendMessage(withText: "hello")
            }
            self.uiMOC.processPendingChanges()
            XCTAssertEqual(observer.receivedChangeInfo.count, 1)
            self.stopMeasuring()
            ZMConversation.removeObserver(for: token)
        }
    }
    
    func testPerformanceOfCalculatingChangeNotificationsWhenANewMessageArrives_RegisteringAnObsever()
    {
        // 50: average: 0.154, relative standard deviation: 14.238%, values: [0.137086, 0.122121, 0.130414, 0.145946, 0.145511, 0.151725, 0.162711, 0.171082, 0.185402, 0.192517],
        // 500: average: 6.785, relative standard deviation: 52.570%, values: [1.613123, 2.536764, 3.633100, 4.787423, 5.926587, 7.130392, 8.417895, 9.744791, 11.248857, 12.808965],  // growing each time! wow!

        let count = 500
        
        self.measureMetrics([XCTPerformanceMetric_WallClockTime], automaticallyStartMeasuring: false) {
            
            let observer = TestConversationObserver()
            
            self.startMeasuring()
            for _ in 1...count {
                let conversation = ZMConversation.insertNewObject(in:self.uiMOC)
                self.uiMOC.saveOrRollback()
                let token = conversation.add(observer)
                conversation.appendMessage(withText: "hello")
                self.uiMOC.processPendingChanges()
                ZMConversation.removeObserver(for: token)
            }
            self.stopMeasuring()
        }
    }
}
