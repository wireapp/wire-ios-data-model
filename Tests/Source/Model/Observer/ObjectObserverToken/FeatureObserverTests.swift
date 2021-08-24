//
// Wire
// Copyright (C) 2021 Wire Swiss GmbH
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

class TestFeatureObserver : NSObject, FeatureObserver {

    var notifications = [Feature.FeatureChangeInfo]()

    func clearNotifications(){
        notifications = []
    }

    func featureDidChange(_ changeInfo: Feature.FeatureChangeInfo) {
        notifications.append(changeInfo)
    }
}

final class FeatureObserverTests: NotificationDispatcherTestBase {
    var observer : TestFeatureObserver!

    override func setUp() {
        super.setUp()
        observer = TestFeatureObserver()
    }

    override func tearDown() {
        observer = nil
        super.tearDown()
    }

    var userInfoKeys : Set<String> {
        return [
            #keyPath(Feature.FeatureChangeInfo.statusChanged),
            #keyPath(Feature.FeatureChangeInfo.configChanged)
        ]
    }

    func checkThatItNotifiesTheObserverOfAChange(_ feature : Feature,
                                                 modifier: (Feature) -> Void,
                                                 expectedChangedFields: Set<String>,
                                                 customAffectedKeys: AffectedKeys? = nil,
                                                 file: StaticString = #file,
                                                 line: UInt = #line) {

        // given
        uiMOC.saveOrRollback()

        self.token = Feature.addObserver(observer, in: self.uiMOC)

        // when
        modifier(feature)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        self.uiMOC.saveOrRollback()

        // then
        let changeCount = observer.notifications.count
        if !expectedChangedFields.isEmpty {
            XCTAssertEqual(changeCount, 1, "Observer expected 1 notification, but received \(changeCount).", file: file, line: line)
        } else {
            XCTAssertEqual(changeCount, 0, "Observer was notified, but DID NOT expect a notification", file: file, line: line)
        }

        // and when
        self.uiMOC.saveOrRollback()

        // then
        XCTAssertEqual(observer.notifications.count, changeCount, "Should not have changed further once")

        guard let changes = observer.notifications.first else { return }
        changes.checkForExpectedChangeFields(userInfoKeys: userInfoKeys,
                                             expectedChangedFields: expectedChangedFields,
                                             file: file,
                                             line: line)
    }

    func testThatItNotifiesTheObserverOfChangedStatus() {
        // given
        let feature = Feature.insertNewObject(in: uiMOC)
        feature.name = .conferenceCalling
        feature.status = .enabled
        uiMOC.saveOrRollback()

        // when
        self.checkThatItNotifiesTheObserverOfAChange(feature,
                                                     modifier: { $0.status =  .disabled},
                                                     expectedChangedFields: [#keyPath(Feature.FeatureChangeInfo.statusChanged)]
        )
    }

    func testThatItNotifiesTheObserverOfChangedConfig() {
        // given
        let feature = Feature.insertNewObject(in: uiMOC)
        feature.name = .appLock
        feature.status = .enabled
        let config = Feature.AppLock.Config()
        feature.config = try! JSONEncoder().encode(config)
        uiMOC.saveOrRollback()

        // when
        let newConfig = Feature.AppLock.Config(enforceAppLock: true, inactivityTimeoutSecs: 70)
        self.checkThatItNotifiesTheObserverOfAChange(feature,
                                                     modifier: {
                                                        $0.config = try! JSONEncoder().encode(newConfig) },
                                                     expectedChangedFields: [#keyPath(Feature.FeatureChangeInfo.configChanged)]
        )
    }

}
