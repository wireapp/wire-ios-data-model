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

class UserObserver : NSObject, ZMUserObserver {

    var notifications = [UserChangeInfo]()

    func clearNotifications(){
        notifications = []
    }
    
    func userDidChange(_ note: UserChangeInfo!) {
        notifications.append(note)
    }
}

class UserObserverTests : NotificationDispatcherTests {
    
    let UserClientsKey = "clients"
    
    enum UserInfoChangeKey: String {
        case Name = "nameChanged"
        case AccentColor = "accentColorValueChanged"
        case ImageMediumData = "imageMediumDataChanged"
        case ImageSmallProfileData = "imageSmallProfileDataChanged"
        case ProfileInfo = "profileInformationChanged"
        case ConnectionState = "connectionStateChanged"
        case TrustLevel = "trustLevelChanged"
        case Handle = "handleChanged"
    }
    
    let userInfoChangeKeys: [UserInfoChangeKey] = [
        .Name,
        .AccentColor,
        .ImageMediumData,
        .ImageSmallProfileData,
        .ProfileInfo,
        .ConnectionState,
        .TrustLevel
    ]
    
    var userObserver : UserObserver!
    
    override func setUp() {
        super.setUp()
        userObserver = UserObserver()
    }
    
    override func tearDown() {
        userObserver = nil
        super.tearDown()
    }
}

extension UserObserverTests {

    func checkThatItNotifiesTheObserverOfAChange(_ user : ZMUser, modifier: (ZMUser) -> Void, expectedChangedField: UserInfoChangeKey, customAffectedKeys: AffectedKeys? = nil) {
        
        // given
        self.uiMOC.saveOrRollback()
        let token = UserChangeInfo.add(observer: userObserver, for: user)
        
        // when
        modifier(user)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        self.uiMOC.saveOrRollback()
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        let changeCount = userObserver.notifications.count
        XCTAssertEqual(changeCount, 1)
        
        // and when
        self.uiMOC.saveOrRollback()
        
        // then
        XCTAssertEqual(userObserver.notifications.count, changeCount, "Should not have changed further once")
        
        if let changes = userObserver.notifications.first {
            for key in userInfoChangeKeys where key != expectedChangedField  {
                if let value = changes.value(forKey: key.rawValue) as? NSNumber {
                    XCTAssertFalse(value.boolValue, "\(key.rawValue) was supposed to be false")
                }
                else {
                    XCTFail("Can't find key or key is not boolean for '\(key.rawValue)'")
                }
            }
        }
        UserChangeInfo.remove(observer: token, for: user)
    }
    
    
    func testThatItNotifiesTheObserverOfANameChange()
    {
        // given
        let user = ZMUser.insertNewObject(in:self.uiMOC)
        user.name = "George"
        self.uiMOC.saveOrRollback()
        
        // when
        self.checkThatItNotifiesTheObserverOfAChange(user,
                                                     modifier: { $0.name = "Phil"},
                                                     expectedChangedField: .Name)
        
    }
    
    func testThatItNotifiestheObserverOfMultipleNameChanges()
    {
        // given
        let user = ZMUser.insertNewObject(in:self.uiMOC)
        let token = UserChangeInfo.add(observer: userObserver, for: user)
        self.uiMOC.saveOrRollback()
        
        // when
        user.name = "Foo"
        self.uiMOC.saveOrRollback()
        
        // then
        XCTAssertEqual(userObserver.notifications.count, 1)
        
        // and when
        user.name = "Bar"
        self.uiMOC.saveOrRollback()
        
        // then
        XCTAssertEqual(userObserver.notifications.count, 2)
        
        // and when
        self.uiMOC.saveOrRollback()
        UserChangeInfo.remove(observer: token, for: user)
        
    }
    
    func testThatItNotifiesTheObserverOfAnAccentColorChange()
    {
        // given
        let user = ZMUser.insertNewObject(in:self.uiMOC)
        user.accentColorValue = ZMAccentColor.strongBlue
        uiMOC.saveOrRollback()

        // when
        self.checkThatItNotifiesTheObserverOfAChange(user,
                                                     modifier: { $0.accentColorValue = ZMAccentColor.softPink },
                                                     expectedChangedField: .AccentColor)
        
    }
    
    func testThatItNotifiesTheObserverOfAMediumProfileImageChange()
    {
        // given
        let user = ZMUser.insertNewObject(in:self.uiMOC)
        user.remoteIdentifier = UUID.create()
        user.mediumRemoteIdentifier = UUID.create()
        user.imageMediumData = self.verySmallJPEGData()
        uiMOC.saveOrRollback()
        
        // when
        self.checkThatItNotifiesTheObserverOfAChange(user,
                                                     modifier: { $0.imageMediumData = Data() },
                                                     expectedChangedField: .ImageMediumData)
    }
    
    func testThatItNotifiesTheObserverOfASmallProfileImageChange()
    {
        // given
        let user = ZMUser.insertNewObject(in:self.uiMOC)
        user.remoteIdentifier = UUID.create()
        user.smallProfileRemoteIdentifier = UUID.create()
        user.imageSmallProfileData = self.verySmallJPEGData()
        uiMOC.saveOrRollback()

        // when
        self.checkThatItNotifiesTheObserverOfAChange(user,
                                                     modifier: { $0.imageSmallProfileData = Data() },
                                                     expectedChangedField: .ImageSmallProfileData)
    }
    
    func testThatItNotifiesTheObserverOfAnEmailChange()
    {
        // given
        let user = ZMUser.insertNewObject(in:self.uiMOC)
        self.setEmailAddress("foo@example.com", on: user)
        uiMOC.saveOrRollback()

        // when
        self.checkThatItNotifiesTheObserverOfAChange(user,
                                                     modifier: { self.setEmailAddress(nil, on: $0) },
                                                     expectedChangedField: .ProfileInfo)
    }
    
    func testThatItNotifiesTheObserverOfAnUsernameChange_fromNil()
    {
        // given
        let user = ZMUser.insertNewObject(in:self.uiMOC)
        XCTAssertNil(user.handle)
        uiMOC.saveOrRollback()

        // when
        self.checkThatItNotifiesTheObserverOfAChange(user,
                                                     modifier: { $0.setValue("handle", forKey: "handle") },
                                                     expectedChangedField: .Handle)
    }
    
    func testThatItNotifiesTheObserverOfAnUsernameChange()
    {
        // given
        let user = ZMUser.insertNewObject(in:self.uiMOC)
        user.setValue("oldHandle", forKey: "handle")
        uiMOC.saveOrRollback()

        // when
        self.checkThatItNotifiesTheObserverOfAChange(user,
                                                     modifier: { $0.setValue("newHandle", forKey: "handle") },
                                                     expectedChangedField: .Handle)
    }
    
    func testThatItNotifiesTheObserverOfAPhoneNumberChange()
    {
        // given
        let user = ZMUser.insertNewObject(in:self.uiMOC)
        self.setPhoneNumber("+99-32312423423", on: user)
        uiMOC.saveOrRollback()

        
        // when
        self.checkThatItNotifiesTheObserverOfAChange(user,
                                                     modifier: { self.setPhoneNumber("+99-0000", on: $0) },
                                                     expectedChangedField: .ProfileInfo)
    }
    
    func testThatItNotifiesTheObserverOfAConnectionStateChange()
    {
        // given
        let user = ZMUser.insertNewObject(in:self.uiMOC)
        user.connection = ZMConnection.insertNewObject(in: self.uiMOC)
        user.connection!.status = ZMConnectionStatus.pending
        self.uiMOC.saveOrRollback()
        
        // when
        self.checkThatItNotifiesTheObserverOfAChange(user,
                                                     modifier : { $0.connection!.status = ZMConnectionStatus.accepted },
                                                     expectedChangedField: .ConnectionState,
                                                     customAffectedKeys: AffectedKeys.all)
    }
    
    func testThatItNotifiesTheObserverOfACreatedIncomingConnection()
    {
        // given
        let user = ZMUser.insertNewObject(in:self.uiMOC)
        self.uiMOC.saveOrRollback()
        
        // when
        self.checkThatItNotifiesTheObserverOfAChange(user,
                                                     modifier : {
                                                        $0.connection = ZMConnection.insertNewObject(in: self.uiMOC)
                                                        $0.connection!.status = ZMConnectionStatus.pending
            },
                                                     expectedChangedField: .ConnectionState,
                                                     customAffectedKeys: AffectedKeys.all)
    }
    
    func testThatItNotifiesTheObserverOfACreatedOutgoingConnection()
    {
        // given
        let user = ZMUser.insertNewObject(in:self.uiMOC)
        self.uiMOC.saveOrRollback()
        
        // when
        self.checkThatItNotifiesTheObserverOfAChange(user,
                                                     modifier : {
                                                        $0.connection = ZMConnection.insertNewObject(in: self.uiMOC)
                                                        $0.connection!.status = ZMConnectionStatus.sent
            },
                                                     expectedChangedField: .ConnectionState,
                                                     customAffectedKeys: AffectedKeys.all)
    }
    
    func testThatItStopsNotifyingAfterUnregisteringTheToken() {
        
        // given
        let user = ZMUser.insertNewObject(in:self.uiMOC)
        self.setEmailAddress("foo@example.com", on: user)
        self.uiMOC.saveOrRollback()
        
        let token = UserChangeInfo.add(observer: userObserver, for: user)
        UserChangeInfo.remove(observer: token, for: user)
        
        
        // when
        user.emailAddress = "aaaaaa@example.com"
        self.uiMOC.saveOrRollback()
        
        // then
        XCTAssertEqual(userObserver.notifications.count, 0)
    }
    
    func testThatItNotifiesUserForClientStartsTrusting() {
        
        // given
        let user = ZMUser.selfUser(in: self.uiMOC)
        let client = UserClient.insertNewObject(in: self.uiMOC)
        let otherUser = ZMUser.insertNewObject(in:self.uiMOC)
        let otherClient = UserClient.insertNewObject(in: self.uiMOC)
        user.mutableSetValue(forKey: UserClientsKey).add(client)
        otherUser.mutableSetValue(forKey: UserClientsKey).add(otherClient)
        
        // when
        self.uiMOC.saveOrRollback()
        XCTAssert(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        print(user.objectID, otherUser.objectID)

        
        // then
        self.checkThatItNotifiesTheObserverOfAChange(otherUser,
                                                     modifier: { _ in client.trustClient(otherClient) },
                                                     expectedChangedField: .TrustLevel)
        
        XCTAssertTrue(otherClient.trustedByClients.contains(client))
    }
    
    func testThatItNotifiesUserForClientStartsIgnoring() {
        
        // given
        let user = ZMUser.selfUser(in: self.uiMOC)
        let client = UserClient.insertNewObject(in: self.uiMOC)
        let otherUser = ZMUser.insertNewObject(in:self.uiMOC)
        let otherClient = UserClient.insertNewObject(in: self.uiMOC)
        user.mutableSetValue(forKey: UserClientsKey).add(client)
        otherUser.mutableSetValue(forKey: UserClientsKey).add(otherClient)
        
        // when
        client.trustClient(otherClient)
        self.uiMOC.saveOrRollback()
        XCTAssert(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        self.checkThatItNotifiesTheObserverOfAChange(otherUser,
                                                     modifier: { _ in client.ignoreClient(otherClient) },
                                                     expectedChangedField: .TrustLevel)
        
        XCTAssertFalse(otherClient.trustedByClients.contains(client))
        XCTAssertTrue(otherClient.ignoredByClients.contains(client))
    }
    
    func testThatItUpdatesClientObserversWhenClientIsAdded() {
        
        // given
        let selfUser = ZMUser.selfUser(in: self.uiMOC)
        let selfClient = UserClient.insertNewObject(in: self.uiMOC)
        selfUser.mutableSetValue(forKey: UserClientsKey).add(selfClient)
        self.uiMOC.saveOrRollback()
        let token = UserChangeInfo.add(observer: userObserver, for: selfUser)
        
        // when
        let otherClient = UserClient.insertNewObject(in: self.uiMOC)
        selfUser.mutableSetValue(forKey: UserClientsKey).add(otherClient)
        self.uiMOC.saveOrRollback()
        XCTAssert(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        guard let changeInfo = userObserver.notifications.first else { return XCTFail("Should receive a changeInfo for the added client") }
        XCTAssertTrue(changeInfo.clientsChanged)
        XCTAssertTrue(changeInfo.changedKeysAndOldValues.keys.contains(UserClientsKey))
        
        // after
        UserChangeInfo.remove(observer: token, for: selfUser)
    }
    
    
    func testThatItUpdatesClientObserversWhenClientIsRemoved() {
        
        // given
        let selfUser = ZMUser.selfUser(in: self.uiMOC)
        let selfClient = UserClient.insertNewObject(in: self.uiMOC)
        let otherClient = UserClient.insertNewObject(in: self.uiMOC)
        selfUser.mutableSetValue(forKey: UserClientsKey).add(selfClient)
        selfUser.mutableSetValue(forKey: UserClientsKey).add(otherClient)
        self.uiMOC.saveOrRollback()
        XCTAssertEqual(selfUser.clients.count, 2)
        
        let token = UserChangeInfo.add(observer: userObserver, for: selfUser)
        
        // when
        selfUser.mutableSetValue(forKey: UserClientsKey).remove(otherClient)
        self.uiMOC.saveOrRollback()
        XCTAssert(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        guard let changeInfo = userObserver.notifications.first else { return XCTFail("Should receive a changeInfo for the added client") }
        XCTAssertTrue(changeInfo.clientsChanged)
        XCTAssertTrue(changeInfo.changedKeysAndOldValues.keys.contains(UserClientsKey))
        XCTAssertEqual(selfUser.clients, Set(arrayLiteral: selfClient))
        XCTAssertEqual(selfUser.clients.count, 1)
        
        UserChangeInfo.remove(observer: token, for: selfUser)
    }
    
    func testThatItUpdatesClientObserversWhenClientsAreFaultedAndNewClientIsAdded() {
        
        // given
        var objectID: NSManagedObjectID!
        var syncMOCUser: ZMUser!
        
        syncMOC.performGroupedBlockAndWait {
            syncMOCUser = ZMUser.insertNewObject(in:self.syncMOC)
            self.syncMOC.saveOrRollback()
            objectID = syncMOCUser.objectID
            XCTAssertEqual(syncMOCUser.clients.count, 0)
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        guard let object = try? uiMOC.existingObject(with: objectID), let uiMOCUser = object as? ZMUser else {
            return XCTFail("Unable to get user with objectID in uiMOC")
        }
        
        let token = UserChangeInfo.add(observer: userObserver, for: uiMOCUser)
        
        // when adding a new client on the syncMOC
        syncMOC.performGroupedBlockAndWait {
            let client = UserClient.insertNewObject(in: self.syncMOC)
            syncMOCUser.mutableSetValue(forKey: self.UserClientsKey).add(client)
            self.syncMOC.saveOrRollback()
            XCTAssertTrue(syncMOCUser.isFault)
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        mergeLastChanges()
        dispatcher.fireAllNotifications()
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then we should receive a changeInfo with clientsChanged on the uiMOC
        let changeInfo = userObserver.notifications.first
        XCTAssertEqual(userObserver.notifications.count, 1)
        XCTAssertEqual(changeInfo?.clientsChanged, true)
        XCTAssertEqual(uiMOCUser.clients.count, 1)
        
        UserChangeInfo.remove(observer: token, for: uiMOCUser)
    }
    
    func testThatItUpdatesClientObserversWhenClientsAreFaultedAndNewClientIsAddedSameContext() {
        
        // given
        let user = ZMUser.insertNewObject(in:uiMOC)
        XCTAssertEqual(user.clients.count, 0)
        XCTAssertFalse(user.clients.first?.user?.isFault == .some(true))
        
        uiMOC.saveOrRollback()
        uiMOC.refresh(user, mergeChanges: true)
        XCTAssertTrue(user.isFault)
        let token = UserChangeInfo.add(observer: userObserver, for: user)
        
        // when
        let client = UserClient.insertNewObject(in: uiMOC)
        user.mutableSetValue(forKey: UserClientsKey).add(client)
        
        uiMOC.saveOrRollback()
        uiMOC.refresh(user, mergeChanges: true)
        uiMOC.refresh(client, mergeChanges: true)
        
        XCTAssertTrue(user.isFault)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        let changeInfo = userObserver.notifications.first
        XCTAssertEqual(changeInfo?.clientsChanged, true)
        XCTAssertEqual(user.clients.count, 1)
        
        UserChangeInfo.remove(observer: token, for: user)
    }
    
    func testThatItNotifiesTrustChangeForClientsAddedAfterSubscribing() {
        
        // given
        let selfUser = ZMUser.selfUser(in: uiMOC)
        let selfClient = UserClient.insertNewObject(in: uiMOC)
        selfUser.mutableSetValue(forKey: UserClientsKey).add(selfClient)
        
        let observedUser = ZMUser.insertNewObject(in:uiMOC)
        let otherClient = UserClient.insertNewObject(in: uiMOC)
        uiMOC.saveOrRollback()
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        let token = UserChangeInfo.add(observer: userObserver, for: observedUser)
        
        // when
        observedUser.mutableSetValue(forKey: UserClientsKey).add(otherClient)
        uiMOC.saveOrRollback()
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        //then
        XCTAssertEqual(userObserver.notifications.count, 1)
        let note : UserChangeInfo = userObserver.notifications.first!
        let clientsChanged : Bool = note.clientsChanged
        XCTAssertEqual(clientsChanged, true)
        
        // when
        selfClient.trustClient(otherClient)
        uiMOC.saveOrRollback()
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        let userChangeInfos = userObserver.notifications
        
        XCTAssertEqual(observedUser.clients.count, 1)
        XCTAssertEqual(userChangeInfos.count, 2)
        XCTAssertEqual(userChangeInfos.map { $0.trustLevelChanged }, [false, true])
        XCTAssertEqual(userChangeInfos.map { $0.clientsChanged }, [true, false])
        
        UserChangeInfo.remove(observer: token, for: observedUser)
    }
    
}

