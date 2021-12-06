//
// Wire
// Copyright (C) 2019 Wire Swiss GmbH
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

extension ZMConversation {
    
    ///Fetch all conversation that are marked as needsToCalculateUnreadMessages and calculate unread messages for them
    public static func calculateLastUnreadMessages(in managedObjectContext: NSManagedObjectContext) {
        let fetchRequest = sortedFetchRequest(with: predicateForConversationsNeedingToBeCalculatedUnreadMessages())
        
        let conversations = managedObjectContext.fetchOrAssert(request: fetchRequest) as? [ZMConversation]
        conversations?.forEach { $0.calculateLastUnreadMessages() }
    }
    
    @objc(unreadConversationCountInContext:)
    public static func unreadConversationCount(in context: NSManagedObjectContext) -> UInt {
        let request = NSFetchRequest<ZMConversation>(entityName: ZMConversation.entityName())
        request.predicate = predicateForConversationConsideredUnread()
        
        return UInt((try? context.count(for: request)) ?? 0)
    }
    
    @objc(unreadConversationCountExcludingSilencedInContext:excluding:)
    static func unreadConversationCountExcludingSilenced(in context: NSManagedObjectContext,
                                                         excluding conversation: ZMConversation?) -> UInt {
        let excludedConversationPredicate = NSPredicate(format: "SELF != %@",
                                                        argumentArray: [conversation ?? NSNull()])
        let request = NSFetchRequest<ZMConversation>(entityName: ZMConversation.entityName())
        
        let predicates = [excludedConversationPredicate, predicateForConversationConsideredUnreadExcludingSilenced()]
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        
        return UInt((try? context.count(for: request)) ?? 0)
    }
    
    public static func predicateForConversationConsideredUnread() -> NSPredicate {
        let notSelfConversation = NSPredicate(format: "%K != %d", argumentArray: [ZMConversationConversationTypeKey, ZMConversationType.`self`.rawValue])
        let notInvalidConversation = NSPredicate(format: "%K != %d", argumentArray: [ZMConversationConversationTypeKey, ZMConversationType.invalid.rawValue])
        
        let pendingConnection = NSPredicate(format: "%K != nil AND %K.status == %d", argumentArray: [ZMConversationConnectionKey, ZMConversationConnectionKey, ZMConnectionStatus.pending.rawValue])
        
        let acceptablePredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [pendingConnection, predicateForUnreadConversation()])
        
        let notBlockedConnection = NSPredicate(format: "(%K == nil) OR (%K != nil AND %K.status != %d)", argumentArray: [ZMConversationConnectionKey, ZMConversationConnectionKey, ZMConversationConnectionKey, ZMConnectionStatus.blocked.rawValue])
        
        return NSCompoundPredicate(andPredicateWithSubpredicates: [notSelfConversation, notInvalidConversation, notBlockedConnection, acceptablePredicate])
    }
    
    static func predicateForUnreadConversation() -> NSPredicate {
        let notifyAllPredicate = NSPredicate(format: "%K == %lu", argumentArray: [ZMConversationMutedStatusKey, MutedMessageOptionValue.none.rawValue])
        let notifyMentionsAndRepliesPredicate = NSPredicate(format: "%K < %lu", argumentArray: [ZMConversationMutedStatusKey, MutedMessageOptionValue.mentionsAndReplies.rawValue])
        let unreadMentionsOrReplies = NSPredicate(format: "%K > 0 OR %K > 0", argumentArray: [ZMConversation.ZMConversationInternalEstimatedUnreadSelfMentionCountKey, ZMConversation.ZMConversationInternalEstimatedUnreadSelfReplyCountKey])
        let unreadMessages = NSPredicate(format: "%K > 0", argumentArray: [ZMConversation.ZMConversationInternalEstimatedUnreadCountKey])
        let notifyAllAndHasUnreadMessages = NSCompoundPredicate(andPredicateWithSubpredicates: [notifyAllPredicate, unreadMessages])
        let notifyMentionsAndRepliesAndHasUnreadMentionsOrReplies = NSCompoundPredicate(andPredicateWithSubpredicates: [notifyMentionsAndRepliesPredicate, unreadMentionsOrReplies])
        
        return NSCompoundPredicate(orPredicateWithSubpredicates: [notifyAllAndHasUnreadMessages, notifyMentionsAndRepliesAndHasUnreadMentionsOrReplies]);
    }
    
    public static func predicateForConversationConsideredUnreadExcludingSilenced() -> NSPredicate {
        let notSelfConversation = NSPredicate(format: "%K != %d", argumentArray: [ZMConversationConversationTypeKey, ZMConversationType.`self`.rawValue])
        let notInvalidConversation = NSPredicate(format: "%K != %d", argumentArray: [ZMConversationConversationTypeKey, ZMConversationType.invalid.rawValue])
        
        let notBlockedConnection = NSPredicate(format: "(%K == nil) OR (%K != nil AND %K.status != %d)", argumentArray: [ZMConversationConnectionKey, ZMConversationConnectionKey, ZMConversationConnectionKey, ZMConnectionStatus.blocked.rawValue])
        
        return NSCompoundPredicate(andPredicateWithSubpredicates: [notSelfConversation, notInvalidConversation, notBlockedConnection, predicateForUnreadConversation()]);
    }
    
    public var estimatedUnreadCount: Int64 {
        internalEstimatedUnreadCount
    }
    
    static var keyPathsForValuesAffectingEstimatedUnreadCount: Set<String> {
        Set([#keyPath(ZMConversation.internalEstimatedUnreadCount), #keyPath(ZMConversation.lastReadServerTimeStamp)])
    }
    
    public var estimatedUnreadSelfMentionCount: Int64 {
        internalEstimatedUnreadSelfMentionCount
    }
    
    public var estimatedUnreadSelfReplyCount: Int64 {
        internalEstimatedUnreadSelfReplyCount
    }
    
    @objc
    public var internalEstimatedUnreadCount: Int64 {
        get {
            let key = ZMConversation.ZMConversationInternalEstimatedUnreadCountKey
            
            willAccessValue(forKey: key)
            let value = primitiveValue(forKey: key) as? Int64
            didAccessValue(forKey: key)
            
            return value ?? 0
        }
        
        set {
            require(managedObjectContext?.zm_isSyncContext ?? false, "internalEstimatedUnreadCount should only be set from the sync context")
            
            let key = ZMConversation.ZMConversationInternalEstimatedUnreadCountKey
            
            willChangeValue(forKey: key)
            setPrimitiveValue(newValue, forKey: key)
            didChangeValue(forKey: key)
        }
    }
    
    @objc
    public var internalEstimatedUnreadSelfMentionCount: Int64 {
        get {
            let key = ZMConversation.ZMConversationInternalEstimatedUnreadSelfMentionCountKey
            
            willAccessValue(forKey: key)
            let value = primitiveValue(forKey: key) as? Int64
            didAccessValue(forKey: key)
            
            return value ?? 0
        }
        
        set {
            require(managedObjectContext?.zm_isSyncContext ?? false, "internalEstimatedUnreadSelfMentionCount should only be set from the sync context")
            
            let key = ZMConversation.ZMConversationInternalEstimatedUnreadSelfMentionCountKey
            
            willChangeValue(forKey: key)
            setPrimitiveValue(newValue, forKey: key)
            didChangeValue(forKey: key)
        }
    }
    
    @objc
    public var internalEstimatedUnreadSelfReplyCount: Int64 {
        get {
            let key = ZMConversation.ZMConversationInternalEstimatedUnreadSelfReplyCountKey
            
            willAccessValue(forKey: key)
            let value = primitiveValue(forKey: key) as? Int64
            didAccessValue(forKey: key)
            
            return value ?? 0
        }
        
        set {
            require(managedObjectContext?.zm_isSyncContext ?? false, "internalEstimatedUnreadSelfReplyCount should only be set from the sync context")
            
            let key = ZMConversation.ZMConversationInternalEstimatedUnreadSelfReplyCountKey
            
            willChangeValue(forKey: key)
            setPrimitiveValue(newValue, forKey: key)
            didChangeValue(forKey: key)
        }
    }
    
    @objc
    var unreadListIndicator: ZMConversationListIndicator {
        if hasUnreadUnsentMessage {
            return .expiredMessage
        } else if estimatedUnreadSelfMentionCount > 0 {
            return .unreadSelfMention
        } else if estimatedUnreadSelfReplyCount > 0 {
            return .unreadSelfReply
        } else if hasUnreadMissedCall {
            return .missedCall
        } else if hasUnreadKnock {
            return .knock
        } else if estimatedUnreadCount != 0 {
            return .unreadMessages
        }
        return .none
    }
    
    @NSManaged public var hasUnreadUnsentMessage: Bool
    @NSManaged var needsToCalculateUnreadMessages: Bool
    
    @objc
    static var keyPathsForValuesAffectingUnreadListIndicator: Set<String> {
        Set([
            #keyPath(ZMConversation.lastUnreadMissedCallDate),
            #keyPath(ZMConversation.lastUnreadKnockDate),
            #keyPath(ZMConversation.internalEstimatedUnreadCount),
            #keyPath(ZMConversation.lastReadServerTimeStamp),
            #keyPath(ZMConversation.hasUnreadUnsentMessage)
        ])
    }
    
    public var hasUnreadMessagesInOtherConversations: Bool {
        guard let context = managedObjectContext else { return false }
        
        return ZMConversation.unreadConversationCountExcludingSilenced(in: context, excluding: self) > 0
    }
}

// MARK: - Internal
// use this for testing only

extension ZMConversation {
    /// lastUnreadKnockDate can only be set from the syncMOC
    /// if this is nil, there is no unread knockMessage
    @objc
    var lastUnreadKnockDate: Date? {
        get {
            let key = ZMConversation.ZMConversationLastUnreadKnockDateKey
            
            willAccessValue(forKey: key)
            let value = primitiveValue(forKey: key) as? Date
            didAccessValue(forKey: key)
            
            return value
        }
        
        set {
            require(managedObjectContext?.zm_isSyncContext ?? false,
                    "lastUnreadKnockDate should only be set from the sync context")
            
            let key = ZMConversation.ZMConversationLastUnreadKnockDateKey
            willChangeValue(forKey: key)
            setPrimitiveValue(newValue, forKey: key)
            didChangeValue(forKey: key)
        }
    }
    
    
    /// lastUnreadMissedCallDate can only be set from the syncMOC
    /// if this is nil, there is no unread missed call
    @objc
    var lastUnreadMissedCallDate: Date? {
        get {
            let key = ZMConversation.ZMConversationLastUnreadMissedCallDateKey
            
            willAccessValue(forKey: key)
            let value = primitiveValue(forKey: key) as? Date
            didAccessValue(forKey: key)
            
            return value
        }
        
        set {
            require(managedObjectContext?.zm_isSyncContext ?? false,
                    "lastUnreadMissedCallDate should only be set from the sync context")
            
            let key = ZMConversation.ZMConversationLastUnreadMissedCallDateKey
            
            willChangeValue(forKey: key)
            setPrimitiveValue(newValue, forKey: key)
            didChangeValue(forKey: key)
        }
    }
    
    @objc
    var hasUnreadKnock: Bool {
        lastUnreadKnockDate != nil
    }
    
    static var keyPathsForValuesAffectingHasUnreadKnock: Set<String> {
        Set([#keyPath(ZMConversation.lastUnreadKnockDate)])
    }
    
    @objc
    var hasUnreadMissedCall: Bool {
        lastUnreadMissedCallDate != nil
    }
    
    static var keyPathsForValuesAffectingHasUnreadMissedCall: Set<String> {
        Set([#keyPath(ZMConversation.lastUnreadMissedCallDate)])
    }
}
