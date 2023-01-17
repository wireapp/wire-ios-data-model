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

// Note: This is a temporary workaround the problem that we can't
// link to CoreCrypto from this project. The idea is to copy the public
// interface of CoreCrypto here, link it in the UI project, and inject
// it into this project.

// VersionL 0.3.0

// MARK: - Protocols

public protocol CoreCryptoProtocol {

    func wire_setCallbacks(callbacks: CoreCryptoCallbacks) throws
    func wire_clientPublicKey() throws -> [UInt8]
    func wire_clientKeypackages(amountRequested: UInt32) throws -> [[UInt8]]
    func wire_clientValidKeypackagesCount() throws -> UInt64
    func wire_createConversation(conversationId: ConversationId, config: ConversationConfiguration) throws
    func wire_conversationEpoch(conversationId: ConversationId) throws -> UInt64
    func wire_conversationExists(conversationId: ConversationId)  -> Bool
    func wire_processWelcomeMessage(welcomeMessage: [UInt8]) throws -> ConversationId
    func wire_addClientsToConversation(conversationId: ConversationId, clients: [Invitee]) throws -> MemberAddedMessages
    func wire_removeClientsFromConversation(conversationId: ConversationId, clients: [ClientId]) throws -> CommitBundle
    func wire_updateKeyingMaterial(conversationId: ConversationId) throws -> CommitBundle
    func wire_commitPendingProposals(conversationId: ConversationId) throws -> CommitBundle?
    func wire_wipeConversation(conversationId: ConversationId) throws
    func wire_decryptMessage(conversationId: ConversationId, payload: [UInt8]) throws -> DecryptedMessage
    func wire_encryptMessage(conversationId: ConversationId, message: [UInt8]) throws -> [UInt8]
    func wire_newAddProposal(conversationId: ConversationId, keyPackage: [UInt8]) throws -> ProposalBundle
    func wire_newUpdateProposal(conversationId: ConversationId) throws -> ProposalBundle
    func wire_newRemoveProposal(conversationId: ConversationId, clientId: ClientId) throws -> ProposalBundle
    func wire_newExternalAddProposal(conversationId: ConversationId, epoch: UInt64) throws -> [UInt8]
    func wire_newExternalRemoveProposal(conversationId: ConversationId, epoch: UInt64, keyPackageRef: [UInt8]) throws -> [UInt8]
    func wire_joinByExternalCommit(groupState: [UInt8]) throws -> ConversationInitBundle
    func wire_exportGroupState(conversationId: ConversationId) throws -> [UInt8]
    func wire_mergePendingGroupFromExternalCommit(conversationId: ConversationId, config: ConversationConfiguration) throws
    func wire_clearPendingGroupFromExternalCommit(conversationId: ConversationId) throws
    func wire_exportSecretKey(conversationId: ConversationId, keyLength: UInt32) throws -> [UInt8]
    func wire_getClientIds(conversationId: ConversationId) throws -> [ClientId]
    func wire_randomBytes(length: UInt32) throws -> [UInt8]
    func wire_reseedRng(seed: [UInt8]) throws
    func wire_commitAccepted(conversationId: ConversationId) throws
    func wire_clearPendingProposal(conversationId: ConversationId, proposalRef: [UInt8]) throws
    func wire_clearPendingCommit(conversationId: ConversationId) throws

    func wire_proteusInit() throws
    func wire_proteusSessionFromPrekey(sessionId: String, prekey: [UInt8]) throws
    func wire_proteusSessionFromMessage(sessionId: String, envelope: [UInt8]) throws -> [UInt8]
    func wire_proteusSessionSave(sessionId: String) throws
    func wire_proteusSessionDelete(sessionId: String) throws
    func wire_proteusDecrypt(sessionId: String, ciphertext: [UInt8]) throws -> [UInt8]
    func wire_proteusEncrypt(sessionId: String, plaintext: [UInt8]) throws -> [UInt8]
    func wire_proteusEncryptBatched(sessionId: [String], plaintext: [UInt8]) throws -> [String: [UInt8]]
    func wire_proteusNewPrekey(prekeyId: UInt16) throws -> [UInt8]
    func wire_proteusFingerprint() throws -> String
    func wire_proteusCryptoboxMigrate(path: String) throws

}

public protocol CoreCryptoCallbacks : AnyObject {

    func authorize(conversationId: ConversationId, clientId: ClientId)  -> Bool
    func userAuthorize(conversationId: ConversationId, externalClientId: ClientId, existingClients: [ClientId]) -> Bool
    func clientIsExistingGroupUser(clientId: ClientId, existingClients: [ClientId]) -> Bool

}

// MARK: - Structs

public struct CommitBundle: Equatable, Hashable {

    public var welcome: [UInt8]?
    public var commit: [UInt8]
    public var publicGroupState: PublicGroupStateBundle

    public init(
        welcome: [UInt8]?,
        commit: [UInt8],
        publicGroupState: PublicGroupStateBundle
    ) {
        self.welcome = welcome
        self.commit = commit
        self.publicGroupState = publicGroupState
    }
}

public struct ConversationConfiguration: Equatable, Hashable {

    public var admins: [MemberId]
    public var ciphersuite: CiphersuiteName?
    public var keyRotationSpan: TimeInterval?
    public var externalSenders: [[UInt8]]

    public init(
        admins: [MemberId] = [],
        ciphersuite: CiphersuiteName,
        keyRotationSpan: TimeInterval? = nil,
        externalSenders: [[UInt8]] = []
    ) {
        self.admins = admins
        self.ciphersuite = ciphersuite
        self.keyRotationSpan = keyRotationSpan
        self.externalSenders = externalSenders
    }
}

public struct DecryptedMessage: Equatable, Hashable {

    public var message: [UInt8]?
    public var proposals: [ProposalBundle]
    public var isActive: Bool
    public var commitDelay: UInt64?
    public var senderClientId: ClientId?

    public init(
        message: [UInt8]? = nil,
        proposals: [ProposalBundle],
        isActive: Bool,
        commitDelay: UInt64? = nil,
        senderClientId: ClientId? = nil
    ) {
        self.message = message
        self.proposals = proposals
        self.isActive = isActive
        self.commitDelay = commitDelay
        self.senderClientId = senderClientId
    }

}

public struct Invitee: Equatable, Hashable {

    public var id: ClientId
    public var kp: [UInt8]

    public init(
        id: ClientId,
        kp: [UInt8]
    ) {
        self.id = id
        self.kp = kp
    }
}

public struct MemberAddedMessages: Equatable, Hashable {

    public var commit: [UInt8]
    public var welcome: [UInt8]
    public var publicGroupState: PublicGroupStateBundle

    public init(
        commit: [UInt8],
        welcome: [UInt8],
        publicGroupState: PublicGroupStateBundle
    ) {
        self.commit = commit
        self.welcome = welcome
        self.publicGroupState = publicGroupState
    }
}

public struct ConversationInitBundle: Equatable, Hashable {

    public var conversationId: ConversationId
    public var commit: [UInt8]
    public var publicGroupState: PublicGroupStateBundle

    public init(
        conversationId: ConversationId,
        commit: [UInt8],
        publicGroupState: PublicGroupStateBundle
    ) {
        self.conversationId = conversationId
        self.commit = commit
        self.publicGroupState = publicGroupState
    }
}

public struct PublicGroupStateBundle: Equatable, Hashable {

    public var encryptionType: PublicGroupStateEncryptionType
    public var ratchetTreeType: RatchetTreeType
    public var payload: [UInt8]

    public init(
        encryptionType: PublicGroupStateEncryptionType,
        ratchetTreeType: RatchetTreeType,
        payload: [UInt8]
    ) {
        self.encryptionType = encryptionType
        self.ratchetTreeType = ratchetTreeType
        self.payload = payload
    }
}

public struct ProposalBundle: Equatable, Hashable {

    public var proposal: [UInt8]
    public var proposalRef: [UInt8]

    public init(
        proposal: [UInt8],
        proposalRef: [UInt8]
    ) {
        self.proposal = proposal
        self.proposalRef = proposalRef
    }

}

// MARK: - Enums

public enum PublicGroupStateEncryptionType: Equatable, Hashable {

    case Plaintext
    case JweEncrypted

}

public enum RatchetTreeType: Equatable, Hashable {

    case Full
    case Delta
    case ByRef

}

public enum CiphersuiteName: Equatable, Hashable {

    case mls128Dhkemx25519Aes128gcmSha256Ed25519
    case mls128Dhkemp256Aes128gcmSha256P256
    case mls128Dhkemx25519Chacha20poly1305Sha256Ed25519
    case mls256Dhkemx448Aes256gcmSha512Ed448
    case mls256Dhkemp521Aes256gcmSha512P521
    case mls256Dhkemx448Chacha20poly1305Sha512Ed448
    case mls256Dhkemp384Aes256gcmSha384P384

}

public enum CryptoError: Error, Equatable, Hashable {

    // Simple error enums only carry a message
    case ConversationNotFound(message: String)

    // Simple error enums only carry a message
    case ClientNotFound(message: String)

    // Simple error enums only carry a message
    case PendingProposalNotFound(message: String)

    // Simple error enums only carry a message
    case PendingCommitNotFound(message: String)

    // Simple error enums only carry a message
    case MalformedIdentifier(message: String)

    // Simple error enums only carry a message
    case ClientSignatureNotFound(message: String)

    // Simple error enums only carry a message
    case ClientSignatureMismatch(message: String)

    // Simple error enums only carry a message
    case LockPoisonError(message: String)

    // Simple error enums only carry a message
    case ImplementationError(message: String)

    // Simple error enums only carry a message
    case OutOfKeyPackage(message: String)

    // Simple error enums only carry a message
    case MlsProviderError(message: String)

    // Simple error enums only carry a message
    case KeyStoreError(message: String)

    // Simple error enums only carry a message
    case MlsError(message: String)

    // Simple error enums only carry a message
    case Utf8Error(message: String)

    // Simple error enums only carry a message
    case StringUtf8Error(message: String)

    // Simple error enums only carry a message
    case ParseIntError(message: String)

    // Simple error enums only carry a message
    case ConvertIntError(message: String)

    // Simple error enums only carry a message
    case InvalidByteArrayError(message: String)

    // Simple error enums only carry a message
    case IoError(message: String)

    // Simple error enums only carry a message
    case Unauthorized(message: String)

    // Simple error enums only carry a message
    case CallbacksNotSet(message: String)

    // Simple error enums only carry a message
    case ExternalAddProposalError(message: String)

    // Simple error enums only carry a message
    case InvalidHashReference(message: String)

    // Simple error enums only carry a message
    case GenerationOutOfBound(message: String)

}

// MARK: - Type aliases

public typealias ClientId = [UInt8]
public typealias ConversationId = [UInt8]
public typealias MemberId = [UInt8]
public typealias TlsCommitBundle = [UInt8]