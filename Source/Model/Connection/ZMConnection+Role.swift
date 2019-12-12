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

extension ZMConnection {
    
    @objc
    
    /// add a user to connection's conversation
    ///
    /// - Parameter user: the user to insert
    public func add(user: ZMUser) {
        guard let managedObjectContext = user.managedObjectContext else { return }
        
        let participantRole = ParticipantRole.create(managedObjectContext: managedObjectContext, user: user, conversation: conversation)
        
        conversation.participantRoles.insert(participantRole)
    }
}
