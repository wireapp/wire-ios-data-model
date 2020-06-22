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

private var zmLog = ZMSLog(tag: "message encryption")

public let ZMFailedToCreateEncryptedMessagePayloadString = "💣"

// MARK: - Encrypted data for recipients

public protocol EncryptedPayloadGenerator {

    typealias Payload = (data: Data, strategy: MissingClientsStrategy)

    /// Produces a payload with encrypted data and the strategy to use to handle missing clients.

    func encryptForTransport() -> Payload?

    var debugInfo: String { get }

}

/// Strategy for handling missing clients.
///
/// When sending a message through the backend, the backend might warn us that some user clients that
/// were supposed to be there are missing (e.g. another user added a new client that we don't yet know about).
/// The various strategies give a hint to the backend of how we want to handle missing clients.

public enum MissingClientsStrategy: Equatable {

    /// Fail the request if there is any missing client.

    case doNotIgnoreAnyMissingClient

    /// Fail the request if there is any missing client for the given user, but ignore missing clients of
    /// any other user.

    case ignoreAllMissingClientsNotFromUsers(users: Set<ZMUser>)

    /// Do not fail the request, no matter which clients are missing.

    case ignoreAllMissingClients

}


extension ZMClientMessage: EncryptedPayloadGenerator {

    public func encryptForTransport() -> Payload? {
        guard let conversation = conversation else { return nil }
        return underlyingMessage?.encryptForTransport(for: conversation)
    }

    public var debugInfo: String {
        var info = "\(String(describing: underlyingMessage))"

        if let genericMessage = underlyingMessage, genericMessage.hasExternal {
            info = "External message: " + info
        }

        return info
    }

}


extension ZMAssetClientMessage: EncryptedPayloadGenerator {

    public func encryptForTransport() -> Payload? {
        guard let conversation = conversation else { return nil }
        return underlyingMessage?.encryptForTransport(for: conversation)
    }

    public var debugInfo: String {
        return "\(String(describing: underlyingMessage))"
    }
    
}

extension GenericMessage {

    /// Attempts to generate an encrypted payload for recipients in the given conversation.

    public func encryptForTransport(for conversation: ZMConversation,
                                    externalData: Data? = nil) -> EncryptedPayloadGenerator.Payload? {

        guard let context = conversation.managedObjectContext else { return nil }

        let selfUser = ZMUser.selfUser(in: context)
        let (users, missingClientsStrategy) = recipientUsersForMessage(in: conversation, selfUser: selfUser)
        let recipients = users.mapToDictionary { $0.clients }

        guard let data = encrypt(for: recipients, with: missingClientsStrategy, externalData: externalData, in: context) else {
            return nil
        }

        return (data, missingClientsStrategy)
    }


    /// Attempts to generate an encrypted payload for the given set of users.
    
    public func encryptForTransport(forBroadcastRecipients recipients: Set<ZMUser>,
                                    in context: NSManagedObjectContext) -> EncryptedPayloadGenerator.Payload? {

        // It's important to ignore all irrelevant missing clients, because otherwise the backend will enforce that
        // the message is sent to all team members and contacts.
        let missingClientsStrategy = MissingClientsStrategy.ignoreAllMissingClientsNotFromUsers(users: recipients)

        let messageRecipients = recipients.mapToDictionary { $0.clients }

        guard let data = encrypt(for: messageRecipients, with: missingClientsStrategy, in: context) else { return nil }

        return (data, missingClientsStrategy)
    }

    /// Attempts to generate an encrypted payload for the given collection of user clients.

    public func encryptForTransport(for recipients: [ZMUser: Set<UserClient>],
                                    in context: NSManagedObjectContext) -> EncryptedPayloadGenerator.Payload? {

        // We're targeting a specific client so we want to ignore all missing clients.
        let missingClientsStrategy = MissingClientsStrategy.ignoreAllMissingClients

        guard let data = encrypt(for: recipients, with: missingClientsStrategy, in: context) else { return nil }

        return (data, missingClientsStrategy)
    }


    private func encrypt(for recipients: [ZMUser: Set<UserClient>],
                         with missingClientsStrategy: MissingClientsStrategy,
                         externalData: Data? = nil,
                         in context: NSManagedObjectContext) -> Data? {

        guard
            let selfClient = ZMUser.selfUser(in: context).selfClient(),
            selfClient.remoteIdentifier != nil
        else {
            return nil
        }
        
        let encryptionContext = selfClient.keysStore.encryptionContext
        var messageData: Data?
        
        encryptionContext.perform { sessionsDirectory in
            let message = otrMessage(selfClient,
                                     recipients: recipients,
                                     missingClientsStrategy: missingClientsStrategy,
                                     externalData: externalData,
                                     sessionDirectory: sessionsDirectory)
            
            messageData = try? message.serializedData()
            
            // Message too big?
            if let data = messageData, UInt(data.count) > ZMClientMessage.byteSizeExternalThreshold && externalData == nil {
                // The payload is too big, we therefore rollback the session since we won't use the message we just encrypted.
                // This will prevent us advancing sender chain multiple time before sending a message, and reduce the risk of TooDistantFuture.
                sessionsDirectory.discardCache()
                messageData = self.encryptForTransportWithExternalDataBlob(for: recipients,
                                                                           with: missingClientsStrategy,
                                                                           in: context)
            }
        }
        
        // Reset all failed sessions.
        recipients.values
            .flatMap { $0 }
            .forEach { $0.failedToEstablishSession = false }

        return messageData
    }
    
    /// Returns a message for the given recipients.

    private func otrMessage(_ selfClient: UserClient,
                            recipients: [ZMUser: Set<UserClient>],
                            missingClientsStrategy: MissingClientsStrategy,
                            externalData: Data?,
                            sessionDirectory: EncryptionSessionsDirectory) -> NewOtrMessage {
        
        let userEntries = userEntriesWithEncryptedData(selfClient,
                                                       recipients: recipients,
                                                       sessionDirectory: sessionDirectory)

        // We do not want to send pushes for delivery receipts.
        let nativePush = !hasConfirmation
        
        var message = NewOtrMessage(withSender: selfClient,
                                    nativePush: nativePush,
                                    recipients: userEntries,
                                    blob: externalData)

        if case .ignoreAllMissingClientsNotFromUsers(let users) = missingClientsStrategy {
            message.reportMissing = Array(users.map{ $0.userId })
        }

        return message
    }

    private func userEntriesWithEncryptedData(_ selfClient: UserClient,
                                              recipients: [ZMUser: Set<UserClient>],
                                              sessionDirectory: EncryptionSessionsDirectory) -> [UserEntry] {

        return recipients.compactMap { (user, clients) in
            guard !user.isAccountDeleted else { return nil }
            
            let clientEntries = clientEntriesWithEncryptedData(selfClient,
                                                               userClients: clients,
                                                               sessionDirectory: sessionDirectory)

            guard !clientEntries.isEmpty else { return nil }

            return UserEntry(withUser: user, clientEntries: clientEntries)
        }
    }

    private func clientEntriesWithEncryptedData(_ selfClient: UserClient,
                                                userClients: Set<UserClient>,
                                                sessionDirectory: EncryptionSessionsDirectory) -> [ClientEntry] {

        return userClients.compactMap { client in
            guard client != selfClient else { return nil }
            return clientEntry(for: client, sessionDirectory: sessionDirectory)
        }
    }

    // Assumes it's not the self client.
    private func clientEntry(for client: UserClient, sessionDirectory: EncryptionSessionsDirectory) -> ClientEntry? {
        guard let sessionIdentifier = client.sessionIdentifier else { return nil }

        if sessionDirectory.hasSession(for: sessionIdentifier) {
            let encryptedData = try? sessionDirectory.encryptCaching(serializedData(), for: sessionIdentifier)
            guard let data = encryptedData else { return nil }
            return ClientEntry(withClient: client, data: data)

        } else if client.failedToEstablishSession {
            // If the session is corrupted, we will send a special payload.
            let data = ZMFailedToCreateEncryptedMessagePayloadString.data(using: String.Encoding.utf8)!
            return ClientEntry(withClient: client, data: data)

        }

        return nil
    }

    func recipientUsersForMessage(in conversation: ZMConversation, selfUser: ZMUser) -> (users: Set<ZMUser>, strategy: MissingClientsStrategy) {
        let (services, otherUsers) = conversation.localParticipants.categorizeServicesAndUser()

        func recipientForButtonActionMessage() -> Set<ZMUser> {
            guard
                case .buttonAction? = content,
                let managedObjectContext = conversation.managedObjectContext,
                let message = ZMMessage.fetch(withNonce: UUID(uuidString: buttonAction.referenceMessageID), for: conversation, in: managedObjectContext),
                let sender = message.sender
            else {
                fatal("buttonAction needs a recipient")
            }

            return Set(arrayLiteral: sender)
        }

        func recipientForConfirmationMessage() -> Set<ZMUser>? {
            guard
                hasConfirmation,
                let managedObjectContext = conversation.managedObjectContext,
                let message = ZMMessage.fetch(withNonce:UUID(uuidString: confirmation.firstMessageID), for:conversation, in:managedObjectContext),
                let sender = message.sender
                else {
                    return nil
            }

            return Set(arrayLiteral: sender)
        }

        func recipientForOtherUsers() -> Set<ZMUser>? {
            guard conversation.connectedUser != nil || (otherUsers.isEmpty == false) else { return nil }
            if let connectedUser = conversation.connectedUser { return Set(arrayLiteral:connectedUser) }
            return Set(otherUsers)
        }

        func recipientsForDeletedEphemeral() -> Set<ZMUser>? {
            guard
                case .deleted? = content,
                conversation.conversationType == .group
            else {
                return nil
            }

            let nonce = UUID(uuidString: self.deleted.messageID)

            guard
                let managedObjectContext = conversation.managedObjectContext,
                let message = ZMMessage.fetch(withNonce:nonce, for:conversation, in: managedObjectContext),
                message.destructionDate != nil
            else {
                return nil
            }

            guard let sender = message.sender else {
                zmLog.error("sender of deleted ephemeral message \(String(describing: self.deleted.messageID)) is already cleared \n ConvID: \(String(describing: conversation.remoteIdentifier)) ConvType: \(conversation.conversationType.rawValue)")
                return Set(arrayLiteral: selfUser)
            }

            // If self deletes their own message, we want to send a delete message for everyone, so return nil.
            guard !sender.isSelfUser else { return nil }

            // Otherwise we delete only for self and the sender, all other recipients are unaffected.
            return Set(arrayLiteral: sender, selfUser)
        }

        func allAuthorizedRecipients() -> Set<ZMUser> {
            if let connectedUser = conversation.connectedUser { return Set(arrayLiteral: connectedUser, selfUser) }

            func mentionedServices() -> Set<ZMUser> {
                return services.filter { service in
                    self.textData?.mentions.contains { $0.userID == service.remoteIdentifier?.transportString() } ?? false
                }
            }

            let authorizedServices = ZMUser.servicesMustBeMentioned ? mentionedServices() : services

            return otherUsers.union(authorizedServices).union([selfUser])
        }

        var recipientUsers = Set<ZMUser>()

        switch content {
        case .confirmation?:
            guard let recipients = recipientForConfirmationMessage() ?? recipientForOtherUsers() else {
                let confirmationInfo = ", original message: \(String(describing: self.confirmation.firstMessageID))"
                fatal("confirmation need a recipient\n ConvType: \(conversation.conversationType.rawValue) \(confirmationInfo)")
            }
            recipientUsers = recipients
        case .buttonAction?:
            recipientUsers = recipientForButtonActionMessage()
        default:
            if let deletedEphemeral = recipientsForDeletedEphemeral() {
                recipientUsers = deletedEphemeral
            } else {
                recipientUsers = allAuthorizedRecipients()
            }
        }

        let hasRestrictions: Bool = {
            if conversation.connectedUser != nil { return recipientUsers.count != 2 }
            return recipientUsers.count != conversation.localParticipants.count
        }()

        let strategy: MissingClientsStrategy = hasRestrictions
            ? .ignoreAllMissingClientsNotFromUsers(users: recipientUsers)
            : .doNotIgnoreAnyMissingClient

        return (recipientUsers, strategy)
    }
}

// MARK: - External

extension GenericMessage {
    
    /// Returns a message with recipients, with the content stored externally, and a strategy to handle missing clients.

    private func encryptForTransportWithExternalDataBlob(for conversation: ZMConversation) -> EncryptedPayloadGenerator.Payload? {
        guard let encryptedDataWithKeys = GenericMessage.encryptedDataWithKeys(from: self) else { return nil }
        let externalGenericMessage = GenericMessage(content: External(withKeyWithChecksum: encryptedDataWithKeys.keys))
        return externalGenericMessage.encryptForTransport(for: conversation, externalData: encryptedDataWithKeys.data)
    }
    
    private func encryptForTransportWithExternalDataBlob(for recipients: [ZMUser: Set<UserClient>],
                                                         with missingClientsStrategy: MissingClientsStrategy,
                                                         in context: NSManagedObjectContext) -> Data? {

        guard
            let encryptedDataWithKeys = GenericMessage.encryptedDataWithKeys(from: self),
            let data = encryptedDataWithKeys.data,
            let keys = encryptedDataWithKeys.keys
        else {
            return nil
        }

        let externalGenericMessage = GenericMessage(content: External(withKeyWithChecksum: keys))
        return externalGenericMessage.encrypt(for: recipients, with: missingClientsStrategy, externalData: data, in: context)
    }
}

// MARK: - Session identifier

extension UserClient {
    
    /// Session identifier of the local cryptobox session with this client.

    public var sessionIdentifier: EncryptionSessionIdentifier? {
        guard
            let userIdentifier = self.user?.remoteIdentifier,
            let clientIdentifier = self.remoteIdentifier
        else {
            return nil
        }

        return EncryptionSessionIdentifier(userId: userIdentifier.uuidString, clientId: clientIdentifier)
    }
    
    /// Previous (V1) session identifier.

    private var sessionIdentifier_V1: String? {
        return self.remoteIdentifier
    }
    
    /// Migrates from old session identifier to new session identifier if needed.

    public func migrateSessionIdentifierFromV1IfNeeded(sessionDirectory: EncryptionSessionsDirectory) {
        guard
            let sessionIdentifier_V1 = sessionIdentifier_V1,
            let sessionIdentifier = sessionIdentifier
        else {
            return
        }

        sessionDirectory.migrateSession(from: sessionIdentifier_V1, to: sessionIdentifier)
    }
}
