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

public extension ZMConversation {
    
    public func appendMissedCallMessage(fromUser user: ZMUser, at timestamp: Date) {
        let (message, index) = appendSystemMessage(type: .missedCall, sender: user, users: [user], clients: nil, timestamp: timestamp)
        if let previous = associatedMessage(before: message, at: index) {
            previous.childMessages.insert(message)
            message.visibleInConversation = nil
            message.hiddenInConversation = self
        }
    }

    public func appendPerformedCallMessage(with duration: TimeInterval, caller: ZMUser) {
        let (message, index) = appendSystemMessage(
            type: .performedCall,
            sender: caller,
            users: [caller],
            clients: nil,
            timestamp: Date(),
            duration: duration
        )

        if let previous = associatedMessage(before: message, at: index) {
            previous.childMessages.insert(message)
            message.visibleInConversation = nil
            message.hiddenInConversation = self
            managedObjectContext?.enqueueDelayedSave()
        }
    }

    private func associatedMessage(before message: ZMSystemMessage, at index: UInt) -> ZMSystemMessage? {
        guard index > 1 else { return nil }
        guard let previous = messages[Int(index - 1)] as? ZMSystemMessage else { return nil }
        guard previous.systemMessageType == message.systemMessageType else { return nil }
        guard previous.users == message.users, previous.sender == message.sender else { return nil }
        return previous
    }

}
