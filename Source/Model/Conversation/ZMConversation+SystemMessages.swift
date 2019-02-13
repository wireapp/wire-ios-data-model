//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
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
    
    public func appendTeamMemberRemovedSystemMessage(user: ZMUser, at timestamp: Date) {
        appendSystemMessage(type: .teamMemberLeave,
                            sender: user,
                            users: [user],
                            clients: nil,
                            timestamp: timestamp)
    }
    
    public func appendParticipantRemovedSystemMessage(user: ZMUser, sender: ZMUser? = nil, at timestamp: Date) {
        appendSystemMessage(type: .participantsRemoved,
                            sender: sender ?? user,
                            users: [user],
                            clients: nil,
                            timestamp: timestamp)
    }
    
    @objc(appendNewConversationSystemMessageAtTimestamp:)
    public func appendNewConversationSystemMessage(at timestamp: Date) {
        let systemMessage = appendSystemMessage(type: .newConversation,
                                                sender: creator,
                                                users: activeParticipants,
                                                clients: nil,
                                                timestamp: timestamp)
        
        systemMessage.text = userDefinedName
        
        // Fill out team specific properties if the conversation was created in the self user team
        if let context = managedObjectContext, let selfUserTeam = ZMUser.selfUser(in: context).team, team == selfUserTeam {
            
            let members = selfUserTeam.members.compactMap { $0.user }
            let guests = activeParticipants.filter { $0.isGuest(in: self) }
            
            systemMessage.allTeamUsersAdded = activeParticipants.isSuperset(of: members)
            systemMessage.numberOfGuestsAdded = Int16(guests.count)
        }
        
        if hasReadReceiptsEnabled {
            appendMessageReceiptModeIsOnMessage(timestamp: timestamp.nextNearestTimestamp)
        }
    }
    
}
