//
// Wire
// Copyright (C) 2018 Wire Swiss GmbH
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

extension ZMConversation {
    
    @NSManaged @objc dynamic public var hasReadReceiptsEnabled: Bool
    
    /// Confirm unread received messages as read.
    ///
    /// - parameter until: unread messages received up until this timestamp will be confirmed as read.
    @discardableResult
    func confirmUnreadMessagesAsRead(until timestamp: Date) -> [ZMClientMessage] {
        
        let unreadMessagesNeedingConfirmation = unreadMessages(until: timestamp).filter({ $0.needsReadConfirmation })
        var confirmationMessages: [ZMClientMessage] = []
        
        for messages in unreadMessagesNeedingConfirmation.partition(by: \.sender).values {
            guard !messages.isEmpty else { continue }
            
            let confirmation = ZMConfirmation.confirm(messages: messages.compactMap(\.nonce), type: .READ)
            
            if let confirmationMessage = append(message: confirmation, hidden: true) {
                confirmationMessages.append(confirmationMessage)
            }
        }
        
        return confirmationMessages
    }
    
}
