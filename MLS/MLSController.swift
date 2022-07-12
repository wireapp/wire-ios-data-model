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

public protocol MLSControllerProtocol {

    @available(iOS 13, *)
    func createGroup(for conversation: ZMConversation) throws

}

public final class MLSController: MLSControllerProtocol {

    // MARK: - Properties

    private weak var context: NSManagedObjectContext?
    private let coreCrypto: CoreCryptoProtocol
    private let logger = ZMSLog(tag: "core-crypto")

    // MARK: - Life cycle

    init(
        context: NSManagedObjectContext,
        coreCrypto: CoreCryptoProtocol
    ) {
        self.context = context
        self.coreCrypto = coreCrypto

        do {
            try generatePublicKeysIfNeeded()
        } catch {
            logger.error("failed to generate public keys: \(String(describing: error))")
        }
    }

    // MARK: - Public key

    private func generatePublicKeysIfNeeded() throws {
        guard
            let context = context,
            let selfClient = ZMUser.selfUser(in: context).selfClient()
        else {
            return
        }

        var keys = selfClient.mlsPublicKeys

        if keys.ed25519 == nil {
            let keyBytes = try coreCrypto.wire_clientPublicKey()
            let keyData = Data(keyBytes)
            keys.ed25519 = keyData.base64EncodedString()
        }

        selfClient.mlsPublicKeys = keys
        context.saveOrRollback()
    }

    // MARK: - Group creation

    enum MLSGroupCreationError: Error {

        case noGroupID
        case notAnMLSConversation
        case failedToClaimKeyPackages
        case failedToCreateGroup
        case failedToAddMembers
        case noMessagesToSend
        case failedToSendHandshakeMessage
        case failedToSendWelcomeMessage

    }

    /// Create an MLS group with the given conversation.
    ///
    /// - Parameters:
    ///   - conversation the conversation representing the MLS group.
    ///
    /// - Throws:
    ///   - MLSGroupCreationError if the group could not be created.

    @available(iOS 13, *)
    public func createGroup(for conversation: ZMConversation) throws {
        Task {
            guard let groupID = conversation.mlsGroupID else {
                throw MLSGroupCreationError.noGroupID
            }

            guard conversation.messageProtocol == .mls else {
                throw MLSGroupCreationError.notAnMLSConversation
            }

            let keyPackages = try await claimKeyPackages(for: Array(conversation.localParticipants))
            let invitees = keyPackages.map(Invitee.init(from:))
            let messagesToSend = try createGroup(id: groupID, invitees: invitees)
            try await sendMessage(messagesToSend.message)
            try await sendWelcomeMessage(messagesToSend.welcome)
        }
    }

    @available(iOS 13, *)
    private func claimKeyPackages(for users: [ZMUser]) async throws -> [KeyPackage] {
        do {
            guard let context = context else { return [] }

            var result = [KeyPackage]()

            for try await keyPackages in claimKeyPackages(for: users, in: context) {
                result.append(contentsOf: keyPackages)
            }

            return result
        } catch let error {
            logger.error("failed to claim key packages: \(String(describing: error))")
            throw MLSGroupCreationError.failedToClaimKeyPackages
        }

    }

    @available(iOS 13, *)
    private func claimKeyPackages(
        for users: [ZMUser],
        in context: NSManagedObjectContext
    ) -> AsyncThrowingStream<([KeyPackage]), Error> {
        var index = 0

        return AsyncThrowingStream {
            guard let user = users.element(atIndex: index) else { return nil }

            index += 1

            var action = ClaimMLSKeyPackageAction(
                domain: user.domain,
                userId: user.remoteIdentifier,
                excludedSelfClientId: user.isSelfUser ? user.selfClient()?.remoteIdentifier : nil
            )

            return try await action.perform(in: context.notificationContext)
        }
    }

    private func createGroup(
        id: MLSGroupID,
        invitees: [Invitee]
    ) throws -> MemberAddedMessages {
        var messagesToSend: MemberAddedMessages?
        let config = ConversationConfiguration(ciphersuite: .mls128Dhkemx25519Aes128gcmSha256Ed25519)

        do {
            messagesToSend = try coreCrypto.wire_createConversation(
                conversationId: id.bytes,
                config: config
            )

            // TODO: check if messagesToPost is nil after creating the conversation.

        } catch let error {
            logger.error("failed to create mls group: \(String(describing: error))")
            throw MLSGroupCreationError.failedToCreateGroup
        }

        do {
            messagesToSend = try coreCrypto.wire_addClientsToConversation(
                conversationId: id.bytes,
                clients: invitees
            )
        } catch let error {
            logger.error("failed to add members: \(String(describing: error))")
            throw MLSGroupCreationError.failedToAddMembers
        }

        guard let messagesToSend = messagesToSend else {
            logger.error("added participants, but no messages to send")
            throw MLSGroupCreationError.noMessagesToSend
        }

        return messagesToSend
    }

    @available(iOS 13, *)
    private func sendMessage(_ bytes: [UInt8]) async throws {
        do {
            guard let context = context else { return }
            var action = SendMLSMessageAction(mlsMessage: bytes.base64EncodedString)
            try await action.perform(in: context.notificationContext)
        } catch let error {
            logger.error("failed to send mls message: \(String(describing: error))")
            throw MLSGroupCreationError.failedToSendHandshakeMessage
        }
    }

    @available(iOS 13, *)
    private func sendWelcomeMessage(_ bytes: [UInt8]) async throws {
        do {
            guard let context = context else { return }
            var action = SendMLSWelcomeAction(body: bytes.base64EncodedString)
            try await action.perform(in: context.notificationContext)
        } catch let error {
            logger.error("failed to send welcome message: \(String(describing: error))")
            throw MLSGroupCreationError.failedToSendWelcomeMessage
        }
    }

}

// MARK: - Helper Extensions

private extension Array where Element == UInt8 {

    var base64EncodedString: String {
        return Data(self).base64EncodedString()
    }

}

private extension String {

    var utf8Data: Data? {
        return data(using: .utf8)
    }

    var base64DecodedData: Data? {
        return Data(base64Encoded: self)
    }

}

extension Invitee {

    init(from keyPackage: KeyPackage) {
        let id = MLSClientID(
            userID: keyPackage.userID.uuidString,
            clientID: keyPackage.client,
            domain: keyPackage.domain
        )

        guard
            let idData = id.string.utf8Data,
            let keyPackageData = Data(base64Encoded: keyPackage.keyPackage)
        else {
            fatalError("Couldn't create Invitee from key package: \(keyPackage)")
        }

        self.init(
            id: idData.bytes,
            kp: keyPackageData.bytes
        )
    }

}
