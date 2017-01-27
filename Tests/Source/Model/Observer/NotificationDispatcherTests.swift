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
@testable import ZMCDataModel



@objc public class NotificationDispatcherTestBase : ZMBaseManagedObjectTest {

    var dispatcher : NotificationDispatcher! {
        return sut
    }
    var sut : NotificationDispatcher!
    var conversationObserver : ConversationObserver!
    var mergeNotifications = [Notification]()
    
    override public func setUp() {
        super.setUp()
        conversationObserver = ConversationObserver()
        sut = NotificationDispatcher(managedObjectContext: uiMOC)
        NotificationCenter.default.addObserver(self, selector: #selector(NotificationDispatcherTestBase.contextDidMerge(_:)), name: Notification.Name.NSManagedObjectContextDidSave, object: syncMOC)
        mergeNotifications = []
    }
    
    override public func tearDown() {
        NotificationCenter.default.removeObserver(self)
        sut.tearDown()
        sut = nil
        mergeNotifications = []
        super.tearDown()
    }
    
    @objc public func contextDidMerge(_ note: Notification) {
        mergeNotifications.append(note)
    }
    
    @objc public func mergeLastChanges() {
        guard let change = mergeNotifications.last else { return }
        let changedObjects = (change.userInfo?[NSUpdatedObjectsKey] as? Set<ZMManagedObject>)?.map{$0.objectID} ?? []
        self.dispatcher.willMergeChanges(Set(changedObjects))
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        self.uiMOC.mergeChanges(fromContextDidSave: change)

        self.dispatcher.didMergeChanges()
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        mergeNotifications = []
    }
}

class NotificationDispatcherTests : NotificationDispatcherTestBase {

    func testThatItNotifiesAboutChanges(){
        
        // given
        let conversation = ZMConversation.insertNewObject(in: uiMOC)
        uiMOC.saveOrRollback()
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        let token = ConversationChangeInfo.add(observer: conversationObserver, for: conversation)

        // when
        conversation.userDefinedName = "foo"
        uiMOC.saveOrRollback()
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(conversationObserver.notifications.count, 1)
        guard let changeInfo = conversationObserver.notifications.first else {
            return XCTFail()
        }
        XCTAssertTrue(changeInfo.nameChanged)
        ConversationChangeInfo.remove(observer: token, for: conversation)
    }
    
    func testThatItNotifiesAboutChangesInOtherObjects(){
        
        // given
        let user = ZMUser.insertNewObject(in: uiMOC)
        user.name = "Bernd"
        let conversation = ZMConversation.insertNewObject(in: uiMOC)
        conversation.conversationType = .group
        conversation.mutableOtherActiveParticipants.add(user)
        uiMOC.saveOrRollback()
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        let token = ConversationChangeInfo.add(observer: conversationObserver, for: conversation)
        
        // when
        user.name = "Brett"
        uiMOC.saveOrRollback()
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(conversationObserver.notifications.count, 1)
        guard let changeInfo = conversationObserver.notifications.first else {
            return XCTFail()
        }
        XCTAssertTrue(changeInfo.nameChanged)
        ConversationChangeInfo.remove(observer: token, for: conversation)
    }
}
