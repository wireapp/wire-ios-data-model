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

@testable import WireDataModel

class SearchUserSnapshotTests : ZMBaseManagedObjectTest {
    
    func testThatItCreatesASnapshotOfAllValues_noUser(){
        // given
        let searchUser = ZMSearchUser(name: "Bernd", handle: "dasBrot", accentColor: .brightOrange, remoteID: UUID(), user: nil, syncManagedObjectContext: syncMOC, uiManagedObjectContext: uiMOC)!

        // when
        let sut = SearchUserSnapshot(searchUser: searchUser, managedObjectContext: self.uiMOC)
        
        // then
        XCTAssertEqual(searchUser.imageMediumData,              sut.snapshotValues[ #keyPath(ZMSearchUser.imageMediumData)] as? Data)
        XCTAssertEqual(searchUser.imageSmallProfileData,        sut.snapshotValues[ #keyPath(ZMSearchUser.imageSmallProfileData)] as? Data)
        XCTAssertEqual(searchUser.user,                         sut.snapshotValues[ #keyPath(ZMSearchUser.user)] as? ZMUser)
        XCTAssertEqual(searchUser.isConnected,                  sut.snapshotValues[ #keyPath(ZMSearchUser.isConnected)] as? Bool)
        XCTAssertEqual(searchUser.isPendingApprovalByOtherUser, sut.snapshotValues[ #keyPath(ZMSearchUser.isPendingApprovalByOtherUser)] as? Bool)
    }
    
    func testThatItCreatesASnapshotOfAllValues_withUser(){
        // given
        let user = ZMUser.insertNewObject(in: uiMOC)
        user.name = "Bernd"
        user.remoteIdentifier = UUID()
        user.imageSmallProfileData = verySmallJPEGData()
        let searchUser = ZMSearchUser(name: nil, handle: nil, accentColor: .undefined, remoteID: nil, user: user, syncManagedObjectContext: syncMOC, uiManagedObjectContext: uiMOC)!
        
        // when
        let sut = SearchUserSnapshot(searchUser: searchUser, managedObjectContext: self.uiMOC)
        
        // then
        XCTAssertEqual(searchUser.imageMediumData,              sut.snapshotValues[ #keyPath(ZMSearchUser.imageMediumData)] as? Data)
        XCTAssertEqual(searchUser.imageSmallProfileData,        sut.snapshotValues[ #keyPath(ZMSearchUser.imageSmallProfileData)] as? Data)
        XCTAssertEqual(searchUser.user,                         sut.snapshotValues[ #keyPath(ZMSearchUser.user)] as? ZMUser)
        XCTAssertEqual(searchUser.isConnected,                  sut.snapshotValues[ #keyPath(ZMSearchUser.isConnected)] as? Bool)
        XCTAssertEqual(searchUser.isPendingApprovalByOtherUser, sut.snapshotValues[ #keyPath(ZMSearchUser.isPendingApprovalByOtherUser)] as? Bool)
    }
    
    func testThatItPostsANotificationWhenUserImageChanged(){
        // given
        let user = ZMUser.insertNewObject(in: uiMOC)
        user.name = "Bernd"
        user.remoteIdentifier = UUID()

        let searchUser = ZMSearchUser(name: nil, handle: nil, accentColor: .undefined, remoteID: nil, user: user, syncManagedObjectContext: syncMOC, uiManagedObjectContext: uiMOC)!
        let sut = SearchUserSnapshot(searchUser: searchUser, managedObjectContext: self.uiMOC)
        
        // expect
        expectation(forNotification: Notification.Name.SearchUserChange.rawValue, object: searchUser) { (note) -> Bool in
            guard let userChange = note.changeInfo as? UserChangeInfo else { return false }
            return userChange.imageSmallProfileDataChanged
        }
        
        // when
        user.smallProfileRemoteIdentifier = UUID()
        uiMOC.zm_userImageCache.setUserImage(user, imageData: verySmallJPEGData(), size: .preview)

        sut.updateAndNotify()
        
        // then
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
        XCTAssertEqual(searchUser.imageSmallProfileData, sut.snapshotValues[ #keyPath(ZMSearchUser.imageSmallProfileData)] as? Data)
    }
    
    func testThatItPostsANotificationWhenConnectionChanged(){
        // given
        let user = ZMUser.insertNewObject(in: uiMOC)
        user.name = "Bernd"
        user.remoteIdentifier = UUID()
        
        let searchUser = ZMSearchUser(name: nil, handle: nil, accentColor: .undefined, remoteID: nil, user: user, syncManagedObjectContext: syncMOC, uiManagedObjectContext: uiMOC)!
        let sut = SearchUserSnapshot(searchUser: searchUser, managedObjectContext: self.uiMOC)
        
        // expect
        expectation(forNotification: Notification.Name.SearchUserChange.rawValue, object: searchUser) { (note) -> Bool in
            guard let userChange = note.changeInfo as? UserChangeInfo else { return false }
            return userChange.connectionStateChanged
        }
        
        // when
        let connection = ZMConnection.insertNewObject(in: uiMOC)
        connection.to = user
        connection.status = .accepted
        sut.updateAndNotify()
        
        // then
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
        XCTAssertEqual(searchUser.isConnected, sut.snapshotValues[ #keyPath(ZMSearchUser.isConnected)] as? Bool)
    }
    
    func testThatItPostsANotificationWhenPendingApprovalChanged(){
        // given
        let user = ZMUser.insertNewObject(in: uiMOC)
        user.name = "Bernd"
        user.remoteIdentifier = UUID()
        let connection = ZMConnection.insertNewObject(in: uiMOC)
        connection.to = user
        connection.status = .pending
        
        let searchUser = ZMSearchUser(name: nil, handle: nil, accentColor: .undefined, remoteID: nil, user: user, syncManagedObjectContext: syncMOC, uiManagedObjectContext: uiMOC)!
        let sut = SearchUserSnapshot(searchUser: searchUser, managedObjectContext: self.uiMOC)
        
        // expect
        expectation(forNotification: Notification.Name.SearchUserChange.rawValue, object: searchUser) { (note) -> Bool in
            guard let userChange = note.changeInfo as? UserChangeInfo else { return false }
            return userChange.connectionStateChanged
        }
        
        // when
        connection.status = .accepted
        sut.updateAndNotify()
        
        // then
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
        XCTAssertEqual(searchUser.isConnected, sut.snapshotValues[ #keyPath(ZMSearchUser.isConnected)] as? Bool)
        XCTAssertEqual(searchUser.isPendingApprovalByOtherUser, sut.snapshotValues[ #keyPath(ZMSearchUser.isPendingApprovalByOtherUser)] as? Bool)
    }
    
    func testThatItPostsANotificationWhenTheUserIsAdded(){
        // given
        let user = ZMUser.insertNewObject(in: uiMOC)
        user.name = "Bernd"
        user.remoteIdentifier = UUID()
        
        let searchUser = ZMSearchUser(name: "Bernd", handle: "dasBrot", accentColor: .brightOrange, remoteID: UUID(), user: nil, syncManagedObjectContext: syncMOC, uiManagedObjectContext: uiMOC)!
        let sut = SearchUserSnapshot(searchUser: searchUser, managedObjectContext: self.uiMOC)
        
        // expect
        expectation(forNotification: Notification.Name.SearchUserChange.rawValue, object: searchUser) { (note) -> Bool in
            return (note.changeInfo as? UserChangeInfo) != nil
        }
        
        // when
        searchUser.setValue(user, forKey: "user") // this is done internally
        sut.updateAndNotify()
        
        // then
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
        XCTAssertEqual(searchUser.isConnected, sut.snapshotValues[ #keyPath(ZMSearchUser.isConnected)] as? Bool)
        XCTAssertEqual(searchUser.isPendingApprovalByOtherUser, sut.snapshotValues[ #keyPath(ZMSearchUser.isPendingApprovalByOtherUser)] as? Bool)
    }
}

class SearchUserObserverCenterTests : ModelObjectsTests {

    var sut : SearchUserObserverCenter!
    
    override func setUp() {
        super.setUp()
        sut = SearchUserObserverCenter()
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    func testThatItDeallocates(){
        // given
        let user = ZMUser.insertNewObject(in: uiMOC)
        user.name = "Bernd"
        user.remoteIdentifier = UUID()
        
        let searchUser = ZMSearchUser(name: nil, handle: nil, accentColor: .undefined, remoteID: nil, user: user, syncManagedObjectContext: syncMOC, uiManagedObjectContext: uiMOC)!
        uiMOC.searchUserObserverCenter.addSearchUser(searchUser, managedObjectContext: self.uiMOC)
        
        // when
        weak var observerCenter = uiMOC.searchUserObserverCenter
        uiMOC.userInfo.removeObject(forKey: NSManagedObjectContext.SearchUserObserverCenterKey)
        
        // then
        XCTAssertNil(observerCenter)
    }
    
    func testThatItAddsASnapshot(){
        // given
        let searchUser = ZMSearchUser(name: "Bernd", handle: "dasBrot", accentColor: .brightOrange, remoteID: UUID(), user: nil, syncManagedObjectContext: syncMOC, uiManagedObjectContext: uiMOC)!
        XCTAssertEqual(sut.snapshots.count, 0)

        // when
        sut.addSearchUser(searchUser, managedObjectContext: self.uiMOC)
        
        // then
        XCTAssertEqual(sut.snapshots.count, 1)
    }
    
    func testThatItRemovesAllSnapshotsOnReset(){
        // given
        let searchUser = ZMSearchUser(name: "Bernd", handle: "dasBrot", accentColor: .brightOrange, remoteID: UUID(), user: nil, syncManagedObjectContext: syncMOC, uiManagedObjectContext: uiMOC)!
        sut.addSearchUser(searchUser, managedObjectContext: self.uiMOC)
        XCTAssertEqual(sut.snapshots.count, 1)
        
        // when
        sut.reset()
        
        // then
        XCTAssertEqual(sut.snapshots.count, 0)
    }
    
    func testThatItForwardsUserChangeInfosToTheSnapshot(){
        // given
        let user = ZMUser.insertNewObject(in: uiMOC)
        user.name = "Bernd"
        user.remoteIdentifier = UUID()
        
        let searchUser = ZMSearchUser(name: nil, handle: nil, accentColor: .undefined, remoteID: nil, user: user, syncManagedObjectContext: syncMOC, uiManagedObjectContext: uiMOC)!
        sut.addSearchUser(searchUser, managedObjectContext: self.uiMOC)
        
        // expect       
        expectation(forNotification: Notification.Name.SearchUserChange.rawValue, object: searchUser)

        // when
        user.name = "Horst"
        let changeInfo = UserChangeInfo(object: user)
        changeInfo.changedKeys = Set(["name"])
        sut.objectsDidChange(changes: [ZMUser.classIdentifier: [changeInfo]])
        
        // then
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
    }
    
    func testThatItForwardCallsForUserUpdatesToTheSnapshot(){
        // given
        let searchUser = ZMSearchUser(name: "Bernd", handle: "dasBrot", accentColor: .brightOrange, remoteID: UUID(), user: nil, syncManagedObjectContext: syncMOC, uiManagedObjectContext: uiMOC)!
        sut.addSearchUser(searchUser, managedObjectContext: self.uiMOC)
        
        // expect
        expectation(forNotification: Notification.Name.SearchUserChange.rawValue, object: searchUser){ note in
            guard let userChange = note.changeInfo as? UserChangeInfo else { return false }
            return userChange.imageMediumDataChanged
        }
        
        // when
        searchUser.setAndNotifyNewMediumImageData(verySmallJPEGData(), searchUserObserverCenter: sut)
        
        // then
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
    }
}

