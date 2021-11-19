//
// Wire
// Copyright (C) 2020 Wire Swiss GmbH
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

final class FeatureTests: ZMBaseManagedObjectTest {

    // MARK: - Tests

    func testThatItUpdatesFeature() {
        // GIVEN
        syncMOC.performGroupedAndWait { context in
            guard let defaultAppLock = Feature.fetch(name: .appLock, context: context) else {
                XCTFail()
                return
            }

            guard let defaultDigitalSignature = Feature.fetch(name: .digitalSignature, context: context) else {
                XCTFail()
                return
            }


            XCTAssertEqual(defaultAppLock.status, .enabled)
            XCTAssertEqual(defaultDigitalSignature.status, .disabled)

        }

        // WHEN
        syncMOC.performGroupedAndWait { context in
            Feature.updateOrCreate(havingName: .appLock, in: context) {
                $0.status = .disabled
            }

            Feature.updateOrCreate(havingName: .digitalSignature, in: context) {
                $0.status = .enabled
            }
        }

        // THEN
        syncMOC.performGroupedAndWait { context in
            let updatedAppLock = Feature.fetch(name: .appLock, context: context)
            XCTAssertEqual(updatedAppLock?.status, .disabled)

            let updatedDigitalSignature = Feature.fetch(name: .digitalSignature, context: context)
            XCTAssertEqual(updatedDigitalSignature?.status, .enabled)

        }
    }
    
    func testThatItFetchesFeature() {
        syncMOC.performGroupedAndWait { context in
            // WHEN
            let defaultAppLock = Feature.fetch(name: .appLock, context: context)
            let defaultDigitalSignature  = Feature.fetch(name: .digitalSignature, context: context)

            // THEN
            XCTAssertNotNil(defaultAppLock)
            XCTAssertNotNil(defaultDigitalSignature)
        }
    }

    func testThatItUpdatesNeedsToNotifyUserFlag_IfAppLockBecameForced() {
        // GIVEN
        syncMOC.performGroupedAndWait { context in
            Feature.updateOrCreate(havingName: .appLock, in: context) {
                $0.config = self.configData(enforced: false)
                $0.hasInitialDefault = false
            }
        }

        syncMOC.performGroupedAndWait { context in
            guard let feature = Feature.fetch(name: .appLock, context: context) else { return XCTFail() }
            XCTAssertFalse(feature.needsToNotifyUser)
            return
        }

        // when
        syncMOC.performGroupedAndWait { context in
            Feature.updateOrCreate(havingName: .appLock, in: context) {
                $0.config = self.configData(enforced: true)
            }
        }

        // then
        syncMOC.performGroupedAndWait { context in
            guard let feature = Feature.fetch(name: .appLock, context: context) else { return XCTFail() }
            XCTAssertTrue(feature.needsToNotifyUser)
            return
        }
    }
    
    func testThatItUpdatesNeedsToNotifyUserFlag_IfAppLockBecameNonForced() {
        // given
        syncMOC.performGroupedAndWait { context in
            Feature.updateOrCreate(havingName: .appLock, in: context) {
                $0.config = self.configData(enforced: true)
                $0.needsToNotifyUser = false
                $0.hasInitialDefault = false
            }
        }

        syncMOC.performGroupedAndWait { context in
            guard let feature = Feature.fetch(name: .appLock, context: context) else { return XCTFail() }
            XCTAssertFalse(feature.needsToNotifyUser)
            return
        }

        // when
        syncMOC.performGroupedAndWait { context in
            Feature.updateOrCreate(havingName: .appLock, in: context) {
                $0.config = self.configData(enforced: false)
            }
        }

        // then
        syncMOC.performGroupedAndWait { context in
            guard let feature = Feature.fetch(name: .appLock, context: context) else { return XCTFail() }
            XCTAssertTrue(feature.needsToNotifyUser)
            return
        }
    }

    func testThatItNotifiesAboutFeatureChanges() {
        // given
        syncMOC.performGroupedAndWait { context in
            let defaultConferenceCalling = Feature.fetch(name: .conferenceCalling, context: self.syncMOC)
            defaultConferenceCalling?.hasInitialDefault = false
            XCTAssertNotNil(defaultConferenceCalling)

            let defaultDigitalSignature = Feature.fetch(name: .digitalSignature, context: self.syncMOC)
            defaultDigitalSignature?.hasInitialDefault = false
            XCTAssertNotNil(defaultDigitalSignature)
        }

        // expect
        let expectation = self.expectation(description: "Notification fired")
        NotificationCenter.default.addObserver(forName: .featureDidChangeNotification, object: nil, queue: nil) { (note) in
            guard let object = note.object as? Feature.FeatureChange else { return }
            XCTAssertEqual(object, .conferenceCallingIsAvailable)
            expectation.fulfill()
        }

        // when
        syncMOC.performGroupedAndWait { context in
            Feature.updateOrCreate(havingName: .conferenceCalling, in: self.syncMOC) { (feature) in
                feature.needsToNotifyUser = false
                feature.status = .enabled

            }

            Feature.updateOrCreate(havingName: .digitalSignature, in: self.syncMOC) { (feature) in
                feature.needsToNotifyUser = false
                feature.status = .enabled

            }
        }


        // Then
        syncMOC.performGroupedAndWait { context in
            guard let feature = Feature.fetch(name: .conferenceCalling, context: context) else {
                XCTFail()
                return
            }

            guard let digitalSignatureFeature = Feature.fetch(name: .digitalSignature, context: context) else {
                XCTFail()
                return
            }

            XCTAssertTrue(feature.needsToNotifyUser)
            XCTAssertTrue(digitalSignatureFeature.needsToNotifyUser)
        }

        // then
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
    }

    func testThatItDoesNotNotifyAboutFeatureChanges_IfThePreviousValueIsDefault() {
        // given
        let testObserver = TestObserver(for: .featureDidChangeNotification)
        syncMOC.performGroupedAndWait { context in
            let defaultConferenceCalling = Feature.fetch(name: .conferenceCalling, context: self.syncMOC)
            XCTAssertNotNil(defaultConferenceCalling)
            XCTAssertTrue(defaultConferenceCalling!.hasInitialDefault)

            let defaultDigitalSignature = Feature.fetch(name: .digitalSignature, context: self.syncMOC)
            XCTAssertNotNil(defaultDigitalSignature)
            XCTAssertTrue(defaultDigitalSignature!.hasInitialDefault)
        }

        // when
        syncMOC.performGroupedAndWait { context in
            Feature.updateOrCreate(havingName: .conferenceCalling, in: self.syncMOC) { (feature) in
                feature.status = .enabled
            }

            Feature.updateOrCreate(havingName: .digitalSignature, in: self.syncMOC) { (feature) in
                feature.status = .enabled
            }
        }

        // then
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertTrue(testObserver.changes.isEmpty)
    }


    guard let digitalSignatureFeature = Feature.fetch(name: .digitalSignature, context: context) else {
        XCTFail()
        return
    }


    XCTAssertFalse(feature.needsToNotifyUser)
    XCTAssertFalse(digitalSignatureFeature.needsToNotifyUser)

    private class TestObserver: NSObject {
        var changes : [Feature.FeatureChange] = []
        
        init(for notificationName: Notification.Name) {
            super.init()

            NotificationCenter.default.addObserver(forName: notificationName, object: nil, queue: nil) { [weak self] (note) in
                guard let object = note.object as? Feature.FeatureChange else { return }
                self?.changes.append(object)
            }

        }
    }
}

// MARK: - Helpers
extension FeatureTests {

    func configData(enforced: Bool) -> Data {
        let json = """
          {
            "enforceAppLock": \(enforced),
            "inactivityTimeoutSecs": 30
          }
          """

        return json.data(using: .utf8)!
    }
}

extension Feature {

    @discardableResult
    static func insert(name: Name,
                       status: Status,
                       config: Data?,
                       context: NSManagedObjectContext) -> Feature {

        let feature = Feature.insertNewObject(in: context)
        feature.name = name
        feature.status = status
        feature.config = config
        return feature
    }

}
