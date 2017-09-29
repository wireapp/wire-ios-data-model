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
import WireCryptobox


extension ZMConversation {

    /// Contains current security level of conversation.
    ///Client should check this property to properly annotate conversation.
    @NSManaged public internal(set) var securityLevel : ZMConversationSecurityLevel

    /// Should be called when client is trusted.
    /// If the conversation became trusted, it will trigger UI notification and add system message for all devices verified
    @objc(increaseSecurityLevelIfNeededAfterTrustingClients:)
    public func increaseSecurityLevelIfNeededAfterTrusting(clients: Set<UserClient>) {
        guard self.increaseSecurityLevelIfNeeded() else { return }
        self.appendNewIsSecureSystemMessage(verified: clients)
        self.notifyOnUI(name: ZMConversation.isVerifiedNotificationName)
    }

    /// Should be called when client is deleted.
    /// If the conversation became trusted, it will trigger UI notification and add system message for all devices verified
    @objc(increaseSecurityLevelIfNeededAfterRemovingClientForUsers:)
    public func increaseSecurityLevelIfNeededAfterRemovingClient(for users: Set<ZMUser>) {
        guard self.increaseSecurityLevelIfNeeded() else { return }
        self.appendNewIsSecureSystemMessage(verified: Set<UserClient>(), for: users)
        self.notifyOnUI(name: ZMConversation.isVerifiedNotificationName)
    }

    /// Should be called when a new client is discovered
    @objc(decreaseSecurityLevelIfNeededAfterDiscoveringClients:causedByMessage:)
    public func decreaseSecurityLevelIfNeededAfterDiscovering(clients: Set<UserClient>, causedBy message: ZMOTRMessage?) {
        guard self.decreaseSecurityLevelIfNeeded() else { return }
        self.appendNewAddedClientSystemMessage(added: clients, causedBy: DiscoveryCause.message(message))
        if let message = message {
            self.expireAllPendingMessagesBecauseOfSecurityLevelDegradation(staringFrom: message)
        }
    }
    
    /// Should be called when a new user is added to the conversation
    @objc(decreaseSecurityLevelIfNeededAfterDiscoveringClients:causedByAddedUsers:)
    public func decreaseSecurityLevelIfNeededAfterDiscovering(clients: Set<UserClient>, causedBy users: Set<ZMUser>) {
        guard self.decreaseSecurityLevelIfNeeded() else { return }
        self.appendNewAddedClientSystemMessage(added: clients, causedBy: DiscoveryCause.addedUsers(users))
    }

    /// Should be called when a client is ignored
    @objc(decreaseSecurityLevelIfNeededAfterIgnoringClients:)
    public func decreaseSecurityLevelIfNeededAfterIgnoring(clients: Set<UserClient>) {
        guard self.decreaseSecurityLevelIfNeeded() else { return }
        self.appendIgnoredClientsSystemMessage(ignored: clients)
    }

    /// Creates system message that says that you started using this device, if you were not registered on this device
    public func appendStartedUsingThisDeviceMessage() {
        guard ZMSystemMessage.fetchStartedUsingOnThisDeviceMessage(conversation: self) == nil else { return }
        let selfUser = ZMUser.selfUser(in: self.managedObjectContext!)
        guard let selfClient = selfUser.selfClient() else { return }
        self.appendSystemMessage(type: .usingNewDevice,
                                 sender: selfUser,
                                 users: Set(arrayLiteral: selfUser),
                                 clients: Set(arrayLiteral: selfClient),
                                 timestamp: self.timestamp(after: self.messages.lastObject as? ZMMessage))
    }

    /// Creates a system message when a device has previously been used before, but was logged out due to invalid cookie and/ or invalidated client
    public func appendContinuedUsingThisDeviceMessage() {
        let selfUser = ZMUser.selfUser(in: self.managedObjectContext!)
        guard let selfClient = selfUser.selfClient() else { return }
        self.appendSystemMessage(type: .reactivatedDevice,
                                 sender: selfUser,
                                 users: Set(arrayLiteral: selfUser),
                                 clients: Set(arrayLiteral: selfClient),
                                 timestamp: Date())
    }

    /// Creates a system message that inform that there are pontential lost messages, and that some users were added to the conversation
    public func appendNewPotentialGapSystemMessage(users: Set<ZMUser>?, timestamp: Date) {
        
        let (systemMessage, index) = self.appendSystemMessage(type: .potentialGap,
                                                              sender: ZMUser.selfUser(in: self.managedObjectContext!),
                                                              users: users,
                                                              clients: nil,
                                                              timestamp: timestamp)
        systemMessage.needsUpdatingUsers = true
        if index > 1,
            let previousMessage = self.messages[Int(index - 1)] as? ZMSystemMessage,
            previousMessage.systemMessageType == .potentialGap
        {
            // In case the message before the new system message was also a system message of
            // the type ZMSystemMessageTypePotentialGap, we delete the old one and update the
            // users property of the new one to use old users and calculate the added / removed users
            // from the time the previous one was added
            systemMessage.users = previousMessage.users
            self.managedObjectContext?.delete(previousMessage)
        }
    }

    /// Creates the message that warns user about the fact that decryption of incoming message is failed
    @objc(appendDecryptionFailedSystemMessageAtTime:sender:client:errorCode:)
    public func appendDecryptionFailedSystemMessage(at date: Date?, sender: ZMUser, client: UserClient?, errorCode: Int) {
        let type = (UInt32(errorCode) == CBOX_REMOTE_IDENTITY_CHANGED.rawValue) ? ZMSystemMessageType.decryptionFailed_RemoteIdentityChanged : ZMSystemMessageType.decryptionFailed
        let clients = client.flatMap { Set(arrayLiteral: $0) } ?? Set<UserClient>()
        let serverTimestamp = date ?? self.timestamp(after: self.messages.lastObject as? ZMMessage)
        self.appendSystemMessage(type: type,
                                 sender: sender,
                                 users: nil,
                                 clients: clients,
                                 timestamp: serverTimestamp)
    }
    
    /// Decrease the security level if some clients are now not trusted
    /// - returns: true if the security level was decreased
    private func decreaseSecurityLevelIfNeeded() -> Bool {
        guard !self.allUsersTrusted && self.securityLevel == .secure else { return false }
        self.securityLevel = .secureWithIgnored
        return true
    }
    
    /// Increase the security level if all clients are now trusted
    /// - returns: true if the security level was increased
    private func increaseSecurityLevelIfNeeded() -> Bool {
        guard self.allUsersTrusted && self.allParticipantsHaveClients && self.securityLevel != .secure else { return false }
        self.securityLevel = .secure
        return true
    }
}

// MARK: - Messages resend/expiration
extension ZMConversation {
    
    /// Mark conversation as not secure. This method is expected to be called from the UI context
    public func makeNotSecure() {
        precondition(self.managedObjectContext!.zm_isUserInterfaceContext)
        self.securityLevel = .notSecure
        self.managedObjectContext?.saveOrRollback()
    }
    
    /// Resend last non sent messages. This method is expected to be called from the UI context
    public func resendMessagesThatCausedConversationSecurityDegradation() {
        precondition(self.managedObjectContext!.zm_isUserInterfaceContext)
        self.securityLevel = .notSecure // The conversation needs to be marked as not secure for new messages to be sent
        self.managedObjectContext?.saveOrRollback()
        self.enumerateReverseMessagesThatCausedDegradationUntilFirstSystemMessageOnSyncContext {
            $0.causedSecurityLevelDegradation = false
            $0.resend()
        }
    }
    
    /// Reset those that caused degradation. This method is expected to be called from the UI context
    public func doNotResendMessagesThatCausedDegradation() {
        guard let syncMOC = self.managedObjectContext?.zm_sync else { return }
        syncMOC.performGroupedBlock {
            guard let conversation = (try? syncMOC.existingObject(with: self.objectID)) as? ZMConversation else { return }
            conversation.clearMessagesThatCausedSecurityLevelDegradation()
            syncMOC.saveOrRollback()
        }
    }
    
    /// Enumerates all messages from newest to oldest and apply a block to all ZMOTRMessage encountered, 
    /// halting the enumeration when a system message for security level degradation is found.
    /// This is executed asychronously on the sync context
    private func enumerateReverseMessagesThatCausedDegradationUntilFirstSystemMessageOnSyncContext(block: @escaping (ZMOTRMessage)->()) {
        guard let syncMOC = self.managedObjectContext?.zm_sync else { return }
        syncMOC.performGroupedBlock {
            guard let conversation = (try? syncMOC.existingObject(with: self.objectID)) as? ZMConversation else { return }
            conversation.messagesThatCausedSecurityLevelDegradation.forEach(block)
            syncMOC.saveOrRollback()
        }
    }
    
    /// Expire all pending message after the given message, including the given message
    fileprivate func expireAllPendingMessagesBecauseOfSecurityLevelDegradation(staringFrom startingMessage: ZMMessage) {
        self.messages.enumerateObjects(options: .reverse) { (msg, idx, stop) in
            guard let message = msg as? ZMOTRMessage else { return }
            if message.deliveryState != .delivered && message.deliveryState != .sent {
                if let clientMessage = message as? ZMClientMessage,
                    let genericMessage = clientMessage.genericMessage,
                    genericMessage.hasConfirmation() {
                    // Delivery receipt: just expire it
                    clientMessage.expire()
                } else {
                    // All other messages: expire and mark that it caused security degradation
                    message.expire()
                    message.causedSecurityLevelDegradation = true
                }
            }
            if startingMessage == message {
                stop.initialize(to: true)
            }
        }
    }
}

// MARK: - HotFix
extension ZMConversation {

    /// Replaces the first NewClient systemMessage for the selfClient with a UsingNewDevice system message
    public func replaceNewClientMessageIfNeededWithNewDeviceMesssage() {

        let selfUser = ZMUser.selfUser(in: self.managedObjectContext!)
        guard let selfClient = selfUser.selfClient() else { return }
        
        self.messages.enumerateObjects(options: .reverse) { (msg, idx, stop) in
            guard idx <= 2 else {
                stop.initialize(to: true)
                return
            }
            
            guard let systemMessage = msg as? ZMSystemMessage,
                systemMessage.systemMessageType == .newClient,
                systemMessage.sender == selfUser else {
                    return
            }
            
            if systemMessage.clients.contains(selfClient) {
                systemMessage.systemMessageType = .usingNewDevice
                stop.initialize(to: true)
            }
        }
    }
}

// MARK: - Appending system messages
extension ZMConversation {
    
    fileprivate func appendNewIsSecureSystemMessage(verified clients: Set<UserClient>) {
        let users = Set(clients.flatMap { $0.user })
        self.appendNewIsSecureSystemMessage(verified: clients, for: users)
    }
    
    fileprivate func appendNewIsSecureSystemMessage(verified clients: Set<UserClient>, for users: Set<ZMUser>) {
        guard !users.isEmpty,
            self.securityLevel != .secureWithIgnored else {
                return
            }
        self.appendSystemMessage(type: .conversationIsSecure,
                                 sender: ZMUser.selfUser(in: self.managedObjectContext!),
                                 users: users,
                                 clients: clients,
                                 timestamp: self.timestamp(after: self.messages.lastObject as? ZMMessage))
    }
    
    fileprivate enum DiscoveryCause {
        case message(ZMOTRMessage?)
        case addedUsers(Set<ZMUser>)
    }
    
    fileprivate func appendNewAddedClientSystemMessage(added clients: Set<UserClient>, causedBy cause: DiscoveryCause) {
        let users = Set(clients.flatMap { $0.user })
        var timestamp : Date?
        var addedUsers: Set<ZMUser> = Set<ZMUser>([])
        
        switch cause {
        case .addedUsers(let users):
            addedUsers = users
        case .message(let message):
            if let message = message, message.conversation == self {
                timestamp = self.timestamp(before: message)
            }
        }
        
        guard !clients.isEmpty || !addedUsers.isEmpty else { return }

        if timestamp == .none {
            timestamp = self.timestamp(after: self.messages.lastObject as? ZMMessage)
        }
        
        self.appendSystemMessage(type: .newClient,
                                 sender: ZMUser.selfUser(in: self.managedObjectContext!),
                                 users: users,
                                 addedUsers: addedUsers,
                                 clients: clients,
                                 timestamp: timestamp)
    }
    
    fileprivate func appendIgnoredClientsSystemMessage(ignored clients: Set<UserClient>) {
        guard !clients.isEmpty else { return }
        let users = Set(clients.flatMap { $0.user })
        self.appendSystemMessage(type: .ignoredClient,
                                 sender: ZMUser.selfUser(in: self.managedObjectContext!),
                                 users: users,
                                 clients: clients,
                                 timestamp: self.timestamp(after: self.messages.lastObject as? ZMMessage))
    }
    
    @discardableResult
    func appendSystemMessage(type: ZMSystemMessageType,
                                         sender: ZMUser,
                                         users: Set<ZMUser>?,
                                         addedUsers: Set<ZMUser> = Set(),
                                         clients: Set<UserClient>?,
                                         timestamp: Date?,
                                         duration: TimeInterval? = nil
                                         ) -> (message: ZMSystemMessage, insertionIndex: UInt) {
        let systemMessage = ZMSystemMessage.insertNewObject(in: self.managedObjectContext!)
        systemMessage.systemMessageType = type
        systemMessage.sender = sender
        systemMessage.isEncrypted = false
        systemMessage.isPlainText = true
        systemMessage.users = users ?? Set()
        systemMessage.addedUsers = addedUsers
        systemMessage.clients = clients ?? Set()
        systemMessage.nonce = UUID()
        systemMessage.serverTimestamp = timestamp
        if let duration = duration {
            systemMessage.duration = duration
        }
        
        let index = self.sortedAppendMessage(systemMessage)
        systemMessage.visibleInConversation = self
        
        if systemMessage.shouldGenerateUnreadCount() {
            precondition(timestamp != nil, "An unread dot generating system message must have a timestamp")
            updateLastServerTimeStampIfNeeded(timestamp)
            updateUnreadMessages(with: systemMessage)
        }
        
        return (message: systemMessage, insertionIndex: index)
    }
    

    
    /// Returns a timestamp that is shortly (as short as possible) before the given message,
    /// or the last modified date if the message is nil
    fileprivate func timestamp(before: ZMMessage?) -> Date? {
        guard let timestamp = before?.serverTimestamp ?? self.lastModifiedDate else { return nil }
        // this feels a bit hackish, but should work. If two messages are less than 1 milliseconds apart
        // then in this case one of them will be out of order
        return timestamp.addingTimeInterval(-0.01)
    }
    
    /// Returns a timestamp that is shortly (as short as possible) after the given message,
    /// or the last modified date if the message is nil
    fileprivate func timestamp(after: ZMMessage?) -> Date? {
        guard let timestamp = after?.serverTimestamp ?? self.lastModifiedDate else { return nil }
        // this feels a bit hackish, but should work. If two messages are less than 1 milliseconds apart
        // then in this case one of them will be out of order
        return timestamp.addingTimeInterval(0.01)
    }
}

// MARK: - Conversation participants status
extension ZMConversation {
    
    /// Returns true if all participants are connected to the self user and all participants are trusted
    public var allUsersTrusted : Bool {
        guard self.otherActiveParticipants.count > 0, self.isSelfAnActiveMember else { return false }
        let hasOnlyTrustedUsers = (self.activeParticipants.array as! [ZMUser]).first { !$0.trusted() } == nil
        return hasOnlyTrustedUsers && !self.containsUnconnectedOrExternalParticipant
    }
    
    fileprivate var containsUnconnectedOrExternalParticipant : Bool {
        guard let managedObjectContext = self.managedObjectContext else {
            return true
        }
        
        let selfUser = ZMUser.selfUser(in: managedObjectContext)
        return (self.otherActiveParticipants.array as! [ZMUser]).first {
            if $0.isConnected {
                return false
            }
            else {
                return $0.team != selfUser.team
            }
        } != nil
    }
    
    fileprivate var allParticipantsHaveClients : Bool {
        return (self.activeParticipants.array as! [ZMUser]).first { $0.clients.count == 0 } == nil
    }
    
    /// If true the conversation might still be trusted / ignored
    public var hasUntrustedClients : Bool {
        return (self.activeParticipants.array as! [ZMUser]).first { $0.untrusted() } != nil
    }
}

// MARK: - System messages
extension ZMSystemMessage {

    /// Fetch the first system message in the conversation about "started to use this device"
    fileprivate static func fetchStartedUsingOnThisDeviceMessage(conversation: ZMConversation) -> ZMSystemMessage? {
        guard let selfClient = ZMUser.selfUser(in: conversation.managedObjectContext!).selfClient() else { return nil }
        let conversationPredicate = NSPredicate(format: "%K == %@ OR %K == %@", ZMMessageConversationKey, conversation, ZMMessageHiddenInConversationKey, conversation)
        let newClientPredicate = NSPredicate(format: "%K == %d", ZMMessageSystemMessageTypeKey, ZMSystemMessageType.newClient.rawValue)
        let containsSelfClient = NSPredicate(format: "ANY %K == %@", ZMMessageSystemMessageClientsKey, selfClient)
        let compound = NSCompoundPredicate(andPredicateWithSubpredicates: [conversationPredicate, newClientPredicate, containsSelfClient])
        
        let fetchRequest = ZMSystemMessage.sortedFetchRequest(with: compound)!
        let result = conversation.managedObjectContext!.executeFetchRequestOrAssert(fetchRequest)!
        return result.first as? ZMSystemMessage
    }
}

extension ZMMessage {
    
    /// True if the message is a "conversation degraded because of new client"
    /// system message
    fileprivate var isConversationNotVerifiedSystemMessage : Bool {
        guard let system = self as? ZMSystemMessage else { return false }
        return system.systemMessageType == .ignoredClient
    }
}
