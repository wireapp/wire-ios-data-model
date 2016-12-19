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

public enum AssetFetchResult : Int {
    case success, failed, noAssetsToFetch
}

public protocol ZMCollection : NSObjectProtocol {
    func tearDown()
    func assets(for category: MessageCategory) -> [ZMMessage]
}

public protocol AssetCollectionDelegate : NSObjectProtocol {
    /// The AssetCollection calls this when the fetching completes
    /// To get all messages for any category defined in `including`, call `assets(for category: MessageCategory)`
    func assetCollectionDidFetch(collection: ZMCollection, messages: [MessageCategory: [ZMMessage]], hasMore: Bool)
    
    /// This method is called when all assets in the conversation have been fetched & analyzed / categorized
    func assetCollectionDidFinishFetching(collection: ZMCollection, result : AssetFetchResult)
}


public class AssetCollection : NSObject, ZMCollection {

    private unowned var delegate : AssetCollectionDelegate
    private var assets : Dictionary<MessageCategory, [ZMMessage]>?
    private var lastAssetMessage : ZMAssetClientMessage?
    private var lastClientMessage : ZMClientMessage?
    private let conversation: ZMConversation
    private let including : [MessageCategory]
    private let excluding : MessageCategory

    enum MessagesToFetch {
        case client, asset
    }
    
    public static let initialFetchCount = 100
    public static let defaultFetchCount = 500
    public private (set) var doneFetchingAssets : Bool = false
    public private (set) var doneFetchingTexts : Bool = false

    private var tornDown = false {
        didSet {
            doneFetchingAssets = true
            doneFetchingTexts = true
        }
    }

    var doneFetching : Bool {
        return doneFetchingTexts && doneFetchingAssets
    }
    
    private var syncMOC: NSManagedObjectContext? {
        return conversation.managedObjectContext?.zm_sync
    }
    private var uiMOC: NSManagedObjectContext? {
        return conversation.managedObjectContext
    }
    
    /// Returns a collection that automatically fetches the assets in batches
    /// @param categoriesToFetch: The AssetCollection only returns and calls the delegate for these categories
    public init(conversation: ZMConversation, including : [MessageCategory], excluding: [MessageCategory] = [], delegate: AssetCollectionDelegate){
        self.conversation = conversation
        self.delegate = delegate
        self.including = including
        self.excluding = excluding.reduce(.none){$0.union($1)}
        super.init()
        
        syncMOC?.performGroupedBlock {
            guard !self.tornDown else { return }
            guard let syncConversation = (try? self.syncMOC?.existingObject(with: self.conversation.objectID)) as? ZMConversation else {
                return
            }
            
            let categorizedMessages : [ZMMessage] = self.categorizedMessages(for: syncConversation)
            if categorizedMessages.count > 0 {
                self.assets = AssetCollectionBatched.messageMap(messages: categorizedMessages, including: self.including, excluding: self.excluding)
                self.notifyDelegate(newAssets: self.assets!, type: nil, didReachLastMessage: false)
            }
            
            self.fetchNextIfNotTornDown(limit: AssetCollection.initialFetchCount, type: .asset, syncConversation: syncConversation)
            self.fetchNextIfNotTornDown(limit: AssetCollection.initialFetchCount, type: .client, syncConversation: syncConversation)
        }

    }
    
    /// Cancels further fetch requests
    public func tearDown() {
        tornDown = true
        doneFetchingAssets = true
        doneFetchingTexts = true
    }
    
    deinit {
        precondition(tornDown, "Call tearDown to avoid continued fetch requests")
    }
    
    /// Returns all assets that have been fetched thus far
    public func assets(for category: MessageCategory) -> [ZMMessage] {
        // Remove zombie objects and return remaining
        if let values = assets?[category] {
            let withoutZombie = values.filter{!$0.isZombieObject}
            assets?[category] = withoutZombie
            return withoutZombie
        }
        return []
    }
    
    private func setFetchingCompleteFor(type: MessagesToFetch) {
        if type == .client {
            doneFetchingTexts = true
        } else {
            doneFetchingAssets = true
        }
    }

    private func fetchNextIfNotTornDown(limit: Int, type: MessagesToFetch, syncConversation: ZMConversation){
        guard !doneFetching, !tornDown else { return }
        guard !syncConversation.isZombieObject else {
            self.notifyDelegateFetchingIsDone(result: .failed)
            return
        }
        
        // Fetch next messages to categorize
        let lastMessage : ZMMessage? = (type == .client) ? self.lastClientMessage : self.lastAssetMessage
        let messagesToAnalyze : [ZMMessage]
        if  type == .client {
            // Unfortunately this is the only way to infer the type :-/
            let clientMessages : [ZMClientMessage] = self.messages(for: syncConversation, startAfter: lastMessage, fetchLimit: limit)
            messagesToAnalyze = clientMessages
        } else {
            let assetMessages : [ZMAssetClientMessage] = self.messages(for: syncConversation, startAfter: lastMessage, fetchLimit: limit)
            messagesToAnalyze = assetMessages
        }
        
        // Determine whether we have reached the end of the messages, if so, set flags for completeness
        let didReachLastMessage = (messagesToAnalyze.count < limit)
        if didReachLastMessage {
            self.setFetchingCompleteFor(type: type)
        }
        if messagesToAnalyze.count == 0 {
            if self.doneFetching {
                self.notifyDelegateFetchingIsDone(result: (self.assets == nil) ? .noAssetsToFetch : .success)
            }
            return
        }
        
        // Remember last message for next fetch
        if type == .client {
            self.lastClientMessage = messagesToAnalyze.last as? ZMClientMessage
        } else {
            self.lastAssetMessage = messagesToAnalyze.last as? ZMAssetClientMessage
        }
        
        // Categorize messages and merge results with existing result
        let newAssets = AssetCollectionBatched.messageMap(messages: messagesToAnalyze, including: self.including, excluding: self.excluding)
        
        // Notify delegate
        self.notifyDelegate(newAssets: newAssets, type: type, didReachLastMessage: didReachLastMessage)
        
        // Return if done
        if didReachLastMessage {
            return
        }
        
        syncMOC?.performGroupedBlock { [weak self] in
            guard let `self` = self, !self.tornDown else { return }
            self.fetchNextIfNotTornDown(limit: AssetCollection.defaultFetchCount, type: type, syncConversation: syncConversation)
        }
    }
    
    private func notifyDelegate(newAssets: [MessageCategory : [ZMMessage]], type: MessagesToFetch?, didReachLastMessage: Bool) {
        if newAssets.count == 0 {
            return
        }

        uiMOC?.performGroupedBlock { [weak self] in
            guard let `self` = self, !self.tornDown else { return }
            
            // Map to ui assets
            var uiAssets = [MessageCategory : [ZMMessage]]()
            newAssets.forEach { (category, messages) in
                let uiValues = messages.flatMap{ (try? self.uiMOC?.existingObject(with: $0.objectID)) as? ZMMessage}
                uiAssets[category] = uiValues
            }

            // Merge with existing assets
            if let assets = self.assets {
                self.assets = AssetCollectionBatched.merge(messageMap: assets, with: newAssets)
            } else {
                self.assets = newAssets
            }
            
            // Notify delegate
            self.delegate.assetCollectionDidFetch(collection: self, messages: uiAssets, hasMore: didReachLastMessage)
            if (self.doneFetching) {
                self.notifyDelegateFetchingIsDone(result: (self.assets == nil) ? .noAssetsToFetch : .success)
            }
        }
    }
    
    private func notifyDelegateFetchingIsDone(result: AssetFetchResult){
        self.uiMOC?.performGroupedBlock { [weak self] in
            guard let `self` = self, !self.tornDown else { return }
            self.delegate.assetCollectionDidFinishFetching(collection: self, result: result)
        }
    }
    
    func categorizedMessages<T : ZMMessage>(for conversation: ZMConversation) -> [T] {
        precondition(conversation.managedObjectContext!.zm_isSyncContext, "Fetch should only be performed on the sync context")
        let request = T.fetchRequestMatching(categories: Set(self.including), excluding: self.excluding, conversation: conversation)
        
        guard let result = conversation.managedObjectContext?.fetchOrAssert(request: request as! NSFetchRequest<T>) else {return []}
        return result
    }
    
    func messages<T: ZMMessage>(for conversation: ZMConversation, startAfter previousMessage: ZMMessage?, fetchLimit: Int) -> [T]  {
        
        let request : NSFetchRequest <T> = AssetCollectionBatched.fetchRequestForUnCategorizedMessages(in: conversation)
        if let serverTimestamp = previousMessage?.serverTimestamp {
            let messagePredicate = NSPredicate(format: "serverTimestamp < %@", serverTimestamp as NSDate)
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [request.predicate!, messagePredicate])
        }
        request.fetchLimit = fetchLimit
        request.returnsObjectsAsFaults = false
        
        guard let result = conversation.managedObjectContext?.fetchOrAssert(request: request) else {return []}
        return result
    }
    
}



