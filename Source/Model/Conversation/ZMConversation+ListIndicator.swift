//
// Wire
// Copyright (C) 2021 Wire Swiss GmbH
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
enum ZMConversationListIndicator: Int16 {
    case invalid,
         none,
         unreadSelfMention,
         unreadSelfReply,
         unreadMessages,
         knock,
         missedCall,
         expiredMessage,
         activeCall, //  Ringing or talking in call.
         inactiveCall, // Other people are having a call but you are not in it.
         pending
}

extension ZMConversation {
    
    var conversationListIndicator: ZMConversationListIndicator {
        if let connectedUser = connectedUser, connectedUser.isPendingApprovalByOtherUser {
            return .pending
        } else if isCallDeviceActive {
            return .activeCall
        
        } else if isIgnoringCall {
            return .inactiveCall
        }
        
        return unreadListIndicator
    }
    
    static var keyPathsForValuesAffectingConversationListIndicator: Set<String> {
        keyPathsForValuesAffectingUnreadListIndicator.union(Set([VoiceChannelStateKey]))
    }
    
}
