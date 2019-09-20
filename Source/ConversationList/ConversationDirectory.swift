//
// Wire
// Copyright (C) 2019 Wire Swiss GmbH
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

public enum ConversationListType {
    case archived, unarchived, pending, contacts, groups
}

public struct ConversationDirectoryChangeInfo {
    
    public var reloaded: Bool
    public var updatedLists: [ConversationListType]
    
}

public protocol ConversationDirectoryObserver {
    
    func conversationDirectoryDidChange(_ changeInfo: ConversationDirectoryChangeInfo)
    
}

public protocol FolderType {
    var name: String { get }
    var conversations: [ZMConversation] { get }
}

public protocol ConversationDirectoryType {
    
    var folders: [FolderType] { get }
    
    func conversations(by: ConversationListType) -> [ZMConversation]
    
    func addObserver(_ observer: ConversationDirectoryObserver) -> Any
    
}

extension ZMConversationListDirectory: ConversationDirectoryType {
    
    public func conversations(by type: ConversationListType) -> [ZMConversation] {
        switch type {
        case .archived:
            return archivedConversations as! [ZMConversation]
        case .unarchived:
            return unarchivedConversations as! [ZMConversation]
        case .pending:
            return pendingConnectionConversations as! [ZMConversation]
        case .contacts:
            return oneToOneConversations as! [ZMConversation]
        case .groups:
            return groupConversations as! [ZMConversation]
        }
    }
    
    public var folders: [FolderType] {
        return []
    }
    
    public func addObserver(_ observer: ConversationDirectoryObserver) -> Any {
        let observerProxy = ConversationListObserverProxy(observer: observer, directory: self)
        let token = ConversationListChangeInfo.add(observer: observerProxy, managedObjectContext: nil!)
        return [token, observerProxy]
    }
    
}

fileprivate class ConversationListObserverProxy: NSObject, ZMConversationListObserver, ZMConversationListReloadObserver  {
    
    var observer: ConversationDirectoryObserver
    var directory: ZMConversationListDirectory
    
    init(observer: ConversationDirectoryObserver, directory: ZMConversationListDirectory) {
        self.observer = observer
        self.directory = directory
    }
    
    func conversationListsDidReload() {
        observer.conversationDirectoryDidChange(ConversationDirectoryChangeInfo(reloaded: true, updatedLists: []))
    }
    
    func conversationListDidChange(_ changeInfo: ConversationListChangeInfo) {
        let updatedLists: [ConversationListType]
        
        switch changeInfo.conversationList {
        case directory.oneToOneConversations:
            updatedLists = [.contacts]
        case directory.groupConversations:
            updatedLists = [.groups]
        case directory.archivedConversations:
            updatedLists = [.archived]
        case directory.pendingConnectionConversations:
            updatedLists = [.pending]
        case directory.unarchivedConversations:
            updatedLists = [.unarchived]
        default:
            updatedLists = []
        }
        
        observer.conversationDirectoryDidChange(ConversationDirectoryChangeInfo(reloaded: false, updatedLists: updatedLists))
    }
    
}
