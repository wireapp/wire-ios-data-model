//
// Wire
// Copyright (C) 2020 Wire Swiss GmbH
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

@objc
public protocol UpdateEvent: NSObjectProtocol {
    var messageNonce: UUID? { get }
    var timestamp: Date? { get }
    var conversationUUID: UUID? { get }
    var senderUUID: UUID? { get }
    
    //from Transport
    var type: ZMUpdateEventType { get }
}

extension ZMUpdateEvent: UpdateEvent {
    private var payloadDictionary: NSDictionary {
        return payload as NSDictionary
    }
    
    public var conversationUUID: UUID? {
        if type == .userConnection {
            return (payloadDictionary.optionalDictionary(forKey: "connection")! as NSDictionary).optionalUuid(forKey: "conversation")
        }
        if type == .teamConversationDelete {
            return (payloadDictionary.optionalDictionary(forKey: "data") as! NSDictionary).optionalUuid(forKey: "conv")
        }

        return payloadDictionary.optionalUuid(forKey: "conversation")

    }
    
    public var senderUUID: UUID? {
        if type == .userConnection {
            return ((payload as NSDictionary).optionalDictionary(forKey: "connection")! as NSDictionary).optionalUuid(forKey: "to")
        }

        if type == .userContactJoin {
            return ((payload as NSDictionary).optionalDictionary(forKey: "user") as! NSDictionary).optionalUuid(forKey: "id")
        }

        return (payload as NSDictionary).optionalUuid(forKey: "from")
    }
    
    public var timestamp: Date? {
        if isTransient || type == .userConnection {
            return nil
        }
        
        return (payload as NSDictionary).date(for: "time")
    }
    
    public var messageNonce: UUID? {
        switch type {
        case .conversationMessageAdd,
             .conversationAssetAdd,
             .conversationKnock:
            return payload.dictionary(forKey: "data")?["nonce"] as? UUID
        case .conversationClientMessageAdd,
             .conversationOtrMessageAdd,
             .conversationOtrAssetAdd:
            let message = GenericMessage(from: self)
            guard let messageID = message?.messageID else {
                return nil
            }
            return UUID(uuidString: messageID)
        default:
            return nil
        }
    }
}

extension ZMUpdateEvent {
    
    public var userIDs: [UUID] {
        guard let dataPayload = (payload as NSDictionary).dictionary(forKey: "data"),
            let userIds = dataPayload["user_ids"] as? [String] else {
                return []
        }
        return userIds.compactMap({ UUID.init(uuidString: $0)})
    }

    public var participantsRemovedReason: ZMParticipantsRemovedReason {
        guard let dataPayload = (payload as NSDictionary).dictionary(forKey: "data"),
              let reasonString = dataPayload["reason"] as? String else {
            return ZMParticipantsRemovedReason.none
        }
        return ZMParticipantsRemovedReason(reasonString)
    }
}
