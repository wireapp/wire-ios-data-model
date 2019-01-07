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

extension ZMOTRMessage {
    
    private static let deliveryConfirmationDayThreshold = 7
    
    @NSManaged @objc dynamic var expectsReadConfirmation: Bool
        
    override open var needsReadConfirmation: Bool {
        guard let conversation = conversation, let managedObjectContext = managedObjectContext else { return false }
        
        if conversation.conversationType == .oneOnOne {
            return genericMessage?.content?.expectsReadConfirmation() == true && ZMUser.selfUser(in: managedObjectContext).readReceiptsEnabled
        } else if conversation.conversationType == .group {
            return expectsReadConfirmation
        }
        
        return false
    }
    
    @objc
    var needsDeliveryConfirmation: Bool {
        return needsDeliveryConfirmationAtCurrentDate()
    }
    
    func needsDeliveryConfirmationAtCurrentDate(_ currentDate: Date = Date()) -> Bool {
        guard let conversation = conversation, conversation.conversationType == .oneOnOne,
              let sender = sender, !sender.isSelfUser,
              let serverTimestamp = serverTimestamp,
              let daysElapsed = Calendar.current.dateComponents([.day], from: serverTimestamp, to: currentDate).day
        else { return false }
        
        return daysElapsed <= ZMOTRMessage.deliveryConfirmationDayThreshold
    }
    
}
