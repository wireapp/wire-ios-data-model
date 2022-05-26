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

    override func setUp() {
        super.setUp()
        deleteFeatureIfNeeded(name: .mls)
    }

    func deleteFeatureIfNeeded(name: Feature.Name) {
        syncMOC.performAndWait {
            if let feature = Feature.fetch(name: name, context: self.syncMOC) {
                self.syncMOC.delete(feature)
            }
        }
    }

    // MARK: - MLS

    func testThatItFetchesMLS() {
        syncMOC.performGroupedBlock {
            // Given
            let sut = FeatureService(context: self.syncMOC)

            let config = Feature.MLS.Config(
                protocolToggleUsers: [.create()],
                defaultProtocol: .mls,
                allowedCipherSuites: [.MLS_128_DHKEMP256_AES128GCM_SHA256_P256],
                defaultCipherSuite: .MLS_256_DHKEMX448_AES256GCM_SHA512_Ed448
            )

            Feature.updateOrCreate(havingName: .mls, in: self.syncMOC) { feature in
                feature.status = .enabled
                feature.config = try! JSONEncoder().encode(config)
            }

            // When
            let result = sut.fetchMLS()

            // Then
            XCTAssertEqual(result.status, .enabled)
            XCTAssertEqual(result.config, config)
        }

        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }

    func testThatItFetchesMLS_ItReturnsADefaultConfigWhenConfigDoesNotExist() {
        syncMOC.performGroupedBlock {
            // Given
            let sut = FeatureService(context: self.syncMOC)

            Feature.updateOrCreate(havingName: .mls, in: self.syncMOC) { feature in
                feature.status = .enabled
                feature.config = nil
            }

            // When
            let result = sut.fetchMLS()

            // Then
            XCTAssertEqual(result.status, .disabled)
            XCTAssertEqual(result.config, .init())
        }

        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }

    func testThatItFetchesMLS_ItReturnsADefaultConfigWhenObjectDoesNotExist() {
        syncMOC.performGroupedBlock {
            // Given
            let sut = FeatureService(context: self.syncMOC)
            XCTAssertNil(Feature.fetch(name: .mls, context: self.syncMOC))

            // When
            let result = sut.fetchMLS()

            // Then
            XCTAssertEqual(result.status, .disabled)
            XCTAssertEqual(result.config, .init())
        }

        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }

    func testThatItStoresMLS() {
        syncMOC.performGroupedBlock {
            // Given
            let sut = FeatureService(context: self.syncMOC)

            let config = Feature.MLS.Config(
                protocolToggleUsers: [.create()],
                defaultProtocol: .mls,
                allowedCipherSuites: [.MLS_128_DHKEMP256_AES128GCM_SHA256_P256],
                defaultCipherSuite: .MLS_256_DHKEMX448_AES256GCM_SHA512_Ed448
            )

            let mls = Feature.MLS(
                status: .enabled,
                config: config
            )

            XCTAssertNil(Feature.fetch(name: .mls, context: self.syncMOC))

            // When
            sut.storeMLS(mls)

            // Then
            guard let feature = Feature.fetch(name: .mls, context: self.syncMOC) else {
                XCTFail("feature not found")
                return
            }

            guard let configData = feature.config else {
                XCTFail("expected config data")
                return
            }

            guard let featureConfig = configData.decode(as: Feature.MLS.Config.self) else {
                XCTFail("failed to decode config data")
                return
            }

            XCTAssertEqual(feature.status, .enabled)
            XCTAssertEqual(featureConfig, config)
        }

        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }

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
        syncMOC.performGroupedAndWait { _ in
            sut.storeAppLock(appLock)
        }

        // Then
        syncMOC.performGroupedAndWait { context -> Void in
            guard let result = Feature.fetch(name: .appLock, context: context) else { return XCTFail() }
            XCTAssertEqual(result.status, appLock.status)
            XCTAssertEqual(result.config, appLock.configData)
        }
    }

    func testItCreatesADefaultInstance() throws {
        // Given
        let sut = FeatureService(context: syncMOC)

        syncMOC.performGroupedAndWait { context in
            if let existingDefault = Feature.fetch(name: .appLock, context: context) {
                context.delete(existingDefault)
            }

            XCTAssertNil(Feature.fetch(name: .appLock, context: context))
        }

        // When
        syncMOC.performGroupedAndWait { _ in
            sut.createDefaultConfigsIfNeeded()
        }

        // Then
        syncMOC.performGroupedAndWait { context in
            XCTAssertNotNil(Feature.fetch(name: .appLock, context: context))
        }
    }

}

private extension Feature.AppLock {

    var configData: Data {
        return try! JSONEncoder().encode(config)
    }

}

private extension Data {

    func decode<T: Decodable>(as type: T.Type) -> T? {
        return try? JSONDecoder().decode(type, from: self)
    }

}
