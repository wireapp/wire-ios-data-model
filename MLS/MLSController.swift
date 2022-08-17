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

    func uploadKeyPackagesIfNeeded()

    func createGroup(for groupID: MLSGroupID) throws

    func conversationExists(groupID: MLSGroupID) -> Bool

    func processWelcomeMessage(welcomeMessage: String) throws -> MLSGroupID

    func decrypt(message: String, for groupID: MLSGroupID) throws -> Data?

    func addMembersToConversation(with users: [MLSUser], for groupID: MLSGroupID) async throws

    func removeMembersFromConversation(with clientIds: [MLSClientID], for groupID: MLSGroupID) async throws
}

public final class MLSController: MLSControllerProtocol {

    // MARK: - Properties

    private weak var context: NSManagedObjectContext?
    private let coreCrypto: CoreCryptoProtocol
    private let conversationEventProcessor: ConversationEventProcessorProtocol
    private let logger = ZMSLog(tag: "core-crypto")

    let actionsProvider: MLSActionsProviderProtocol
    let targetUnclaimedKeyPackageCount = 100

    // MARK: - Life cycle

    init(
        context: NSManagedObjectContext,
        coreCrypto: CoreCryptoProtocol,
        conversationEventProcessor: ConversationEventProcessorProtocol,
        actionsProvider: MLSActionsProviderProtocol = MLSActionsProvider()
    ) {
        self.context = context
        self.coreCrypto = coreCrypto
        self.conversationEventProcessor = conversationEventProcessor
        self.actionsProvider = actionsProvider

        do {
            try generatePublicKeysIfNeeded()
        } catch {
            logger.error("failed to generate public keys: \(String(describing: error))")
        }
    }

    // MARK: - Public keys

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

        case noParticipantsToAdd
        case failedToClaimKeyPackages
        case failedToCreateGroup
        case failedToAddMembers
        case failedToSendHandshakeMessage
        case failedToSendWelcomeMessage

    }

    /// Create an MLS group with the given group id.
    ///
    /// - Parameters:
    ///   - groupID the id representing the MLS group.
    ///
    /// - Throws:
    ///   - MLSGroupCreationError if the group could not be created.

    public func createGroup(for groupID: MLSGroupID) throws {
        do {
            try coreCrypto.wire_createConversation(
                conversationId: groupID.bytes,
                config: ConversationConfiguration(ciphersuite: .mls128Dhkemx25519Aes128gcmSha256Ed25519)
            )
        } catch let error {
            logger.warn("failed to create mls group: \(String(describing: error))")
            throw MLSGroupCreationError.failedToCreateGroup
        }
    }

    private func claimKeyPackages(for users: [MLSUser]) async throws -> [KeyPackage] {
        do {
            guard let context = context else { return [] }

            var result = [KeyPackage]()

            for try await keyPackages in claimKeyPackages(for: users, in: context) {
                result.append(contentsOf: keyPackages)
            }

            return result
        } catch let error {
            logger.warn("failed to claim key packages: \(String(describing: error))")
            throw MLSGroupCreationError.failedToClaimKeyPackages
        }
    }

    private func claimKeyPackages(
        for users: [MLSUser],
        in context: NSManagedObjectContext
    ) -> AsyncThrowingStream<([KeyPackage]), Error> {
        var index = 0

        return AsyncThrowingStream { [actionsProvider] in
            guard let user = users.element(atIndex: index) else { return nil }

            index += 1

            return try await actionsProvider.claimKeyPackages(
                userID: user.id,
                domain: user.domain,
                excludedSelfClientID: user.selfClientID,
                in: context.notificationContext
            )
        }
    }

    private func sendMessage(_ bytes: Bytes) async throws {
        var updateEvents = [ZMUpdateEvent]()

        do {
            guard let context = context else { return }
            updateEvents = try await actionsProvider.sendMessage(
                bytes.data,
                in: context.notificationContext
            )
        } catch let error {
            logger.warn("failed to send mls message: \(String(describing: error))")
            throw MLSGroupCreationError.failedToSendHandshakeMessage
        }

        conversationEventProcessor.processConversationEvents(updateEvents)
    }

    private func sendWelcomeMessage(_ bytes:  Bytes) async throws {
        do {
            guard let context = context else { return }
            try await actionsProvider.sendWelcomeMessage(
                bytes.data,
                in: context.notificationContext
            )
        } catch let error {
            logger.warn("failed to send welcome message: \(String(describing: error))")
            throw MLSGroupCreationError.failedToSendWelcomeMessage
        }
    }

    // MARK: - Add participants to mls group

    /// Add users to MLS group in the given conversation.
    /// - Parameters:
    ///   - users: Users represents the MLS group to be added.
    ///   - groupID: Represents the MLS conversation group ID in which users to be added

    public func addMembersToConversation(with users: [MLSUser], for groupID: MLSGroupID) async throws {

        guard !users.isEmpty else {
            throw MLSGroupCreationError.noParticipantsToAdd
        }

        let keyPackages = try await claimKeyPackages(for: users)
        let invitees = keyPackages.map(Invitee.init(from:))
        let messagesToSend = try addMembers(id: groupID, invitees: invitees)

        guard let messagesToSend = messagesToSend else { return }
        try await sendMessage(messagesToSend.message)
        try await sendWelcomeMessage(messagesToSend.welcome)

    }

    private func addMembers(
        id: MLSGroupID,
        invitees: [Invitee]
    ) throws -> MemberAddedMessages? {

        do {
            return try coreCrypto.wire_addClientsToConversation(
                conversationId: id.bytes,
                clients: invitees
            )
        } catch let error {
            logger.warn("failed to add members: \(String(describing: error))")
            throw MLSGroupCreationError.failedToAddMembers
        }
    }

    // MARK: - Remove participants from mls group

    enum MLSRemoveParticipantsError: Error {

        case failedToRemoveMembers
        case noClientsToRemove

    }

    public func removeMembersFromConversation(
        with clientIds: [MLSClientID],
        for groupID: MLSGroupID
    ) async throws {

        guard !clientIds.isEmpty else {
            throw MLSRemoveParticipantsError.noClientsToRemove
        }
        
        let clientIds =  clientIds.compactMap { $0.string.utf8Data?.bytes }

        let messageToSend = try removeMembers(id: groupID, clientIds: clientIds)

        guard let messageToSend = messageToSend else { return }
        try await sendMessage(messageToSend)

    }

    private func removeMembers(
        id: MLSGroupID,
        clientIds: [ClientId]
    ) throws -> Bytes? {

        do {
            return try coreCrypto.wire_removeClientsFromConversation(
                conversationId: id.bytes,
                clients: clientIds
            )
        } catch let error {
            logger.error("failed to remove members: \(String(describing: error))")
            throw MLSRemoveParticipantsError.failedToRemoveMembers
        }
    }

    // MARK: - Key packages

    enum MLSKeyPackagesError: Error {

        case failedToGenerateKeyPackages
        case failedToCountUnclaimedKeyPackages

    }

    /// Uploads new key packages if needed.
    ///
    /// Checks how many key packages are available on the backend and
    /// generates new ones if there are less than 50% of the target unclaimed key package count..

    public func uploadKeyPackagesIfNeeded() {

        // TODO: Get actual key packages count from CoreCrypto once updated to latest. For now using a mock value of 50.
        let estimatedLocalKeyPackageCount  = 50
        let shouldCountRemainingKeyPackages = estimatedLocalKeyPackageCount < targetUnclaimedKeyPackageCount / 2
        let lastCheckWasMoreThen24Hours = UserDefaults.standard.hasMoreThan24HoursPassedSinceLastCheck

        // Check if need to query the backend
        guard lastCheckWasMoreThen24Hours || shouldCountRemainingKeyPackages else { return }

        guard
            let context = context,
            let clientID = ZMUser.selfUser(in: context).selfClient()?.remoteIdentifier
        else {
            return
        }

        Task {
            let unclaimedKeyPackageCount = try await countUnclaimedKeyPackages(clientID: clientID, context: context.notificationContext)

            UserDefaults.standard.lastKeyPackageCountDate = Date()

            guard unclaimedKeyPackageCount <= targetUnclaimedKeyPackageCount / 2 else { return }

            let amount = UInt32(targetUnclaimedKeyPackageCount - unclaimedKeyPackageCount)
            let keyPackages = try generateKeyPackages(amountRequested: amount)
            try await uploadKeyPackages(clientID: clientID, keyPackages: keyPackages, context: context.notificationContext)
        }
    }

    private func countUnclaimedKeyPackages(
        clientID: String,
        context: NotificationContext
    ) async throws -> Int {
        do {
            return try await actionsProvider.countUnclaimedKeyPackages(
                clientID: clientID,
                context: context
            )

        } catch let error {
            self.logger.warn("failed to count unclaimed key packages with error: \(String(describing: error))")
            throw MLSKeyPackagesError.failedToCountUnclaimedKeyPackages
        }
    }

    private func generateKeyPackages(amountRequested: UInt32) throws -> [String] {

        var keyPackages = [Bytes]()

        do {

            keyPackages = try coreCrypto.wire_clientKeypackages(amountRequested: amountRequested)

        } catch let error {
            logger.error("failed to generate new key packages: \(String(describing: error))")
            throw MLSKeyPackagesError.failedToGenerateKeyPackages
        }

        if keyPackages.isEmpty {
            logger.error("CoreCrypto generated empty key packages array")
            throw MLSKeyPackagesError.failedToGenerateKeyPackages
        }

        return keyPackages.map { $0.base64EncodedString } 
    }

    private func uploadKeyPackages(
        clientID: String,
        keyPackages: [String],
        context: NotificationContext
    ) async throws {

        do {
            try await actionsProvider.uploadKeyPackages(
                clientID: clientID,
                keyPackages: keyPackages,
                context: context
            )

        } catch let error {
            logger.warn("failed to upload key packages: \(String(describing: error))")
            throw MLSKeyPackagesError.failedToGenerateKeyPackages
        }
    }

    // MARK: - Process welcome message

    public enum MLSWelcomeMessageProcessingError: Error {

        case failedToConvertMessageToBytes
        case failedToProcessMessage
        
    }


    public func conversationExists(groupID: MLSGroupID) -> Bool {
        return coreCrypto.wire_conversationExists(conversationId: groupID.bytes)
    }

    public func processWelcomeMessage(welcomeMessage: String) throws -> MLSGroupID {
        guard let messageBytes = welcomeMessage.base64EncodedBytes else {
            logger.error("failed to convert welcome message to bytes")
            throw MLSWelcomeMessageProcessingError.failedToConvertMessageToBytes
        }

        do {
            let groupID = try coreCrypto.wire_processWelcomeMessage(welcomeMessage: messageBytes)
            uploadKeyPackagesIfNeeded()
            return MLSGroupID(groupID)
        } catch {
            logger.error("failed to process welcome message: \(String(describing: error))")
            throw MLSWelcomeMessageProcessingError.failedToProcessMessage
        }
    }

    // MARK: - Decrypting Message

    public enum MLSMessageDecryptionError: Error {

        case failedToConvertMessageToBytes
        case failedToDecryptMessage

    }

    /// Decrypts an MLS message for the given group
    ///
    /// - Parameters:
    ///   - message: a base64 encoded encrypted message
    ///   - groupID: the id of the MLS group
    ///
    /// - Returns:
    ///   The data representing the decrypted message bytes.
    ///   May be nil if the message was a handshake message, in which case it is safe to ignore.
    ///
    /// - Throws: `MLSMessageDecryptionError` if the message could not be decrypted

    public func decrypt(message: String, for groupID: MLSGroupID) throws -> Data? {

        guard let messageBytes = message.base64EncodedBytes else {
            throw MLSMessageDecryptionError.failedToConvertMessageToBytes
        }

        do {
            let decryptedMessageBytes = try coreCrypto.wire_decryptMessage(
                conversationId: groupID.bytes,
                payload: messageBytes
            )
            return decryptedMessageBytes?.data
        } catch {
            logger.warn("failed to decrypt message: \(String(describing: error))")
            throw MLSMessageDecryptionError.failedToDecryptMessage
        }
    }

}

// MARK: -  Helper types

public struct MLSUser: Equatable {

    public let id: UUID
    public let domain: String
    public let selfClientID: String?

    public init(
        id: UUID,
        domain: String,
        selfClientID: String? = nil
    ) {
        self.id = id
        self.domain = domain
        self.selfClientID = selfClientID
    }

    public init(from user: ZMUser) {
        id = user.remoteIdentifier
        domain = user.domain?.selfOrNilIfEmpty ?? APIVersion.domain!

        if user.isSelfUser, let selfClientID = user.selfClient()?.remoteIdentifier {
            self.selfClientID = selfClientID
        } else {
            selfClientID = nil
        }
    }

}

// MARK: - Helper Extensions

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

protocol MLSActionsProviderProtocol {

    func countUnclaimedKeyPackages(
        clientID: String,
        context: NotificationContext
    ) async throws -> Int

    func uploadKeyPackages(
        clientID: String,
        keyPackages: [String],
        context: NotificationContext
    ) async throws

    func claimKeyPackages(
        userID: UUID,
        domain: String?,
        excludedSelfClientID: String?,
        in context: NotificationContext
    ) async throws -> [KeyPackage]

    func sendMessage(
        _ message: Data,
        in context: NotificationContext
    ) async throws -> [ZMUpdateEvent]

    func sendWelcomeMessage(
        _ welcomeMessage: Data,
        in context: NotificationContext
    ) async throws

}

private class MLSActionsProvider: MLSActionsProviderProtocol {

    func countUnclaimedKeyPackages(
        clientID: String,
        context: NotificationContext
    ) async throws -> Int {
        var action = CountSelfMLSKeyPackagesAction(clientID: clientID)
        return try await action.perform(in: context)
    }



    func uploadKeyPackages(
        clientID: String,
        keyPackages: [String],
        context: NotificationContext
    ) async throws {
        var action = UploadSelfMLSKeyPackagesAction(
            clientID: clientID,
            keyPackages: keyPackages
        )

        try await action.perform(in: context)
    }

    func claimKeyPackages(
        userID: UUID,
        domain: String?,
        excludedSelfClientID: String?,
        in context: NotificationContext
    ) async throws -> [KeyPackage] {
        var action = ClaimMLSKeyPackageAction(
            domain: domain,
            userId: userID,
            excludedSelfClientId: excludedSelfClientID
        )

        return try await action.perform(in: context)
    }

    func sendMessage(
        _ message: Data,
        in context: NotificationContext
    ) async throws -> [ZMUpdateEvent] {
        var action = SendMLSMessageAction(message: message)
        return try await action.perform(in: context)
    }

    func sendWelcomeMessage(
        _ welcomeMessage: Data,
        in context: NotificationContext
    ) async throws {
        var action = SendMLSWelcomeAction(welcomeMessage: welcomeMessage)
        try await action.perform(in: context)
    }

}

public protocol ConversationEventProcessorProtocol {

    func processConversationEvents(_ events: [ZMUpdateEvent])

}

// MARK: - Helper

private extension UserDefaults {

    enum Keys {
        static let keyPackageQueriedTime = "keyPackageQueriedTime"
    }

    var lastKeyPackageCountDate: Date? {

        get { UserDefaults.standard.object(forKey: Keys.keyPackageQueriedTime) as? Date }
        set { set(newValue, forKey: Keys.keyPackageQueriedTime) }

    }

    var hasMoreThan24HoursPassedSinceLastCheck: Bool {

        guard let storedDate = lastKeyPackageCountDate else { return true }

        if Calendar.current.dateComponents([.hour], from: storedDate, to: Date()).hour > 24 {
            return true
        } else {
            return false
        }

    }
}
