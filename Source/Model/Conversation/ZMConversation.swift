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

import Foundation
import WireUtilities

@objc(ZMConversation)
@objcMembers
public final class ZMConversation: ZMManagedObject {
    private let zmLog = ZMSLog(tag: "ZMConversation")
    
    public override static func entityName() -> String {
        "Conversation"
    }
    
    @NSManaged public var lastServerTimeStamp: Date?
    @NSManaged public var team: Team?
    @NSManaged public var labels: Set<Label>
    @NSManaged public var domain: String?
    @NSManaged public var allMessages: Set<ZMMessage>
    @NSManaged public var creator: ZMUser
    @NSManaged public var lastModifiedDate: Date?
    @NSManaged public var silencedChangedTimestamp: Date?
    @NSManaged public var connection: ZMConnection?
    @NSManaged public var archivedChangedTimestamp: Date?
    @NSManaged public var participantRoles: Set<ParticipantRole>
    @NSManaged public var nonTeamRoles: Set<Role>
    
    @NSManaged var internalIsArchived: Bool
    @NSManaged var normalizedUserDefinedName: String?
    @NSManaged public var hiddenMessages: Set<ZMMessage>
    
    var lastReadTimestampSaveDelay: TimeInterval = 0
    var lastReadTimestampUpdateCounter: Int64 = 0
    
    var pendingLastReadServerTimestamp: Date?
    var previousLastReadServerTimestamp: Date?
    
    public var userDefinedName: String? {
        get {
            let key = #keyPath(ZMConversation.userDefinedName)

            willAccessValue(forKey: key)
            let value = primitiveValue(forKey: key) as? String
            didAccessValue(forKey: key)

            return value
        }
        
        set {
            let key = #keyPath(ZMConversation.userDefinedName)
            

            willChangeValue(forKey: key)
            setPrimitiveValue(newValue?.removingExtremeCombiningCharacters, forKey: key)
            didChangeValue(forKey: key)

            normalizedUserDefinedName = (newValue as NSString?)?.normalized() as String?
        }
    }
    
    public var clearedTimeStamp: Date? {
        get {
            let key = #keyPath(ZMConversation.clearedTimeStamp)

            willAccessValue(forKey: key)
            let value = primitiveValue(forKey: key) as? Date
            didAccessValue(forKey: key)

            return value
        }
        
        set {
            let key = #keyPath(ZMConversation.clearedTimeStamp)

            willChangeValue(forKey: key)
            setPrimitiveValue(newValue, forKey: key)
            didChangeValue(forKey: key)

            if managedObjectContext?.zm_isSyncContext ?? false {
                deleteOlderMessages()
            }
        }
    }
    
    public var lastReadServerTimeStamp: Date? {
        get {
            let key = #keyPath(ZMConversation.lastReadServerTimeStamp)

            willAccessValue(forKey: key)
            let value = primitiveValue(forKey: key) as? Date
            didAccessValue(forKey: key)

            return value
        }
        
        set {
            let key = #keyPath(ZMConversation.lastReadServerTimeStamp)

            willChangeValue(forKey: key)
            setPrimitiveValue(newValue, forKey: key)
            didChangeValue(forKey: key)

            if managedObjectContext?.zm_isSyncContext ?? false {
                calculateLastUnreadMessages()
            }
        }
    }
    
    public var remoteIdentifier: UUID? {
        get {
            transientUUID(forKey: #keyPath(ZMConversation.remoteIdentifier))
        }

        set {
            setTransientUUID(newValue, forKey: #keyPath(ZMConversation.remoteIdentifier))
        }
    }
    
    static var keyPathsForValuesAffectingRemoteIdentifier: Set<String> {
        Set([ZMConversation.ZMConversationRemoteIdentifierDataKey])
    }
    
    public var teamRemoteIdentifier: UUID? {
        get {
            transientUUID(forKey: #keyPath(ZMConversation.teamRemoteIdentifier))
        }

        set {
            setTransientUUID(newValue, forKey: #keyPath(ZMConversation.teamRemoteIdentifier))
        }
    }
    
    public var mutableMessages: NSMutableSet {
        mutableSetValue(forKeyPath: #keyPath(ZMConversation.allMessages))
    }
    
    @objc(conversationsIncludingArchivedInContext:)
    static func conversationsIncludingArchived(in context: NSManagedObjectContext) -> ZMConversationList {
        context.conversationListDirectory().conversationsIncludingArchived
    }
    
    @objc(archivedConversationsInContext:)
    static func archivedConversations(in context: NSManagedObjectContext) -> ZMConversationList {
        context.conversationListDirectory().archivedConversations
    }
    
    @objc(clearedConversationsInContext:)
    static func clearedConversations(in context: NSManagedObjectContext) -> ZMConversationList {
        context.conversationListDirectory().clearedConversations
    }
    
    @objc(conversationsExcludingArchivedInContext:)
    public static func conversationsExcludingArchived(in context: NSManagedObjectContext) -> ZMConversationList {
        context.conversationListDirectory().unarchivedConversations
    }
    
    @objc(pendingConversationsInContext:)
    static func pendingConversations(in context: NSManagedObjectContext) -> ZMConversationList {
        context.conversationListDirectory().pendingConnectionConversations
    }
    
    var isPendingConnectionConversation: Bool {
        connection?.status == .pending
    }
    
    static var keyPathsForValuesAffectingIsPendingConnectionConversation: Set<String> {
        Set([#keyPath(ZMConversation.connection.status)])
    }
    
    
    public var relatedConnectionState: ZMConnectionStatus {
        guard let connection = connection else { return .invalid }
        
        return connection.status
    }
    
    static var keyPathsForValuesAffectingRelatedConnectionState: Set<String> {
        Set([#keyPath(ZMConversation.connection.status), #keyPath(ZMConversation.connection)])
    }
    
    public var hasDraftMessage: Bool {
        !(draftMessage?.text ?? "").isEmpty
    }
    
    static var keyPathsForValuesAffectingHasDraftMessage: Set<String> {
        Set([DraftMessageDataKey])
    }
    
    public var lastEditableMessage: ZMMessage? {
        for message in lastMessages(limit: 50) {
            if message.isEditableMessage {
                return message
            }
        }
        return nil
    }
    
    public override func filterUpdatedLocallyModifiedKeys(_ updatedKeys: Set<String>) -> Set<String> {
        var newKeys = super.filterUpdatedLocallyModifiedKeys(updatedKeys)
        
        // Don't sync the conversation name if it was set before inserting the conversation
        // as it will already get synced when inserting the conversation on the backend.
        
        let keyPathToRemove = #keyPath(ZMConversation.userDefinedName)
        if isInserted, userDefinedName != nil, newKeys.contains(keyPathToRemove) {
            newKeys.remove(keyPathToRemove)
        }
        
        return newKeys
    }
    
    static var keyPathsForValuesAffectingFirstUnreadMessage: Set<String> {
        Set([#keyPath(ZMConversation.allMessages), #keyPath(ZMConversation.lastReadServerTimeStamp)])
    }
    
    public var isArchived: Bool {
        get {
            internalIsArchived
        }
        
        set {
            internalIsArchived = newValue
            
            guard let lastServerTimeStamp = lastServerTimeStamp else { return }
            updateArchived(lastServerTimeStamp, synchronize: true)
        }
    }
    
    static var keyPathsForValuesAffectingIsArchived: Set<String> {
        Set([#keyPath(ZMConversation.internalIsArchived)])
    }
    
    public var isReadOnly: Bool {
        switch conversationType {
        case .invalid, .`self`, .connection:
            return true
        case .oneOnOne:
            return false
        case .group:
            return !isSelfAnActiveMember
        }
    }
    
    static var keyPathsForValuesAffectingIsReadOnly: Set<String> {
        Set([#keyPath(ZMConversation.conversationType), #keyPath(ZMConversation.participantRoles)])
    }
    
    public var connectedUser: ZMUser? {
        guard let internalType = ZMConversationType(rawValue: internalConversationType) else { return nil }
        
        if internalType == .oneOnOne || internalType == .connection {
            return connection?.to
        } else if conversationType == .oneOnOne {
            return localParticipantsExcludingSelf.first
        }
        
        return nil
    }
    
    static var keyPathsForValuesAffectingConnectedUser: Set<String> {
        Set([#keyPath(ZMConversation.conversationType)])
    }
    
    var connectionMessage: String {
        connection?.message.removingExtremeCombiningCharacters ?? ""
    }
    
    public var canMarkAsUnread: Bool {
        !(estimatedUnreadCount > 0 || lastMessageCanBeMarkedUnread == nil)
    }
    
    private var lastMessageCanBeMarkedUnread: ZMMessage? {
        for message in lastMessages(limit: 50) {
            if message.canBeMarkedUnread {
                return message
            }
        }
        
        return nil
    }
    
    public func markAsUnread() {
        guard let lastMessageCanBeMarkedUnread = lastMessageCanBeMarkedUnread else {
            zmLog.error("Cannot mark as read: no message to mark in \(self)")
            return
        }
        
        lastMessageCanBeMarkedUnread.markAsUnread()
    }
    
    @objc(existingOneOnOneConversationWithUser:inUserSession:)
    static func existingOneOnOneConversation(with user: ZMUser, in session: ContextProvider) -> ZMConversation? {
        user.connection?.conversation
    }
    
    public override static func defaultSortDescriptors() -> [NSSortDescriptor]? {
        [
            NSSortDescriptor(key: #keyPath(ZMConversation.internalIsArchived), ascending: true),
            NSSortDescriptor(key: #keyPath(ZMConversation.lastModifiedDate), ascending: false),
            NSSortDescriptor(key: ZMConversationRemoteIdentifierDataKey, ascending: true)
        ]
    }
    
    public func clearMessageHistory() {
        isArchived = true
        clearedTimeStamp = lastServerTimeStamp // This will delete all messages
        lastReadServerTimeStamp = lastServerTimeStamp
    }
    
    public func revealClearedConversation() {
        isArchived = false
    }
    
    @objc(appendMessage:)
    public func append(_ newMessage: ZMMessage?) {
        guard let message = newMessage else {
            require(newMessage != nil)
            return
        }
        
        message.updateNormalizedText()
        message.visibleInConversation = self
        
        addToAllMessages(message)
        updateTimestampsAfterInsertingMessage(message)
    }
    
    public func mergeWithExistingConversation(withRemoteID remoteID: UUID) {
        guard let context = managedObjectContext else { return }
        
        if let existingConversation = ZMConversation.internalFetch(withRemoteIdentifier: remoteID, in: context), !existingConversation.isEqual(self) {
            require(remoteIdentifier == nil)
            
            mutableMessages.union(existingConversation.allMessages)
            
            needsToBeUpdatedFromBackend = true
            
            context.delete(existingConversation)
        }
        
        remoteIdentifier = remoteID
    }
    
    func unarchiveIfNeeded() {
        if isArchived {
            isArchived = false
        }
    }
    
    private var shouldNotBeRefreshed: Bool {
        let HOUR_IN_SEC = 60 * 60
        let STALENESS = TimeInterval(-36 * HOUR_IN_SEC)
        
        if let lastModifiedDate = lastModifiedDate, lastModifiedDate.timeIntervalSinceNow > STALENESS {
            return true
        }
        
        return isFault || lastModifiedDate == nil
    }
    
    @objc(refreshObjectsThatAreNotNeededInSyncContext:)
    static func refreshObjectsThatAreNotNeeded(in syncContext: NSManagedObjectContext) {
        var conversationsToKeep = [NSManagedObject]()
        var usersToKeeep = Set<NSManagedObject>()
        var messagesToKeep = Set<NSManagedObject>()
        
        let registeredObjects = syncContext.registeredObjects
        
        for object in registeredObjects {
            guard !object.isFault else { continue }
            
            if let conversation = object as? ZMConversation {
                guard conversation.shouldNotBeRefreshed else { continue }
                
                conversationsToKeep.append(conversation)
                usersToKeeep.formUnion(conversation.localParticipants)
                
            } else if let message = object as? ZMOTRMessage {
                guard
                    !message.hasFault(forRelationshipNamed: ZMMessageMissingRecipientsKey),
                    !message.missingRecipients.isEmpty
                else {
                    continue
                }
                
                messagesToKeep.insert(message)
            }
        }
        
        usersToKeeep.insert(ZMUser.selfUser(in: syncContext))
        
        func check<T, C: Collection>(object: NSManagedObject, type: T.Type, in collection: C) -> Bool where C.Element: NSManagedObject {
            return object is T && collection.contains(object as! C.Element)
        }
        
        for object in registeredObjects {
            guard !object.isFault else { continue }
            
            let isUser = object is ZMUser
            let isConversation = object is ZMConversation
            let isMessage = object is ZMMessage
            
            let isOfTypeToBeRefreshed = isUser || isMessage || isConversation
            
            if (isUser && usersToKeeep.contains(object)) ||
                (isConversation && conversationsToKeep.contains(object))
                    ||
                (isMessage && messagesToKeep.contains(object)) ||
                !isOfTypeToBeRefreshed {
                continue
            }
            
            syncContext.refresh(object, mergeChanges: object.hasChanges)
        }
    }
    
    public override static func sortedFetchRequest() -> NSFetchRequest<NSFetchRequestResult> {
        let request = super.sortedFetchRequest()
        
        if let predicate = request.predicate {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate,  predicateForFilteringResults()])
        } else {
            request.predicate = predicateForFilteringResults()
        }
        return request
        
    }
    
    public override func awakeFromFetch() {
        super.awakeFromFetch()
        
        lastReadTimestampSaveDelay = ZMConversation.ZMConversationDefaultLastReadTimestampSaveDelay
        
        guard
            let managedObjectContext = managedObjectContext,
            managedObjectContext.zm_isSyncContext,
            needsToCalculateUnreadMessages
        else {
            return
        }
        
        // From the documentation: The managed object context’s change processing is explicitly disabled around this method so that you can use public setters to establish transient values and other caches without dirtying the object or its context.
        // Therefore we need to do a dispatch async  here in a performGroupedBlock to update the unread properties outside of awakeFromFetch
        managedObjectContext.performGroupedBlock { [weak self] in
            guard let self = self else { return }
            
            self.calculateLastUnreadMessages()
        }
    }
    
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        
        lastReadTimestampSaveDelay = ZMConversation.ZMConversationDefaultLastReadTimestampSaveDelay
        
        guard
            let managedObjectContext = managedObjectContext,
            managedObjectContext.zm_isSyncContext,
            needsToCalculateUnreadMessages
        else {
            return
        }
        
        // From the documentation: You are typically discouraged from performing fetches within an implementation of awakeFromInsert. Although it is allowed, execution of the fetch request can trigger the sending of internal Core Data notifications which may have unwanted side-effects. Since we fetch the unread messages here, we should do a dispatch async
        managedObjectContext.performGroupedBlock { [weak self] in
            guard let self = self else { return }
            
            self.calculateLastUnreadMessages()
        }
    }
    
    @objc
    func validateUserDefinedName(_ value: AutoreleasingUnsafeMutablePointer<AnyObject?>) throws {
        try ExtremeCombiningCharactersValidator.validateValue(value)

        do {
            try StringLengthValidator.validateValue(value, minimumStringLength: 1, maximumStringLength: 64, maximumByteLength: UInt32.max)
        } catch {
            if value.pointee == nil {
                return
            } else {
                throw error
            }
        }
    }
}

// MARK: Core Data Generated accessors

extension ZMConversation {
    
    @objc(addAllMessagesObject:)
    @NSManaged public func addToAllMessages(_ value: ZMMessage)

    @objc(removeAllMessagesObject:)
    @NSManaged public func removeFromAllMessages(_ value: ZMMessage)

    @objc(addAllMessages:)
    @NSManaged public func addToAllMessages(_ values: NSSet)

    @objc(removeAllMessages:)
    @NSManaged public func removeFromAllMessages(_ values: NSSet)
    
    
    @objc(addHiddenMessagesObject:)
    @NSManaged public func addToHiddenMessages(_ value: ZMMessage)

    @objc(removeHiddenMessagesObject:)
    @NSManaged public func removeFromHiddenMessages(_ value: ZMMessage)

    @objc(addHiddenMessages:)
    @NSManaged public func addToHiddenMessages(_ values: NSSet)

    @objc(removeHiddenMessages:)
    @NSManaged public func removeFromHiddenMessages(_ values: NSSet)
}

@objc
extension NSUUID {
    @objc(isSelfConversationRemoteIdentifierInContext:)
    func isSelfConversationRemoteIdentifier(in context: NSManagedObjectContext) -> Bool {
        ZMUser.selfUser(in: context).remoteIdentifier.uuidString == self.uuidString
    }
}
