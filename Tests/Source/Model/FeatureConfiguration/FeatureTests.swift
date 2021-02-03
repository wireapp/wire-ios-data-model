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

    func testThatItCreatesFeature() {
        syncMOC.performGroupedAndWait { context in
            // given
            let team = self.createTeam(in: context)

            // when
            let feature = Feature.createOrUpdate(name: .appLock,
                                                 status: .enabled,
                                                 config: self.configData(enforced: false),
                                                 team: team,
                                                 context: context)
            // then
            let fetchedFeature = Feature.fetch(name: .appLock, context: context)
            XCTAssertEqual(feature, fetchedFeature)
            XCTAssertEqual(feature.team?.remoteIdentifier, team.remoteIdentifier!)
        }
    }
    
    func testThatItUpdatesFeature() {
        syncMOC.performGroupedAndWait { context in
            // given
            let team = self.createTeam(in: context)

            let feature = Feature.insert(name: .appLock,
                                         status: .enabled,
                                         config: self.configData(enforced: false),
                                         team: team,
                                         context: context)
            XCTAssertEqual(feature.status, .enabled)

            // when
            let _ = Feature.createOrUpdate(name: .appLock,
                                           status: .disabled,
                                           config: self.configData(enforced: false),
                                           team: team,
                                           context: context)

            // then
            XCTAssertEqual(feature.status, .disabled)
        }
    }
    
    func testThatItFetchesFeature() {
        syncMOC.performGroupedAndWait { context in
            // given
            let team = self.createTeam(in: context)

            let _ = Feature.createOrUpdate(name: .appLock,
                                           status: .enabled,
                                           config: self.configData(enforced: false),
                                           team: team,
                                           context: context)


            // when
            let fetchedFeature = Feature.fetch(name: .appLock, context: context)

            // then
            XCTAssertNotNil(fetchedFeature)
        }
    }
    
    func testThatItUpdatesNeedsToNotifyUserFlag_IfAppLockBecameForced() {
        syncMOC.performGroupedAndWait { context in
            // given
            let team = self.createTeam(in: context)
            let oldConfigData = self.configData(enforced: false)
            let decoder = JSONDecoder()
            let feature = Feature.insert(name: .appLock,
                                         status: .enabled,
                                         config: oldConfigData,
                                         team: team,
                                         context: context)

            let oldConfig = try? decoder.decode(Feature.AppLock.Config.self, from: oldConfigData)
            XCTAssertFalse(oldConfig!.enforceAppLock)

            XCTAssertFalse(feature.needsToNotifyUser)

            // when
            let newConfigData = self.configData(enforced: true)
            let _ = Feature.createOrUpdate(name: .appLock,
                                           status: .enabled,
                                           config: newConfigData,
                                           team: team,
                                           context: context)

            let newConfig = try? decoder.decode(Feature.AppLock.Config.self, from: newConfigData)
            XCTAssertTrue(newConfig!.enforceAppLock)

            let fetchedFeature = Feature.fetch(name: .appLock, context: context)

            // then
            XCTAssertTrue(fetchedFeature!.needsToNotifyUser)
        }
    }
    
    func testThatItUpdatesNeedsToNotifyUserFlag_IfAppLockBecameNonForced() {
        syncMOC.performGroupedAndWait { context in
            // given
            let team = self.createTeam(in: context)
            let oldConfigData = self.configData(enforced: true)
            let decoder = JSONDecoder()
            let feature = Feature.insert(name: .appLock,
                                         status: .enabled,
                                         config: oldConfigData,
                                         team: team,
                                         context: context)

            let oldConfig = try? decoder.decode(Feature.AppLock.Config.self, from: oldConfigData)
            XCTAssertTrue(oldConfig!.enforceAppLock)

            XCTAssertFalse(feature.needsToNotifyUser)

            // when
            let newConfigData = self.configData(enforced: false)
            let _ = Feature.createOrUpdate(name: .appLock,
                                           status: .enabled,
                                           config: newConfigData,
                                           team: team,
                                           context: context)

            let newConfig = try? decoder.decode(Feature.AppLock.Config.self, from: newConfigData)
            XCTAssertFalse(newConfig!.enforceAppLock)

            let fetchedFeature = Feature.fetch(name: .appLock, context: context)

            // then
            XCTAssertTrue(fetchedFeature!.needsToNotifyUser)
        }
    }
}

// MARK: - Helpers
extension FeatureTests {
    func configData(enforced: Bool) -> Data {
        return {
          let json = """
          {
            "enforceAppLock": \(enforced),
            "inactivityTimeoutSecs": 30
          }
          """

          return json.data(using: .utf8)!
        }()
    }
}
