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

// TODO Sabine: Pass in snapshots to get previous values

protocol SideEffectSource {
    
    /// Returns a map of objects and keys that are affected by an update and it's resulting changedValues mapped by classIdentifier
    /// [classIdentifier : [affectedObject: changedKeys]]
    func affectedObjectsAndKeys(keyStore: DependencyKeyStore, knownKeys: Set<String>) -> [ClassIdentifier: ObjectAndChanges]
    
    /// Returns a map of objects and keys that are affected by an insert or deletion mapped by classIdentifier
    /// [classIdentifier : [affectedObject: changedKeys]]
    func affectedObjectsForInsertionOrDeletion(keyStore: DependencyKeyStore) -> [ClassIdentifier: ObjectAndChanges]
}


extension ZMManagedObject {
    
    /// Returns a map of [classIdentifier : [affectedObject: changedKeys]]
    func byInsertOrDeletionAffectedKeys(for object: ZMManagedObject?, keyStore: DependencyKeyStore, affectedKey: String) -> [ClassIdentifier: ObjectAndChanges] {
        guard let object = object else { return [:] }
        let classIdentifier = type(of:object).entityName()
        return [classIdentifier : [object : Changes(changedKeys: keyStore.keyPathsAffectedByValue(classIdentifier, key: affectedKey))]]
    }
    
    /// Returns a map of [classIdentifier : [affectedObject: changedKeys]]
    func byUpdateAffectedKeys(for object: ZMManagedObject?,
                              knownKeys: Set<String>,
                              keyStore: DependencyKeyStore,
                              originalChangeKey: String? = nil,
                              keyMapping: ((String) -> String)) -> [ClassIdentifier: ObjectAndChanges]
    {
        guard let object = object else { return [:]}
        let classIdentifier = type(of: object).entityName()
        
        var changes = changedValues()
        guard changes.count > 0 || knownKeys.count > 0 else { return [:] }
        let allKeys = knownKeys.union(changes.keys)
        
        let mappedKeys : [String] = Array(allKeys).map(keyMapping)
        let keys = mappedKeys.map{keyStore.keyPathsAffectedByValue(classIdentifier, key: $0)}.reduce(Set()){$0.union($1)}
        guard keys.count > 0 || originalChangeKey != nil else { return [:] }
        
        var originalChanges = [String : NSObject?]()
        if let originalChangeKey = originalChangeKey {
            let requiredKeys = keyStore.requiredKeysForIncludingRawChanges(classIdentifier: classIdentifier, for: self)
            knownKeys.forEach {
                if changes[$0] == nil {
                    changes[$0] = .none as Optional<NSObject>
                }
            }
            if requiredKeys.count == 0 || !requiredKeys.isDisjoint(with: changes.keys) {
                originalChanges = [originalChangeKey : [self : changes] as Optional<NSObject>]
            }
        }
        return [classIdentifier : [object: Changes(changedKeys: keys, originalChanges: originalChanges)]]
    }
}


extension ZMUser : SideEffectSource {
    
    var allConversations : [ZMConversation] {
        var conversations = activeConversations.array as? [ZMConversation] ?? []
        if let connectedConversation = connection?.conversation {
            conversations.append(connectedConversation)
        }
        return conversations
    }
    
    func affectedObjectsAndKeys(keyStore: DependencyKeyStore, knownKeys: Set<String>) -> [ClassIdentifier: ObjectAndChanges] {
        let changes = changedValues()
        guard changes.count > 0 || knownKeys.count > 0 else { return [:] }
        
        let allKeys = knownKeys.union(changes.keys)

        let conversations = allConversations
        guard conversations.count > 0 else { return  [:] }
        
        let affectedObjects = conversationChanges(changedKeys: allKeys, conversations:conversations, keyStore:keyStore)
        return affectedObjects
    }
    
    func conversationChanges(changedKeys: Set<String>, conversations: [ZMConversation], keyStore: DependencyKeyStore) -> [ClassIdentifier: ObjectAndChanges] {
        var affectedObjects = [String: [NSObject : Changes]]()
        let classIdentifier = ZMConversation.entityName()
        let otherPartKeys = changedKeys.map{"otherActiveParticipants.\($0)"}
        let selfUserKeys = changedKeys.map{"connection.to.\($0)"}
        let mappedKeys = otherPartKeys + selfUserKeys
        var keys = mappedKeys.map{keyStore.keyPathsAffectedByValue(classIdentifier, key: $0)}.reduce(Set()){$0.union($1)}
        
        affectedObjects[classIdentifier] = [:]
        conversations.forEach {
            if $0.allUsersTrusted {
                keys.insert(SecurityLevelKey)
            }
            if keys.count > 0 {
                affectedObjects[classIdentifier]![$0] = Changes(changedKeys: keys)
            }
        }
        return affectedObjects
    }
    
    func affectedObjectsForInsertionOrDeletion(keyStore: DependencyKeyStore) -> [ClassIdentifier: ObjectAndChanges] {
        let conversations = allConversations
        guard conversations.count > 0 else { return  [:] }
        
        let classIdentifier = ZMConversation.entityName()
        return [classIdentifier: Dictionary(keys: conversations,
                                            repeatedValue: Changes(changedKeys: keyStore.keyPathsAffectedByValue(classIdentifier, key: "otherActiveParticipants")))]
    }
}

extension ZMMessage : SideEffectSource {
    
    func affectedObjectsAndKeys(keyStore: DependencyKeyStore, knownKeys: Set<String>) -> [ClassIdentifier: ObjectAndChanges] {
        return [:]
    }
    
    func affectedObjectsForInsertionOrDeletion(keyStore: DependencyKeyStore) -> [ClassIdentifier: ObjectAndChanges] {
        return byInsertOrDeletionAffectedKeys(for: conversation, keyStore: keyStore, affectedKey: "messages")
    }
}

extension ZMConnection : SideEffectSource {
    
    func affectedObjectsAndKeys(keyStore: DependencyKeyStore, knownKeys: Set<String>) -> [ClassIdentifier: ObjectAndChanges] {
        let conversationChanges = byUpdateAffectedKeys(for: conversation, knownKeys:knownKeys, keyStore: keyStore, keyMapping: {"connection.\($0)"})
        let userChanges = byUpdateAffectedKeys(for: to, knownKeys:knownKeys, keyStore: keyStore, keyMapping: {"connection.\($0)"})
        return conversationChanges.updated(other: userChanges)
    }
    
    func affectedObjectsForInsertionOrDeletion(keyStore: DependencyKeyStore) -> [ClassIdentifier: ObjectAndChanges] {
        return [:]
    }
}


extension UserClient : SideEffectSource {
    
    func affectedObjectsAndKeys(keyStore: DependencyKeyStore, knownKeys: Set<String>) -> [ClassIdentifier: ObjectAndChanges] {
        return byUpdateAffectedKeys(for: user, knownKeys:knownKeys, keyStore: keyStore, originalChangeKey: "clientChanges", keyMapping: {"clients.\($0)"})
    }
    
    func affectedObjectsForInsertionOrDeletion(keyStore: DependencyKeyStore) -> [ClassIdentifier: ObjectAndChanges] {
        return byInsertOrDeletionAffectedKeys(for: user, keyStore: keyStore, affectedKey: "clients")
    }
}

extension Reaction : SideEffectSource {

    func affectedObjectsAndKeys(keyStore: DependencyKeyStore, knownKeys: Set<String>) -> [ClassIdentifier: ObjectAndChanges] {
        return byUpdateAffectedKeys(for: message, knownKeys:knownKeys, keyStore: keyStore, originalChangeKey: "reactionChanges", keyMapping: {"reactions.\($0)"})
    }
    
    func affectedObjectsForInsertionOrDeletion(keyStore: DependencyKeyStore) -> [ClassIdentifier: ObjectAndChanges] {
        return byInsertOrDeletionAffectedKeys(for: message, keyStore: keyStore, affectedKey: "reactions")
    }
}

extension ZMGenericMessageData : SideEffectSource {
    
    func affectedObjectsAndKeys(keyStore: DependencyKeyStore, knownKeys: Set<String>) -> [ClassIdentifier: ObjectAndChanges] {
        return byUpdateAffectedKeys(for: message ?? asset, knownKeys:knownKeys, keyStore: keyStore, keyMapping: {"dataSet.\($0)"})
    }
    
    func affectedObjectsForInsertionOrDeletion(keyStore: DependencyKeyStore) -> [ClassIdentifier: ObjectAndChanges] {
        return byInsertOrDeletionAffectedKeys(for: message ?? asset, keyStore: keyStore, affectedKey: "dataSet")
    }
}
