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
import ZMUtilities


extension ZMMessage {

    func updateNormalizedText() {
        // no-op
    }

}

extension ZMClientMessage {

    override func updateNormalizedText() {
        // TODO: Check transforms
        if let normalized = textMessageData?.messageText?.normalized() as? String {
            normalizedText = normalized
        } else {
            normalizedText = ""
        }
    }

}

extension ZMClientMessage {

    static func predicateForMessagesMatching(_ query: String) -> NSPredicate {
        let components = query.components(separatedBy: .whitespaces)
        let predicates = components.map { NSPredicate(format: "%K CONTAINS[n] %@", #keyPath(ZMMessage.normalizedText), $0) }
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    static func predicateForMessages(inConversationWith identifier: UUID) -> NSPredicate {
        return NSPredicate(
            format: "%K.%K == %@",
            ZMMessageConversationKey,
            ZMConversationRemoteIdentifierDataKey,
            (identifier as NSUUID).data() as NSData
        )
    }

    static func predicateForNotIndexedMessages() -> NSPredicate {
        return NSPredicate(format: "%K == NULL", #keyPath(ZMMessage.normalizedText))
    }

    static func predicateForIndexedMessages() -> NSPredicate {
        return NSPredicate(format: "%K != NULL", #keyPath(ZMMessage.normalizedText))
    }

}


// TODO: Move into correct Framework (wire-ios-utilities)
public func &&(lhs: NSPredicate, rhs: NSPredicate) -> NSPredicate {
    return NSCompoundPredicate(andPredicateWithSubpredicates: [lhs, rhs])
}

// TODO: Move into correct Framework (wire-ios-utilities)
public func &&(lhs: NSPredicate, rhs: NSPredicate?) -> NSPredicate {
    guard let rhs = rhs else { return lhs }
    return NSCompoundPredicate(andPredicateWithSubpredicates: [lhs, rhs])
}

// TODO: Move into correct Framework (wire-ios-utilities)
public func ||(lhs: NSPredicate, rhs: NSPredicate) -> NSPredicate {
    return NSCompoundPredicate(orPredicateWithSubpredicates: [lhs, rhs])
}


public protocol TextSearchQueryDelegate: class {
    func textSearchQueryDidReceive(result: TextQueryResult)
}

public class TextQueryResult: NSObject {
    public var matches: [ZMMessage]
    public var hasMore: Bool
    public weak var query: TextSearchQuery?

    init(query: TextSearchQuery?, matches: [ZMMessage], hasMore: Bool) {
        self.query = query
        self.matches = matches
        self.hasMore = hasMore
    }

    func updated(appending matches: [ZMMessage], hasMore: Bool) -> TextQueryResult {
        return TextQueryResult(query: self.query, matches: self.matches + matches, hasMore: hasMore)
    }
}


// TODO: Add Documentation
public class TextSearchQuery: NSObject {

    private let uiMOC: NSManagedObjectContext
    private let syncMOC: NSManagedObjectContext

    private let conversationRemoteIdentifier: UUID
    private let conversation: ZMConversation
    private let query: String

    let notIndexedBatchSize = 200
    let indexedBatchSize = 200

    private weak var delegate: TextSearchQueryDelegate?

    private var cancelled = false
    private var executed = false

    private var result: TextQueryResult?


    public init?(conversation: ZMConversation, query: String, delegate: TextSearchQueryDelegate) {
        guard query.characters.count > 0 else { return nil }
        guard let uiMOC = conversation.managedObjectContext, let syncMOC = uiMOC.zm_sync else {
            fatal("NSManagedObjectContexts not accessible")
        }

        self.uiMOC = uiMOC
        self.syncMOC = syncMOC
        self.conversation = conversation
        self.conversationRemoteIdentifier = conversation.remoteIdentifier!
        self.query = query.normalized() as String
        self.delegate = delegate
    }

    /// Start the search, the delegate will be called with 
    /// results one or more times if not cancelled.
    public func execute() {
        precondition(!executed, "Trying to re-execute an already executed query")
        executed = true
        syncMOC.performGroupedBlock {
            self.executeQueryForIndexedMessages(totalCount: self.countForIndexedMessages()) { [weak self] in
                self?.executeQueryForNonIndexedMessages()
            }
        }
    }

    /// Cancel the current search query.
    /// A new `TextSearchQuery` object has to be created to start a new search.
    public func cancel() {
        cancelled = true
    }

    /// Fetches the next batch of indexed messages in a conversation and notifies
    /// the delegate about the result.
    /// - param callCount The number of times this method has been called recursivly, used the compute the `fetchOffset`
    /// - param totalCount The total amount of indexed messages in the conversation
    /// - param completion The completion handler which will be called after all indexed messages have been queried
    private func executeQueryForIndexedMessages(callCount: Int = 0, totalCount: Int, completion: @escaping () -> Void) {
        guard !self.cancelled else { return }
        guard totalCount > 0 else { return completion() }

        let predicate = ZMClientMessage.predicateForIndexedMessages() && predicateForQueryMatch
        print(predicate)

        syncMOC.performGroupedBlock { [weak self] in
            guard let `self` = self else { return }
            let request = ZMClientMessage.sortedFetchRequest(with: predicate)
            request?.fetchLimit = self.indexedBatchSize
            request?.fetchOffset = callCount * self.indexedBatchSize

            guard let matches = self.syncMOC.executeFetchRequestOrAssert(request) as? [ZMClientMessage] else { return completion() }

            // Notify the delegate
            let nextOffset = (callCount + 1) * self.indexedBatchSize
            let needsMoreFetches = nextOffset < totalCount
            self.notifyDelegate(with: matches, hasMore: needsMoreFetches)

            if needsMoreFetches {
                self.executeQueryForIndexedMessages(callCount: callCount + 1, totalCount: totalCount, completion: completion)
            } else {
                completion()
            }
        }
    }

    /// Fetches the next batch of not indexed messages in a conversation and updates
    /// their `noralizedText` property. After the indexing the indexed messages
    /// are queried for the search term and the delegate is notified.
    private func executeQueryForNonIndexedMessages() {
        guard !self.cancelled && countForNonIndexedMessages() > 0 else { return }

        let nonIndexPredicate = predicateForNotIndexedMessages
        let queryPredicate = predicateForQueryMatch

        syncMOC.performGroupedBlock { [weak self] in
            guard let `self` = self else { return }
            let request = ZMClientMessage.sortedFetchRequest(with: nonIndexPredicate)
            request?.fetchLimit = self.notIndexedBatchSize

            guard let messagesToIndex = self.syncMOC.executeFetchRequestOrAssert(request) as? [ZMClientMessage] else { return }
            messagesToIndex.forEach {
                $0.updateNormalizedText()
            }
            self.syncMOC.saveOrRollback()

            let matches = (messagesToIndex as NSArray).filtered(using: queryPredicate)
            let hasMore = messagesToIndex.count == self.notIndexedBatchSize

            // Notify the delegate
            self.notifyDelegate(with: matches as! [ZMMessage], hasMore: hasMore)

            if hasMore {
                self.executeQueryForNonIndexedMessages()
            }
        }
    }

    /// Fetches the objects on the UI context and notifies the delegate
    private func notifyDelegate(with messages: [ZMMessage], hasMore: Bool) {
        let objectIDs = messages.map { $0.objectID }
        uiMOC.performGroupedBlock { [weak self] in
            guard let `self` = self else { return }
            let uiMessages = objectIDs.flatMap {
                (try? self.uiMOC.existingObject(with: $0)) as? ZMMessage
            }

            let queryResult = self.result?.updated(appending: uiMessages, hasMore: hasMore)
                           ?? TextQueryResult(query: self, matches: uiMessages, hasMore: hasMore)
    
            self.result = queryResult
            self.delegate?.textSearchQueryDidReceive(result: queryResult)
        }
    }

    /// Returns the count of indexed messages. Needs to be called from the syncMOC's Queue.
    private func countForIndexedMessages() -> Int {
        let predicate = ZMClientMessage.predicateForIndexedMessages()
                     && ZMClientMessage.predicateForMessages(inConversationWith: conversationRemoteIdentifier)
        guard let request = ZMClientMessage.sortedFetchRequest(with: predicate) else { return 0 }
        return (try? self.syncMOC.count(for: request)) ?? 0
    }

    /// Returns the count of not indexed indexed messages. Needs to be called from the syncMOC's Queue.
    private func countForNonIndexedMessages() -> Int {
        guard let request = ZMMessage.sortedFetchRequest(with: predicateForNotIndexedMessages) else { return 0 }
        return (try? self.syncMOC.count(for: request)) ?? 0
    }

    private lazy var predicateForQueryMatch: NSPredicate = {
        return ZMClientMessage.predicateForMessagesMatching(self.query)
            && ZMClientMessage.predicateForMessages(inConversationWith: self.conversationRemoteIdentifier)
    }()

    private lazy var predicateForNotIndexedMessages: NSPredicate = {
        return ZMClientMessage.predicateForNotIndexedMessages()
            && ZMClientMessage.predicateForMessages(inConversationWith: self.conversationRemoteIdentifier)
    }()

}

