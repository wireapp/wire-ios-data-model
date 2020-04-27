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
import WireCryptobox

extension ZMConversation {
    static func appendHideMessageToSelfConversation(_ message: ZMMessage) {
        guard let messageId = message.nonce,
            let conversation = message.conversation,
            let conversationId = conversation.remoteIdentifier else {
                return
        }
        
        let genericMessage = GenericMessage(content: MessageHide(conversationId: conversationId, messageId: messageId))
        ZMConversation.appendSelfConversation(genericMessage: genericMessage, managedObjectContext: message.managedObjectContext!)
    }
}

extension ZMMessage {
    
    // NOTE: This is a free function meant to be called from Obj-C because you can't call protocol extension from it
    @objc public static func hideMessage(_ message: ZMConversationMessage) {
        // when deleting ephemeral, we must delete for everyone (only self & sender will receive delete message)
        // b/c deleting locally will void the destruction timer completion.
        guard !message.isEphemeral else { deleteForEveryone(message); return }
        guard let castedMessage = message as? ZMMessage else { return }
        castedMessage.hideForSelfUser()
    }
    
    @objc public func hideForSelfUser() {
        guard !isZombieObject else { return }
        ZMConversation.appendHideMessageToSelfConversation(self)

        // To avoid reinserting when receiving an edit we delete the message locally
        removeClearingSender(true)
        managedObjectContext?.delete(self)
    }
    
    @discardableResult @objc public static func deleteForEveryone(_ message: ZMConversationMessage) -> ZMClientMessage? {
        guard let castedMessage = message as? ZMMessage else { return nil }
        return castedMessage.deleteForEveryone()
    }
    
    @discardableResult @objc func deleteForEveryone() -> ZMClientMessage? {
        guard !isZombieObject, let sender = sender , (sender.isSelfUser || isEphemeral) else { return nil }
        guard let conversation = conversation, let messageNonce = nonce else { return nil}
        
        let message =  conversation.append(message: MessageDelete(messageId: messageNonce), hidden: true)
        
        removeClearingSender(false)
        updateCategoryCache()
        return message
    }
    
    @objc var isEditableMessage : Bool {
        return false
    }
}

extension ZMClientMessage {
    override var isEditableMessage : Bool {
        guard let genericMessage = genericMessage,
              let sender = sender, sender.isSelfUser
        else {
            return false
        }
        
        return genericMessage.hasEdited() || genericMessage.hasText() && !isEphemeral && isSent
    }
}



