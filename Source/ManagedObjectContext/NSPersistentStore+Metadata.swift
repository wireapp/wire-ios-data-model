//
// Wire
// Copyright (C) 2016 Wire Swiss GmbH
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

// MARK: - Public accessors

@objc(ZMPersistableMetadata) public protocol PersistableInMetadata : NSObjectProtocol {
}

extension NSString : PersistableInMetadata {}
extension NSNumber : PersistableInMetadata {}

public protocol SwiftPersistableInMetadata {}
extension String : SwiftPersistableInMetadata {}

extension NSManagedObjectContext {
    
    /// Fetch metadata for key from in-memory non-persisted metadata
    /// or from persistent store metadata, in that order
    @objc(persistentStoreMetadataForKey:) public func persistentStoreMetadata(key: String) -> Any? {
        
        let store = self.persistentStoreCoordinator!.persistentStores.first!
        
        if let valueInMetadata = self.nonCommittedMetadata[key] {
            return valueInMetadata
        }
        
        if self.nonCommitedDeletedMetadataKeys.contains(key) {
            return nil
        }
        
        if let storedValue = self.persistentStoreCoordinator?.metadata(for: store)[key] {
            if storedValue is NSNull {
                return nil
            }
            return storedValue
        }
        return nil
    }
    
    @objc(setPersistentStoreMetadata:forKey:) public func setPersistentStoreMetadata(_ persistable: PersistableInMetadata?, key: String) {
        self.setPersistentStoreMetadata(data: persistable, key: key)
    }
    
    public func setPersistentStoreMetadata(_ data: SwiftPersistableInMetadata?, key: String) {
        self.setPersistentStoreMetadata(data: data, key: key)
    }
    
    public func setPersistentStoreMetadata<T: SwiftPersistableInMetadata>(array: [T], key: String) {
        self.setPersistentStoreMetadata(data: array as NSArray, key: key)
    }
}

// MARK: - Internal setters/getters

private let metadataKey = "ZMMetadataKey"
private let metadataKeysToRemove = "ZMMetadataKeysToRemove"

extension NSManagedObjectContext {
    
    /// Non-persisted store metadata
    fileprivate var nonCommittedMetadata : [String: Any] {
        get {
            return (self.userInfo[metadataKey] as? NSDictionary) as? [String: Any] ?? [:]
        }
    }
    
    /// Non-persisted deleted metadata (need to keep around to know what to remove
    /// from the store when persisting)
    fileprivate var nonCommitedDeletedMetadataKeys : Set<String> {
        get {
            return self.userInfo[metadataKeysToRemove] as? Set<String> ?? Set<String>()
        }
    }
    
    /// Discard non commited store metadata
    fileprivate func discardNonCommitedMetadata() {
        self.userInfo[metadataKeysToRemove] = [String]()
        self.userInfo[metadataKey] = [String: Any]()
    }
    
    /// Persist in-memory metadata to persistent store
    @objc func makeMetadataPersistent() {
        
        let store = self.persistentStoreCoordinator!.persistentStores.first!
        var storedMetadata = self.persistentStoreCoordinator!.metadata(for: store)
        
        // remove keys
        self.nonCommitedDeletedMetadataKeys.forEach { storedMetadata.removeValue(forKey: $0) }
        
        // set keys
        self.nonCommittedMetadata.forEach { (key: String, value: Any) in
            storedMetadata[key] = value
        }
        
        self.persistentStoreCoordinator?.setMetadata(storedMetadata, for: store)
        self.discardNonCommitedMetadata()
    }
    
    /// Remove key from keys that are deleted
    fileprivate func removeFromNonCommittedDeteledMetadataKeys(key: String) {
        var deletedKeys = self.nonCommitedDeletedMetadataKeys
        deletedKeys.remove(key)
        self.userInfo[metadataKeysToRemove] = deletedKeys
    }
    
    /// Add a key to the keys that are deleted
    fileprivate func addNonCommittedDeletedMetadataKey(key: String) {
        var deletedKeys = self.nonCommitedDeletedMetadataKeys
        deletedKeys.insert(key)
        self.userInfo[metadataKeysToRemove] = deletedKeys
    }
    
    /// Set a value in the metadata for the store. The value won't be persisted until the metadata is persisted
    fileprivate func setPersistentStoreMetadata(data: Any?, key: String) {
        var metadata = self.nonCommittedMetadata
        if let data = data {
            self.removeFromNonCommittedDeteledMetadataKeys(key: key)
            metadata[key] = data
        } else {
            self.addNonCommittedDeletedMetadataKey(key: key)
            metadata.removeValue(forKey: key)
        }
        self.userInfo[metadataKey] = metadata
    }
}
