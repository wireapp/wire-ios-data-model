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

actor CoreCryptoActor {

    // MARK: - Types

    enum Commit {

        case addMembers([Invitee])
        case removeClients([ClientId])
        case updateKeyMaterial
        case proposal

    }

    enum CoreCryptoActorError: Error {

        case failedToGenerateCommit
        case failedToSendCommit
        case failedToSendWelcome
        case failedToMergeCommit
        case failedToClearCommit
        case noPendingProposals

    }

    // MARK: - Properties

    private let coreCrypto: CoreCryptoProtocol
    private let context: NSManagedObjectContext
    private let actionsProvider: MLSActionsProviderProtocol

    // MARK: - Life cycle

    init(
        coreCrypto: CoreCryptoProtocol,
        context: NSManagedObjectContext,
        actionsProvider: MLSActionsProviderProtocol = MLSActionsProvider()
    ) {
        self.coreCrypto = coreCrypto
        self.context = context
        self.actionsProvider = actionsProvider
    }

    // MARK: - Methods

    func addMembers(_ invitees: [Invitee], to groupID: MLSGroupID) async throws -> [ZMUpdateEvent] {
        do {
            let bundle = try createCommit(for: .addMembers(invitees), in: groupID)
            let events = try await sendCommit(bundle.commit)
            try mergeCommit(in: groupID)

            if let welcome = bundle.welcome {
                try await sendWelcome(welcome)
            }

            return events

        } catch CoreCryptoActorError.failedToSendCommit {
            try clearPendingCommit(in: groupID)
            throw CoreCryptoActorError.failedToSendCommit
        }
    }

    func removeClients(_ clients: [ClientId], from groupID: MLSGroupID) async throws -> [ZMUpdateEvent] {
        do {
            let bundle = try createCommit(for: .removeClients(clients), in: groupID)
            let events = try await sendCommit(bundle.commit)
            try mergeCommit(in: groupID)
            return events
        } catch CoreCryptoActorError.failedToSendCommit {
            try clearPendingCommit(in: groupID)
            throw CoreCryptoActorError.failedToSendCommit
        }
    }

    func updateKeyMaterial(for groupID: MLSGroupID) async throws -> [ZMUpdateEvent] {
        do {
            let bundle = try createCommit(for: .updateKeyMaterial, in: groupID)
            let events = try await sendCommit(bundle.commit)
            try mergeCommit(in: groupID)
            return events
        } catch CoreCryptoActorError.failedToSendCommit {
            try clearPendingCommit(in: groupID)
            throw CoreCryptoActorError.failedToSendCommit
        }
    }

    func commitPendingProposals(in groupID: MLSGroupID) async throws -> [ZMUpdateEvent] {
        do {
            let bundle = try createCommit(for: .proposal, in: groupID)
            let events = try await sendCommit(bundle.commit)
            try mergeCommit(in: groupID)

            if let welcome = bundle.welcome {
                try await sendWelcome(welcome)
            }

            return events
        } catch CoreCryptoActorError.failedToSendCommit {
            try clearPendingCommit(in: groupID)
            throw CoreCryptoActorError.failedToSendCommit
        }
    }

    // MARK: - Helpers

    private func createCommit(for commit: Commit, in groupID: MLSGroupID) throws -> CommitBundle {
        do {
            switch commit {
            case .addMembers(let clients):
                let memberAddMessages = try coreCrypto.wire_addClientsToConversation(
                    conversationId: groupID.bytes,
                    clients: clients
                )

                return CommitBundle(
                    welcome: memberAddMessages.welcome,
                    commit: memberAddMessages.commit,
                    publicGroupState: memberAddMessages.publicGroupState
                )

            case .removeClients(let clients):
                return try coreCrypto.wire_removeClientsFromConversation(
                    conversationId: groupID.bytes,
                    clients: clients
                )

            case .updateKeyMaterial:
                return try coreCrypto.wire_updateKeyingMaterial(conversationId: groupID.bytes)

            case .proposal:
                guard let bundle = try coreCrypto.wire_commitPendingProposals(
                    conversationId: groupID.bytes
                ) else {
                    throw CoreCryptoActorError.noPendingProposals
                }

                return bundle
            }
        } catch {
            throw CoreCryptoActorError.failedToGenerateCommit
        }
    }

    private func sendCommit(_ bytes: Bytes) async throws -> [ZMUpdateEvent] {
        var events = [ZMUpdateEvent]()

        do {
            events = try await actionsProvider.sendMessage(
                bytes.data,
                in: context.notificationContext
            )
        } catch {
            throw CoreCryptoActorError.failedToSendCommit
        }

        return events
    }

    private func sendWelcome(_ message: Bytes) async throws {
        do {
            try await actionsProvider.sendWelcomeMessage(
                message.data,
                in: context.notificationContext
            )
        } catch {
            throw CoreCryptoActorError.failedToSendWelcome
        }
    }

    private func mergeCommit(in groupID: MLSGroupID) throws {
        do {
            try coreCrypto.wire_commitAccepted(conversationId: groupID.bytes)
        } catch {
            throw CoreCryptoActorError.failedToMergeCommit
        }
    }

    private func clearPendingCommit(in groupID: MLSGroupID) throws {
        do {
            try coreCrypto.wire_clearPendingCommit(conversationId: groupID.bytes)
        } catch {
            throw CoreCryptoActorError.failedToClearCommit
        }
    }

}
