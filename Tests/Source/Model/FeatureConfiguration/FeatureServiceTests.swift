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

class FeatureServiceTests: ZMBaseManagedObjectTest {

    func testThatItStoresAppLockFeature() {
        // Given
        let sut = FeatureService(context: syncMOC)
        let appLock = Feature.AppLock(status: .disabled, config: .init(enforceAppLock: true, inactivityTimeoutSecs: 10))

        syncMOC.performGroupedAndWait { context -> Void in
            guard let existing = Feature.fetch(name: .appLock, context: context) else { return XCTFail() }
            XCTAssertNotEqual(existing.status, appLock.status)
            XCTAssertNotEqual(existing.config, appLock.configData)
        }

        // When
        syncMOC.performGroupedAndWait { context in
            sut.storeAppLock(appLock)
        }

        // Then
        syncMOC.performGroupedAndWait { context -> Void in
            guard let result = Feature.fetch(name: .appLock, context: context) else { return XCTFail() }
            XCTAssertEqual(result.status, appLock.status)
            XCTAssertEqual(result.config, appLock.configData)
        }
    }

    func testThatItStoresDigitalSignature() {
        // GIVEN
        let sut = FeatureService(context: syncMOC)
        let digitalSignature = Feature.DigitalSignature(status: .enabled)

        syncMOC.performGroupedAndWait { context -> Void in
            guard let existing = Feature.fetch(name: .digitalSignature, context: context) else { return XCTFail() }
            XCTAssertNotEqual(existing.status, digitalSignature.status)
        }

        // WHEN
        syncMOC.performGroupedAndWait { context in
            sut.storeDigitalSignature(digitalSignature)
        }

        //THEN
        syncMOC.performGroupedAndWait { context -> Void in
            guard let result = Feature.fetch(name: .digitalSignature, context: context) else { return XCTFail() }
            XCTAssertEqual(result.status, digitalSignature.status)
    }
    }

    func testItCreatesADefaultInstance() throws {
        // Given
        let sut = FeatureService(context: syncMOC)

        syncMOC.performGroupedAndWait { context in
            if let existingDefault = Feature.fetch(name: .appLock, context: context) {
                context.delete(existingDefault)
            }

            if let existingDefaultForDigitalSignature = Feature.fetch(name: .digitalSignature, context: context) {
                context.delete(existingDefaultForDigitalSignature)
            }

            XCTAssertNil(Feature.fetch(name: .appLock, context: context))
            XCTAssertNil(Feature.fetch(name: .digitalSignature, context: context))
        }

        // When
        syncMOC.performGroupedAndWait { context in
            sut.createDefaultConfigsIfNeeded()
        }

        // Then
        syncMOC.performGroupedAndWait { context in
            XCTAssertNotNil(Feature.fetch(name: .appLock, context: context))
            XCTAssertNotNil(Feature.fetch(name: .digitalSignature, context: context))

        }
    }

    func testItEnqueuesBackendRefreshForFeature() {
        // Given
        let sut = FeatureService(context: syncMOC)

        syncMOC.performGroupedAndWait { context -> Void in
            guard let feature = Feature.fetch(name: .appLock, context: context) else { return XCTFail() }
            XCTAssertFalse(feature.needsToBeUpdatedFromBackend)

            guard let digitalSignatureFeature = Feature.fetch(name: .digitalSignature, context: context) else { return XCTFail() }
            XCTAssertFalse(digitalSignatureFeature.needsToBeUpdatedFromBackend)
        }

        // When
        syncMOC.performGroupedAndWait { context in
            sut.enqueueBackendRefresh(for: .appLock)
            sut.enqueueBackendRefresh(for: .digitalSignature)
        }

        // Then
        syncMOC.performGroupedAndWait { context -> Void in
            guard let feature = Feature.fetch(name: .appLock, context: context) else { return XCTFail() }
            XCTAssertTrue(feature.needsToBeUpdatedFromBackend)

            guard let digitalSignatureFeature = Feature.fetch(name: .digitalSignature, context: context) else { return XCTFail() }
            XCTAssertTrue(digitalSignatureFeature.needsToBeUpdatedFromBackend)
        }
    }

}

private extension Feature.AppLock {

    var configData: Data {
        return try! JSONEncoder().encode(config)
    }

}
