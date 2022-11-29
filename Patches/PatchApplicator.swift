//
// Wire
// Copyright (C) 2022 Wire Swiss GmbH
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
            context.setPersistentStoreMetadata(currentVersion, key: lastRunPatchVersion)
            context.saveOrRollback()
        }
        
        // Get the previous version
        guard let previousVersion = context.persistentStoreMetadata(forKey: lastRunPatchVersion) as? Int
        else {
            // no version was run, this is a fresh install, skipping...
            zmLog.info("no version was run, this is a fresh install, skipping...")
            return
        }
        
        zmLog.info("previousVersion\(previousVersion)")
        T.allCases
            .filter { $0.version > previousVersion }
            .forEach {
            $0.execute(in: context)
        }
    }
}

let lastRunPatchVersion = "zm_PatchApplicatorLastRunPatchVersion"

protocol DataPatchInterface: CaseIterable {
    
    var version: Int { get }
    func execute(in context: NSManagedObjectContext)
    
}

enum DataPatch: Int, DataPatchInterface {
    
    // Add patches as cases
    case patch1
    
    var version: Int {
        return rawValue
    }
    
    func execute(in context: NSManagedObjectContext) {
        //Execute production patch
        
        switch self {
        case .patch1: break
        }
    }
}
