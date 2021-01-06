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
import WireTransport

@objc(ZMSystemMessage)
public class ZMSystemMessage: ZMMessage, ZMSystemMessageData {

    @NSManaged
    public var childMessages: Set<AnyHashable>

    @NSManaged
    public var systemMessageType: ZMSystemMessageType

    @NSManaged
    public var users: Set<ZMUser>

    @NSManaged
    public var clients: Set<AnyHashable>

    @NSManaged
    public var addedUsers: Set<ZMUser> // Only filled for ZMSystemMessageTypePotentialGap and ZMSystemMessageTypeIgnoredClient
    @NSManaged
    public var removedUsers: Set<ZMUser> // Only filled for ZMSystemMessageTypePotentialGap

    @NSManaged
    public var text: String?

    @NSManaged
    public var needsUpdatingUsers: Bool

    @NSManaged
    public var duration: TimeInterval // Only filled for .performedCall

    @NSManaged
    weak public var parentMessage: ZMSystemMessageData? // Only filled for .performedCall & .missedCall

    @NSManaged
    public var messageTimer: NSNumber? // Only filled for .messageTimerUpdate

    @NSManaged
    var relevantForConversationStatus: Bool // If true (default), the message is considered to be shown inside the conversation list

    static let eventTypeToSystemMessageTypeMap: [ZMUpdateEventType: ZMSystemMessageType] = [
        .conversationMemberJoin: .participantsAdded,
        .conversationMemberLeave: .participantsRemoved,
        .conversationRename: .conversationNameChanged]

    public override static func entityName() -> String {
        return "SystemMessage"
    }
    
    /// fix for "use of unimplemented initializer"
    @objc
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?) {
        super.init(entity: entity, insertInto: context)
    }

    override init(nonce: UUID?, managedObjectContext: NSManagedObjectContext) {
        let entity: NSEntityDescription? = NSEntityDescription.entity(forEntityName: ZMSystemMessage.entityName(), in: managedObjectContext)
        super.init(entity: entity!, insertInto: managedObjectContext)

        self.nonce = nonce
        //TODO: crash when init
        relevantForConversationStatus = true //default value
    }
    
    @objc(createOrUpdateMessageFromUpdateEvent:inManagedObjectContext:prefetchResult:)
    public override static func createOrUpdate(from updateEvent: ZMUpdateEvent,
                                            in moc: NSManagedObjectContext,
                                            prefetchResult: ZMFetchRequestBatchResult?) -> Self? {
        let updateEventType = updateEvent.type
        let type = updateEventType.systemMessageType
        
        if type == .invalid {
            return nil
        }

        let conversation = ZMMessage.conversation(for: updateEvent, in: moc, prefetchResult: prefetchResult)

        //TODO:

//        VerifyAction(conversation != nil, return nil)

//        #define VerifyAction(assertion, action) \
//        do { \
//            if ( __builtin_expect(!(assertion), 0) ) { \
//                ZMDebugAssertMessage(@"Verify", #assertion, __FILE__, __LINE__, nil); \
//                    action; \
//            } \
//        } while (0)
        
        
        // Only create connection request system message if conversation type is valid.
        // Note: if type is not connection request, then it relates to group conversations (see first line of this method).
        // We don't explicitly check for group conversation type b/c if this is the first time we were added to the conversation,
        // then the default conversation type is `invalid` (b/c we haven't fetched from BE yet), so we assume BE sent the
        // update event for a group conversation.
        if conversation?.conversationType == .connection && type != .connectionRequest {
            return nil
        }

        let messageText = updateEvent.payload.dictionary(forKey: "data")?.optionalString(forKey: "message")?.removingExtremeCombiningCharacters
        let name = updateEvent.payload.dictionary(forKey: "data")?.optionalString(forKey: "name")?.removingExtremeCombiningCharacters

        var usersSet: Set<AnyHashable> = []
        if let payload = (updateEvent.payload.dictionary(forKey: "data") as NSDictionary?)?.optionalArray(forKey: "user_ids") {
            for userId in payload {
                guard let userId = userId as? String else {
                    continue
                }
                let user = ZMUser(remoteID: NSUUID(transport: userId)! as UUID, createIfNeeded: true, in: moc)
                _ = usersSet.insert(user)
            }
        }

        let message = ZMSystemMessage(nonce: UUID(), managedObjectContext: moc)
        message.systemMessageType = type
        message.visibleInConversation = conversation
        message.serverTimestamp = updateEvent.timestamp

        message.update(with: updateEvent, for: conversation!)

        if usersSet != Set<AnyHashable>([message.sender]) {
            usersSet.remove(message.sender)
        }

        message.users = usersSet as! Set<ZMUser>
        message.text = messageText ?? name

        conversation?.updateTimestampsAfterInsertingMessage( message)

        return message as? Self
    }

    @objc
    override public var systemMessageData: ZMSystemMessageData? {
        return self
    }

    public override func shouldGenerateUnreadCount() -> Bool {
        switch systemMessageType {
        case .participantsRemoved, .participantsAdded:
            let selfUser = ZMUser.selfUser(in: managedObjectContext!)
                return users.contains(selfUser) && false == sender?.isSelfUser
        case .newConversation:
            return sender?.isSelfUser == false
        case .missedCall:
            return relevantForConversationStatus
        default:
            return false
        }
    }
    
    override func updateQuoteRelationships() {
        // System messages don't support quotes at the moment
    }

    /// Set to true if sender is the only user in users array. E.g. when a wireless user joins conversation
    public var userIsTheSender: Bool {
        let onlyOneUser = users.count == 1
        let isSender: Bool
        if let sender = sender {
            isSender = users.contains(sender)
        } else {
            isSender = false
        }
        return onlyOneUser && isSender
    }

    // MARK: - internal
    @objc
    class func doesEventTypeGenerateSystemMessage(_ type: ZMUpdateEventType) -> Bool {
        return eventTypeToSystemMessageTypeMap.keys.contains(type)
    }
    
    @objc
    func updateNeedsUpdatingUsersIfNeeded() {
        if systemMessageType == .potentialGap && needsUpdatingUsers {
            let matchUnfetchedUserBlock: (ZMUser?) -> Bool = { user in
                return user?.name == nil
            }
            
            needsUpdatingUsers = addedUsers.any(matchUnfetchedUserBlock) || removedUsers.any(matchUnfetchedUserBlock)
        }
    }

    @objc(fetchLatestPotentialGapSystemMessageInConversation:)
    class func fetchLatestPotentialGapSystemMessage(in conversation: ZMConversation) -> ZMSystemMessage? {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: self.entityName())
        request.sortDescriptors = [
            NSSortDescriptor(key: ZMMessageServerTimestampKey, ascending: false)
        ]
        request.fetchBatchSize = 1
        request.predicate = predicateForPotentialGapSystemMessagesNeedingUpdatingUsers(in: conversation)
        let result = conversation.managedObjectContext!.executeFetchRequestOrAssert(request)
        return result.first as? ZMSystemMessage
    }
    
    class func predicateForPotentialGapSystemMessagesNeedingUpdatingUsers(in conversation: ZMConversation) -> NSPredicate {
        let conversationPredicate = NSPredicate(format: "%K == %@", ZMMessageConversationKey, conversation)
        let missingMessagesTypePredicate = NSPredicate(format: "%K == %d", ZMMessageSystemMessageTypeKey, ZMSystemMessageType.potentialGap.rawValue)
        let needsUpdatingUsersPredicate = NSPredicate(format: "%K == YES", ZMMessageNeedsUpdatingUsersKey)
        return NSCompoundPredicate(andPredicateWithSubpredicates: [
            conversationPredicate,
            missingMessagesTypePredicate,
            needsUpdatingUsersPredicate
        ])
    }
    
    class func predicateForSystemMessagesInsertedLocally() -> NSPredicate {
        return NSPredicate(block: { msg, _ in
            guard let msg = msg as? ZMSystemMessage else {
                return false
            }
            
            switch msg.systemMessageType {
            case .newClient, .potentialGap, .ignoredClient, .performedCall, .usingNewDevice, .decryptionFailed, .reactivatedDevice, .conversationIsSecure, .messageDeletedForEveryone, .decryptionFailed_RemoteIdentityChanged, .teamMemberLeave, .missedCall, .readReceiptsEnabled, .readReceiptsDisabled, .readReceiptsOn, .legalHoldEnabled, .legalHoldDisabled:
                return true
            case .invalid, .conversationNameChanged, .connectionRequest, .connectionUpdate, .newConversation, .participantsAdded, .participantsRemoved, .messageTimerUpdate:
                return false
            @unknown default:
                return false
            }
        })
    }
}

private extension ZMUpdateEventType {
    var systemMessageType: ZMSystemMessageType {
        guard let systemMessageType = ZMSystemMessage.eventTypeToSystemMessageTypeMap[self] else {
            return .invalid
        }
        
        return systemMessageType
    }
}