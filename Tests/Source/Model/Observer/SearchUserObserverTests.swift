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

class SearchUserObserverTests : NotificationDispatcherTestBase {
    
    class TestSearchUserObserver : NSObject, ZMUserObserver {
        
        var receivedChangeInfo : [UserChangeInfo] = []
        
        func userDidChange(_ changeInfo: UserChangeInfo) {
            receivedChangeInfo.append(changeInfo)
        }
    }
    
    var testObserver : TestSearchUserObserver!
    
    override func setUp() {
        super.setUp()
        testObserver = TestSearchUserObserver()
    }
    
    override func tearDown() {
        testObserver = nil
        uiMOC.searchUserObserverCenter.reset()
        super.tearDown()
    }
    
    func testThatItNotifiesTheObserverOfASmallProfilePictureChange() {
        
        // given
        let remoteID = UUID.create()
        let searchUser = ZMSearchUser(name: "Hans",
                                      handle: "hans",
                                      accentColor: .brightOrange,
                                      remoteID: remoteID,
                                      user: nil,
                                      syncManagedObjectContext: self.syncMOC,
                                      uiManagedObjectContext:self.uiMOC)!
        
        uiMOC.searchUserObserverCenter.addSearchUser(searchUser)
        self.token = UserChangeInfo.add(observer: testObserver, forBareUser: searchUser, managedObjectContext: self.uiMOC)
        
        // when
        searchUser.notifyNewSmallImageData(self.verySmallJPEGData(), searchUserObserverCenter: uiMOC.searchUserObserverCenter)
        
        // then
        XCTAssertEqual(testObserver.receivedChangeInfo.count, 1)
        if let note = testObserver.receivedChangeInfo.first {
            XCTAssertTrue(note.imageSmallProfileDataChanged)
        }
    }
    
    func testThatItNotifiesTheObserverOfASmallProfilePictureChangeIfTheInternalUserUpdates() {
        
        // given
        let user = ZMUser.insertNewObject(in:self.uiMOC)
        user.remoteIdentifier = UUID.create()
        self.uiMOC.saveOrRollback()
        let searchUser = ZMSearchUser(name: "Foo",
                                      handle: "foo",
                                      accentColor: .brightYellow,
                                      remoteID: user.remoteIdentifier,
                                      user: user,
                                      syncManagedObjectContext: self.syncMOC,
                                      uiManagedObjectContext:self.uiMOC)!
        
        uiMOC.searchUserObserverCenter.addSearchUser(searchUser)
        self.token = UserChangeInfo.add(observer: testObserver, forBareUser:searchUser, managedObjectContext: self.uiMOC)
        
        // when
        user.smallProfileRemoteIdentifier = UUID.create()
        user.imageSmallProfileData = self.verySmallJPEGData()
        self.uiMOC.saveOrRollback()
        
        // then
        XCTAssertEqual(testObserver.receivedChangeInfo.count, 1)
        if let note = testObserver.receivedChangeInfo.first {
            XCTAssertTrue(note.imageSmallProfileDataChanged)
        }
    }
    
    func testThatItStopsNotifyingAfterUnregisteringTheToken() {
        
        // given
        let remoteID = UUID.create()
        let searchUser = ZMSearchUser(name: "Hans",
                                      handle: "hans",
                                      accentColor: .brightOrange,
                                      remoteID: remoteID,
                                      user: nil,
                                      syncManagedObjectContext: self.syncMOC,
                                      uiManagedObjectContext:self.uiMOC)!
        
        uiMOC.searchUserObserverCenter.addSearchUser(searchUser)
        self.token = UserChangeInfo.add(observer: testObserver, forBareUser: searchUser, managedObjectContext: self.uiMOC)
        
        // when
        self.token = nil
        searchUser.notifyNewSmallImageData(self.verySmallJPEGData(), searchUserObserverCenter: uiMOC.searchUserObserverCenter)
        
        // then
        XCTAssertEqual(testObserver.receivedChangeInfo.count, 0)
    }
    
    func testThatItNotifiesObserversWhenConnectingToASearchUserThatHasNoLocalUser(){
    
        // given
        let remoteID = UUID.create()
        let searchUser = ZMSearchUser(name: "Hans",
                                      handle: "hans",
                                      accentColor: .brightOrange,
                                      remoteID: remoteID,
                                      user: nil,
                                      syncManagedObjectContext: self.syncMOC,
                                      uiManagedObjectContext:self.uiMOC)!
        
        XCTAssertFalse(searchUser.isPendingApprovalByOtherUser)
        uiMOC.searchUserObserverCenter.addSearchUser(searchUser)
        self.token = UserChangeInfo.add(observer: testObserver, forBareUser: searchUser, managedObjectContext: self.uiMOC)

        // expect
        let callbackCalled = expectation(description: "Connection callback was called")
        
        // when
        searchUser.connect(withMessageText: "Hey") { 
            callbackCalled.fulfill()
        }
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(testObserver.receivedChangeInfo.count, 1)
        guard let note = testObserver.receivedChangeInfo.first else { return XCTFail()}
        XCTAssertEqual(note.user as? ZMSearchUser, searchUser)
        XCTAssertTrue(note.connectionStateChanged)
    }
 
    func testThatItNotifiesObserverWhenConnectingToALocalUser() {
    
        // given
        let user = ZMUser.insertNewObject(in: uiMOC)
        user.remoteIdentifier = UUID()
        XCTAssert(uiMOC.saveOrRollback())

        let searchUser = ZMSearchUser(name: "Hans",
                                      handle: "hans",
                                      accentColor: .brightOrange,
                                      remoteID: nil,
                                      user: user,
                                      syncManagedObjectContext: self.syncMOC,
                                      uiManagedObjectContext:self.uiMOC)!
        
        let testObserver2 = TestSearchUserObserver()
        var tokens: [AnyObject] = []
        self.token = tokens
        tokens.append(UserChangeInfo.add(observer: testObserver, forBareUser: user, managedObjectContext: self.uiMOC)!)
        
        uiMOC.searchUserObserverCenter.addSearchUser(searchUser)
        tokens.append(UserChangeInfo.add(observer: testObserver2, forBareUser: searchUser, managedObjectContext: self.uiMOC)!)
        
        // expect
        let callbackCalled = expectation(description: "Connection callback was called")
        
        // when
        searchUser.connect(withMessageText: "Hey") {
            callbackCalled.fulfill()
        }
        XCTAssert(uiMOC.saveOrRollback())
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
        
        // when
        XCTAssertTrue(searchUser.user.isPendingApprovalByOtherUser)
        XCTAssertEqual(testObserver.receivedChangeInfo.count, 1)
        XCTAssertEqual(testObserver2.receivedChangeInfo.count, 1)
        
        if let note1 = testObserver.receivedChangeInfo.first {
            XCTAssertEqual(note1.user as? ZMUser, user)
            XCTAssertTrue(note1.connectionStateChanged)
        } else {
            XCTFail("Did not receive UserChangeInfo for ZMUser")
        }

        if let note2 = testObserver2.receivedChangeInfo.first {
            XCTAssertEqual(note2.user as? ZMSearchUser, searchUser)
            XCTAssertTrue(note2.connectionStateChanged)
        } else {
            XCTFail("Did not receive UserChangeInfo for ZMSearchUser")
        }
    }
}
