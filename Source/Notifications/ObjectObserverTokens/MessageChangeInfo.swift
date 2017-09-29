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

private var zmLog = ZMSLog(tag: "MessageChangeInfo")

// MARK: Message observing 

enum MessageKey: String {
    case previewGenericMessage = "previewGenericMessage"
    case mediumGenericMessage = "mediumGenericMessage"
    case linkPreview = "linkPreview"
}

extension ZMMessage : ObjectInSnapshot {
    
    public class var observableKeys : Set<String> {
        return [#keyPath(ZMMessage.deliveryState), #keyPath(ZMMessage.isObfuscated)]
    }
    
    public var notificationName : Notification.Name {
        return .MessageChange
    }
}

extension ZMAssetClientMessage {

    public class override var observableKeys : Set<String> {
        let keys = super.observableKeys
        let additionalKeys = [#keyPath(ZMAssetClientMessage.transferState),
                              MessageKey.previewGenericMessage.rawValue,
                              MessageKey.mediumGenericMessage.rawValue,
                              #keyPath(ZMAssetClientMessage.hasDownloadedImage),
                              #keyPath(ZMAssetClientMessage.hasDownloadedFile),
                              #keyPath(ZMAssetClientMessage.progress),
                              #keyPath(ZMMessage.reactions)]
        return keys.union(additionalKeys)
    }
}

extension ZMClientMessage {
    
    public class override var observableKeys : Set<String> {
        let keys = super.observableKeys
        let additionalKeys = [#keyPath(ZMAssetClientMessage.hasDownloadedImage),
                              #keyPath(ZMClientMessage.linkPreviewState),
                              #keyPath(ZMClientMessage.genericMessage),
                              #keyPath(ZMMessage.reactions),
                              MessageKey.linkPreview.rawValue]
        return keys.union(additionalKeys)
    }
}

extension ZMImageMessage {
    
    public class override var observableKeys : Set<String> {
        let keys = super.observableKeys
        let additionalKeys = [#keyPath(ZMImageMessage.mediumData),
                              #keyPath(ZMImageMessage.mediumRemoteIdentifier),
                              #keyPath(ZMMessage.reactions)]
        return keys.union(additionalKeys)
    }
}

extension ZMSystemMessage {

    public class override var observableKeys : Set<String> {
        let keys = super.observableKeys
        let additionalKeys = [#keyPath(ZMSystemMessage.childMessages)]
        return keys.union(additionalKeys)
    }

}

@objc final public class MessageChangeInfo : ObjectChangeInfo {
    
    static let UserChangeInfoKey = "userChanges"
    static let ReactionChangeInfoKey = "reactionChanges"

    static func changeInfo(for message: ZMMessage, changes: Changes) -> MessageChangeInfo? {
        var originalChanges = changes.originalChanges
        let clientChanges = originalChanges.removeValue(forKey: ReactionChangeInfoKey) as? [NSObject : [String : Any]]
        
        if let clientChanges = clientChanges {
            var reactionChangeInfos = [ReactionChangeInfo]()
            clientChanges.forEach {
                let changeInfo = ReactionChangeInfo(object: $0)
                changeInfo.changeInfos = $1 as! [String : NSObject]
                reactionChangeInfos.append(changeInfo)
            }
            originalChanges[ReactionChangeInfoKey] = reactionChangeInfos as NSObject?
        }
        
        guard originalChanges.count > 0 || changes.changedKeys.count > 0 else { return nil }
        
        let changeInfo = MessageChangeInfo(object: message)
        changeInfo.changeInfos = originalChanges
        changeInfo.changedKeys = changes.changedKeys
        return changeInfo
    }
    
    
    public required init(object: NSObject) {
        self.message = object as! ZMMessage
        super.init(object: object)
    }
    public var deliveryStateChanged : Bool {
        return changedKeysContain(keys: #keyPath(ZMMessage.deliveryState))
    }
    
    public var reactionsChanged : Bool {
        return changedKeysContain(keys: #keyPath(ZMMessage.reactions)) || reactionChangeInfos.count != 0
    }

    public var childMessagesChanged : Bool {
        return changedKeysContain(keys: #keyPath(ZMSystemMessage.childMessages))
    }

    /// Whether the image data on disk changed
    public var imageChanged : Bool {
        return changedKeysContain(keys: #keyPath(ZMImageMessage.mediumData),
                                  #keyPath(ZMImageMessage.mediumRemoteIdentifier),
                                  #keyPath(ZMAssetClientMessage.hasDownloadedImage),
                                  MessageKey.previewGenericMessage.rawValue,
                                  MessageKey.mediumGenericMessage.rawValue)
    }
    
    /// Whether the file on disk changed
    public var fileAvailabilityChanged: Bool {
        return changedKeysContain(keys: #keyPath(ZMAssetClientMessage.hasDownloadedFile))
    }

    public var usersChanged : Bool {
        return userChangeInfo != nil
    }
    
    public var linkPreviewChanged: Bool {
        return changedKeysContain(keys: #keyPath(ZMClientMessage.linkPreviewState), MessageKey.linkPreview.rawValue)
    }

    public var transferStateChanged: Bool {
        return changedKeysContain(keys: #keyPath(ZMAssetClientMessage.transferState))
    }

    public var senderChanged : Bool {
        if self.usersChanged && (self.userChangeInfo?.user as? ZMUser ==  self.message.sender){
            return true
        }
        return false
    }
    
    public var isObfuscatedChanged : Bool {
        return changedKeysContain(keys: #keyPath(ZMMessage.isObfuscated))
    }
    
    public var userChangeInfo : UserChangeInfo? {
        return changeInfos[MessageChangeInfo.UserChangeInfoKey] as? UserChangeInfo
    }
    
    var reactionChangeInfos : [ReactionChangeInfo] {
        return changeInfos[MessageChangeInfo.ReactionChangeInfoKey] as? [ReactionChangeInfo] ?? []
    }
    
    public let message : ZMMessage
    
}



@objc public protocol ZMMessageObserver : NSObjectProtocol {
    func messageDidChange(_ changeInfo: MessageChangeInfo)
}

extension MessageChangeInfo {
    
    /// Adds a ZMMessageObserver to the specified message
    /// To observe messages and their users (senders, systemMessage users), observe the conversation window instead
    /// Messages observed with this call will not contain information about user changes
    /// You must hold on to the token and use it to unregister
    @objc(addObserver:forMessage:managedObjectContext:)
    public static func add(observer: ZMMessageObserver,
                           for message: ZMConversationMessage,
                           managedObjectContext: NSManagedObjectContext) -> NSObjectProtocol {
        return ManagedObjectObserverToken(name: .MessageChange,
                                          managedObjectContext: managedObjectContext,
                                          object: message)
        { [weak observer] (note) in
            guard let `observer` = observer,
                let changeInfo = note.changeInfo as? MessageChangeInfo
                else { return }
            
            observer.messageDidChange(changeInfo)
        } 
    }
}


// MARK: - Reaction observer

private let ReactionUsersKey = "users"

public final class ReactionChangeInfo : ObjectChangeInfo {
    
    var usersChanged : Bool {
        return changedKeysContain(keys: ReactionUsersKey)
    }
}

@objc protocol ReactionObserver {
    func reactionDidChange(_ reactionInfo: ReactionChangeInfo)
}
