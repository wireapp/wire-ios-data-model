//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
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
import XCTest
@testable import WireDataModel
import CoreData

private let zmLog = ZMSLog(tag: "PatchesTest")

struct TestPatch: DataPatchInterface {
    static var allCases = [TestPatch]()
    
    var version: Int
    
    /// The patch code
    let block: (NSManagedObjectContext)->()
    
    func execute(in context: NSManagedObjectContext) {
        //Execute test patch
        return block(context)
    }
        
    init(version: Int, block: @escaping (NSManagedObjectContext)->()) {
        self.version = version
        self.block = block
    }
}

class PatchApplicatorTests: ZMBaseManagedObjectTest {
    
    func testItAppliesNoPatchesWhenThereIsNoPreviousVersion() {
        syncMOC.performGroupedBlockAndWait {
            // Given some patches
            var patchApplied = [Int: Bool]()
            TestPatch.allCases = [
                TestPatch(version: 1, block: { _ in patchApplied[1] = true }),
                TestPatch(version: 2, block: { _ in patchApplied[2] = true }),
                TestPatch(version: 3, block: { _ in patchApplied[3] = true })
            ]
            
            // Given no previous version
            self.syncMOC.setPersistentStoreMetadata(Optional<Int>.none, key: lastRunPatchVersion)
            self.syncMOC.saveOrRollback()
            
            // When I apply some patches
            PatchApplicator.apply(TestPatch.self, in: self.syncMOC)
            
            zmLog.info("patchApplied \(patchApplied)")
            // Then no patches were run
            XCTAssertEqual(patchApplied, [:])
            
            // Then the current version is set as the previous version
            let previousVersion = self.syncMOC.persistentStoreMetadata(forKey: lastRunPatchVersion) as? Int
            XCTAssertEqual(previousVersion, 3)
        }
    }
    
    func testThatItDoesNotApplyRequiredPatch() {
        
        //Given a previous version as 2
        self.syncMOC.performGroupedBlockAndWait {
            self.syncMOC.setPersistentStoreMetadata(2, key: lastRunPatchVersion)
            self.syncMOC.saveOrRollback()
            
            //Given some patches of various verions
            var wasPatch1Executed = false
            let patch1 = TestPatch(version: 1) { (moc) in
                wasPatch1Executed = true
            }
            
            var wasPatch2Executed = false
            let patch2 = TestPatch(version: 2) { (moc) in
                wasPatch2Executed = true
            }
            
            var wasPatch3Executed = false
            let patch3 = TestPatch(version: 3) { (moc) in
                wasPatch3Executed = true
            }
            
            var wasPatch4Executed = false
            let patch4 = TestPatch(version: 4) { (moc) in
                wasPatch4Executed = true
            }
            
            var wasPatch5Executed = false
            let patch5 = TestPatch(version: 5) { (moc) in
                wasPatch5Executed = true
            }
            
            TestPatch.allCases = [patch1, patch2, patch3, patch4, patch5]
            
            // When I apply some patches
            PatchApplicator.apply(TestPatch.self, in: self.syncMOC)
            zmLog.info("wasPatch1Executed\(wasPatch1Executed)")
            zmLog.info("wasPatch2Executed\(wasPatch2Executed)")
            zmLog.info("wasPatch3Executed\(wasPatch3Executed)")
            zmLog.info("wasPatch4Executed\(wasPatch4Executed)")
            zmLog.info("wasPatch5Executed\(wasPatch5Executed)")
            
            let updatedCurrentVersion = self.syncMOC.persistentStoreMetadata(forKey: lastRunPatchVersion) as? Int
            zmLog.info("updatedCurrentVersion\(updatedCurrentVersion)")
            
            // Then
            XCTAssertFalse(wasPatch1Executed)
            XCTAssertFalse(wasPatch2Executed)
            XCTAssertTrue(wasPatch3Executed)
            XCTAssertTrue(wasPatch4Executed)
            XCTAssertTrue(wasPatch5Executed)
            
            // Then the current version is set as the previous version
            let previousVersion = self.syncMOC.persistentStoreMetadata(forKey: lastRunPatchVersion) as? Int
            XCTAssertEqual(previousVersion, 5)
            
        }
    }
    
    func testItAppliesFirstPatchSuccessfully() {
        
        self.syncMOC.performGroupedBlockAndWait {
            // Given no patches were run previously (previous version is 1)
            self.syncMOC.setPersistentStoreMetadata(0, key: lastRunPatchVersion)
            self.syncMOC.saveOrRollback()
        
            // When the first patch is added
            var wasPatch1Executed = false
            let patch1 = TestPatch(version: 1) { (moc) in
                wasPatch1Executed = true
            }
            
            TestPatch.allCases = [patch1]
            
            PatchApplicator.apply(TestPatch.self, in: self.syncMOC)
            zmLog.info("wasPatch1Executed\(wasPatch1Executed)")
            
            // Then previous version is 1
            let previousVersion = self.syncMOC.persistentStoreMetadata(forKey: lastRunPatchVersion) as? Int
            
            XCTAssertEqual(previousVersion, 1)
        }
    }
}
