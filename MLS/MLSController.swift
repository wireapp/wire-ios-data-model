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

public final class MLSController {

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

    // MARK: - Methods

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

    @available(iOS 13, *)
    func createGroup(for conversation: ZMConversation) {
        Task {
            guard let context = context else { return }
            guard let groupID = conversation.mlsGroupID else { return }

            let allKeyPackages = claimKeyPackages(
                for: Array(conversation.localParticipants),
                in: context
            )

            // Collect all the key packages.
            var buffer = [KeyPackage]()

            do {
                for try await keyPackages in allKeyPackages {
                    buffer.append(contentsOf: keyPackages)
                }
            } catch let error {
                fatalError("Failed to claim key packages: \(String(describing: error))")
            }

            // Deafult config for the group.
            let config = ConversationConfiguration(
                extraMembers: [],
                admins: [],
                ciphersuite: .mls128Dhkemx25519Aes128gcmSha256Ed25519,
                keyRotationSpan: nil
            )

            var messagesToPost: MemberAddedMessages?

            do {
                messagesToPost = try coreCrypto.wire_createConversation(
                    conversationId: groupID.bytes,
                    config: config
                )

                // TODO: check if messagesToPost is nil after creating the conversation.

            } catch let error {
                fatalError("Failed to create mls group: \(String(describing: error))")
            }

            do {
                messagesToPost = try coreCrypto.wire_addClientsToConversation(
                    conversationId: groupID.bytes,
                    clients: buffer.map(Invitee.init(from:))
                )

                // TODO: post messagesToPost.message
                // TODO: post messagesToPost.welcom

            } catch let error {
                fatalError("Failed to add clients to the conversation: \(String(describing: error))")
            }
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

}

private extension EntityAction {

    @available(*, renamed: "perform(in:)")
    mutating func perform(
        in context: NotificationContext,
        resultHandler: @escaping ResultHandler
    ) {
        self.resultHandler = resultHandler
        send(in: context)
    }

    @available(iOS 13, *)
    mutating func perform(in context: NotificationContext) async throws -> Result {
        return try await withCheckedThrowingContinuation { continuation in
            perform(in: context, resultHandler: continuation.resume(with:))
        }
    }

}

extension ZMUser {

    var mlsClientID: String {
        return ""
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

private extension String {

    var utf8Data: Data? {
        return data(using: .utf8)
    }

    var base64DecodedData: Data? {
        return Data(base64Encoded: self)
    }


}

struct MLSClientID: Equatable {

    private let userID: String
    private let clientID: String
    private let domain: String

    let string: String

    init?(userClient: UserClient) {
        guard
            let userID = userClient.user?.remoteIdentifier.uuidString,
            let clientID = userClient.remoteIdentifier,
            let domain = userClient.user?.domain ?? APIVersion.domain
        else {
            return nil
        }

        self.init(
            userID: userID,
            clientID: clientID,
            domain: domain
        )
    }

    init(
        userID: String,
        clientID: String,
        domain: String
    ) {
        self.userID = userID.lowercased()
        self.clientID = clientID.lowercased()
        self.domain = domain.lowercased()
        self.string = "\(self.userID):\(self.clientID)@\(self.domain)"
    }

}
