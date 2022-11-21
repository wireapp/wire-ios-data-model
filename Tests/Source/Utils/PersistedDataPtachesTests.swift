//
//  PersistedDataPtaches.swift
//  WireDataModel
//
//  Created by John Ranjith on 11/21/22.
//  Copyright © 2022 Wire Swiss GmbH. All rights reserved.
//

import Foundation
import XCTest
@testable import WireDataModel
import CoreData

class PersistedDataPatchTests: ZMBaseManagedObjectTest {

    func testProductionPatch() {
        
    }
    
    func testPatch() {
        self.syncMOC.performGroupedBlockAndWait {
            PatchApplicator.apply(TestPatch.self, in: self.syncMOC)
        }
    }
    
    func testMultiplePatch() {
        self.syncMOC.performGroupedBlockAndWait {
            TestPatch.allCases.append(TestPatch.init(version: 1))
            TestPatch.allCases.append(TestPatch.init(version: 2))
            TestPatch.allCases.append(TestPatch.init(version: 3))
            TestPatch.allCases.append(TestPatch.init(version: 4))
            PatchApplicator.apply(TestPatch.self, in: self.syncMOC)
        }
    }
}
