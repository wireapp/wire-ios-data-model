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

struct TestPatch: DataPatchInterface {
    static var allCases = [TestPatch]()
    
    var version: Int
    
    /// The patch code
    let block: (NSManagedObjectContext)->()
    
    func execute(in context: NSManagedObjectContext) {
        //Execute test patch
        print("executing test patch")
    }
    init(version: Int, block: @escaping (NSManagedObjectContext)->()) {
        self.version = version
        self.block = block
    }
}

class PatchApplicatorTests: ZMBaseManagedObjectTest {

    func testThatItApplyPatchesWhenNoVersion() {
        // GIVEN
        var patchApplied = false
        let patch = TestPatch(version: 1) { (moc) in
            XCTFail()
            patchApplied = true
        }
        
        // WHEN
        self.syncMOC.performGroupedBlockAndWait {
            TestPatch.allCases = [patch]
            PatchApplicator.apply(TestPatch.self, in: self.syncMOC)
        }

        // THEN
        XCTAssertTrue(patchApplied)
    }
    
    func testThatItApplyPatchesWhenPreviousVersionIsLesser() {

        // GIVEN
        var patchApplied = false
        let patch = TestPatch(version: 1) { (moc) in
            XCTAssertEqual(moc, self.syncMOC)
            patchApplied = true
        }
        
        TestPatch.allCases = [patch]
        
        // this will bump last patched version to current version, which hopefully is less than 10000000.32.32
        self.syncMOC.performGroupedBlockAndWait {
            PatchApplicator.apply(TestPatch.self, in: self.syncMOC)
        }

        // WHEN
        self.syncMOC.performGroupedBlockAndWait {
            PatchApplicator.apply(TestPatch.self, in: self.syncMOC)
        }

        // THEN
        XCTAssertTrue(patchApplied)
    }

    func testThatItDoesNotApplyUnnecessarypatch() {
        
        self.syncMOC.performGroupedBlockAndWait {
            self.syncMOC.setPersistentStoreMetadata(5, key: "zm_lastDataModelVersionThatWasPatched")
        }
        
        var wasPatch1Executed = false
        let patch1 = TestPatch(version: 4) { (moc) in
            wasPatch1Executed = true
        }
        
        var wasPatch2Executed = false
        let patch2 = TestPatch(version: 5) { (moc) in
            wasPatch2Executed = true
        }
        
        var wasPatch3Executed = false
        let patch3 = TestPatch(version: 6) { (moc) in
            wasPatch3Executed = true
        }
        
        var wasPatch4Executed = false
        let patch4 = TestPatch(version: 7) { (moc) in
            wasPatch4Executed = true
        }
        
        TestPatch.allCases = [patch1, patch2, patch3, patch4]
        
        // When
        self.syncMOC.performGroupedBlockAndWait {
            PatchApplicator.apply(TestPatch.self, in: self.syncMOC)
        }
        // Then
            XCTAssertFalse(wasPatch1Executed)
            XCTAssertFalse(wasPatch2Executed)
            XCTAssertTrue(wasPatch3Executed)
            XCTAssertTrue(wasPatch4Executed)
    }
}
