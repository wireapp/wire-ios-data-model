//
//  PersistedDataPatches.swift
//  WireDataModel
//
//  Created by John Ranjith on 11/21/22.
//  Copyright © 2022 Wire Swiss GmbH. All rights reserved.
//

import Foundation
import CoreData

private let zmLog = ZMSLog(tag: "Patches")

enum PatchApplicator {
    
    static func apply<T: DataPatchInterface>(
        _ patchType: T.Type,
        in context: NSManagedObjectContext
    ) {
        // Get the current version
        let currentVersion = T.allCases.count
    
        defer {
            context.setPersistentStoreMetadata(currentVersion, key: "lastRunPatchVersion")
            context.saveOrRollback()
        }
        
        // Get the previous version
        guard let previousVersion = context.persistentStoreMetadata(forKey: "lastRunPatchVersion") as? Int else {
            // no version was run, this is a fresh install, skipping...
            return
        }
        
        T.allCases.filter { $0.version > previousVersion }.forEach {
            $0.execute(in: context)
        }
    }
}

let lastRunPatchVersion = "zm_lastDataModelVersionKeyThatWasPatched"

protocol DataPatchInterface:CaseIterable {
    
    var version: Int { get }
    func execute(in context: NSManagedObjectContext)
    
}

enum Patch: Int, DataPatchInterface {
    
    case firstPatch
    case secondPatch
    
    var version: Int {
        return rawValue
    }
    
    func execute(in context: NSManagedObjectContext) {
        //Execute production patch
    }
}

struct TestPatch: DataPatchInterface {
    static var allCases = [TestPatch]()
    
    var version: Int
    func execute(in context: NSManagedObjectContext) {
        //Execute test patch
        print("executing test patch")
    }
}
