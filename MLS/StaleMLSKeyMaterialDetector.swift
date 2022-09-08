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

protocol StaleMLSKeyDetectorProtocol {

    /// The number of days before a key is considered stale.

    var keyLifetimeInDays: UInt { get set }

    /// All group IDs for groups requiring a key update.

    var groupsWithStaleKeyingMaterial: Set<MLSGroupID> { get }

    /// Notify the detector that keying material was updated.
    ///
    /// - Parameters:
    ///   - groupID: the ID of the group in which the keying material was updated

    func keyingMaterialUpdated(for groupID: MLSGroupID)

}

final class StaleMLSKeyDetector: StaleMLSKeyDetectorProtocol {

    // MARK: - Properties

    var keyLifetimeInDays: UInt
    let context: NSManagedObjectContext

    // MARK: - Life cycle

    init(
        keyLifetimeInDays: UInt,
        context: NSManagedObjectContext
    ) {
        self.keyLifetimeInDays = keyLifetimeInDays
        self.context = context
    }

    // TODO: test
    var groupsWithStaleKeyingMaterial: Set<MLSGroupID> {
        let result = fetchMLSConversations().lazy
            .filter(isKeyingMaterialStale)
            .compactMap(\.mlsGroupID)

        return Set(result)
    }

    // TODO: test
    func keyingMaterialUpdated(for groupID: MLSGroupID) {
        Logging.mls.info("Tracking key material update date for group (\(groupID))")

        context.perform {
            guard let conversation = ZMConversation.fetch(
                with: groupID,
                domain: "",
                in: self.context
            ) else {
                Logging.mls.warn("Can't upload key material for group (\(groupID)): conversation not found in db")
                return
            }

            conversation.lastMLSKeyMaterialUpdateDate = Date()
            self.context.enqueueDelayedSave()
        }
    }

    // MARK: - Helpers

    private func fetchMLSConversations() -> Set<ZMConversation> {
        let request = NSFetchRequest<ZMConversation>(entityName: ZMConversation.entityName())

        request.predicate = NSPredicate(
            format: "%@ == %@",
            ZMConversation.messageProtocolKey, MessageProtocol.mls.rawValue
        )

        let mlsConversations = context.fetchOrAssert(request: request)
        return Set(mlsConversations)
    }

    private func isKeyingMaterialStale(for conversation: ZMConversation) -> Bool {
        guard let lastUpdateDate = conversation.lastMLSKeyMaterialUpdateDate else {
            Logging.mls.info("last key material update date for group (\(String(describing: conversation.mlsGroupID)) doesn't exist... considering stale")
            return true
        }

        guard numberOfDays(since: lastUpdateDate) > keyLifetimeInDays else {
            return false
        }

        Logging.mls.info("key material for group (\(String(describing: conversation.mlsGroupID))) is stale")
        return true
    }

    private func numberOfDays(since date: Date) -> Int {
        let now = Date()
        return Calendar.current.dateComponents([.day], from: date, to: now).day ?? 0
    }

}
