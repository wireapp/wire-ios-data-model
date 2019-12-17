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

enum ConversationAction {
    case addConversationMember
    case removeConversationMember
    case modifyConversationName
    case modifyConversationMessageTimer
    case modifyConversationReceiptMode
    case modifyConversationAccess
    case modifyOtherConversationMember
    case leaveConversation
    case deleteConvesation
    
    var name: String {
        switch self {
        case .addConversationMember: return "add_conversation_member"
        case .removeConversationMember: return "remove_conversation_member"
        case .modifyConversationName: return "modify_conversation_name"
        case .modifyConversationMessageTimer: return "modify_conversation_message_timer"
        case .modifyConversationReceiptMode: return "modify_conversation_receipt_mode"
        case .modifyConversationAccess: return "modify_conversation_access"
        case .modifyOtherConversationMember: return "modify_other_conversation_member"
        case .leaveConversation: return "leave_conversation"
        case .deleteConvesation: return "delete_conversation"
        }
    }
}

public extension ZMUser {
    
    var teamRole: TeamRole {
        return TeamRole(rawPermissions: permissions?.rawValue ?? 0)
    }
    
    private var permissions: Permissions? {
        return membership?.permissions
    }
    
    @objc(canAddServiceToConversation:)
    func canAddService(to conversation: ZMConversation) -> Bool {
        guard !isGuest(in: conversation), conversation.isSelfAnActiveMember else { return false }
        return permissions?.contains(.addRemoveConversationMember) ?? false
    }
    
    @objc(canRemoveServiceFromConversation:)
    func canRemoveService(from conversation: ZMConversation) -> Bool {
        return canAddService(to: conversation)
    }
    
    @objc(canAddUserToConversation:)
    func canAddUser(to conversation: ZMConversation) -> Bool {
        if conversation.conversationType == .group {
            return hasRoleWithAction(actionName: ConversationAction.addConversationMember.name, conversation: conversation)
        } else {
            guard conversation.teamRemoteIdentifier == nil || !isGuest(in: conversation), conversation.isSelfAnActiveMember else { return false }
            return permissions?.contains(.addRemoveConversationMember) ?? true
        }
    }
    
    @objc(canRemoveUserFromConversation:)
    func canRemoveUser(from conversation: ZMConversation) -> Bool {
        if conversation.conversationType == .group {
            return hasRoleWithAction(actionName: ConversationAction.removeConversationMember.name, conversation: conversation)
        } else {
            return canAddUser(to: conversation)
        }
    }
    
    @objc(canDeleteConversation:)
    func canDeleteConversation(_ conversation: ZMConversation) -> Bool {
        if conversation.conversationType == .group {
            return hasRoleWithAction(actionName: ConversationAction.deleteConvesation.name, conversation: conversation)
        } else {
            return conversation.teamRemoteIdentifier != nil && conversation.isSelfAnActiveMember && conversation.creator == self
        }
    }
    
    @objc(canModifyOtherMemberInConversation:)
    func canModifyOtherMember(in conversation: ZMConversation) -> Bool {
        guard conversation.conversationType == .group else { return false }
        return hasRoleWithAction(actionName: ConversationAction.modifyOtherConversationMember.name, conversation: conversation)
    }
    
    @objc(canModifyReadReceiptSettingsInConversation:)
    func canModifyReadReceiptSettings(in conversation: ZMConversation) -> Bool {
        guard !isGuest(in: conversation), conversation.isSelfAnActiveMember else { return false }
        return permissions?.contains(.modifyConversationMetaData) ?? false
    }
    
    @objc(canModifyEphemeralSettingsInConversation:)
    func canModifyEphemeralSettings(in conversation: ZMConversation) -> Bool {
        if conversation.conversationType == .group {
            return hasRoleWithAction(actionName: ConversationAction.modifyConversationMessageTimer.name, conversation: conversation)
        } else {
            guard  conversation.teamRemoteIdentifier == nil || !isGuest(in: conversation), conversation.isSelfAnActiveMember else { return false }
            return permissions?.contains(.modifyConversationMetaData) ?? true
        }
    }
    
    @objc(canModifyReceiptModeInConversation:)
    func canModifyReceiptMode(in conversation: ZMConversation) -> Bool {
        guard conversation.conversationType == .group else { return true }
        return hasRoleWithAction(actionName: ConversationAction.modifyConversationReceiptMode.name, conversation: conversation)
    }
    
    @objc(canModifyNotificationSettingsInConversation:)
    func canModifyNotificationSettings(in conversation: ZMConversation) -> Bool {
        guard conversation.isSelfAnActiveMember else { return false }
        return isTeamMember
    }
    
    @objc(canModifyAccessControlSettingsInConversation:)
    func canModifyAccessControlSettings(in conversation: ZMConversation) -> Bool {
        
        if conversation.conversationType == .group {
            return hasRoleWithAction(actionName: ConversationAction.modifyConversationAccess.name, conversation: conversation)
        } else {
            // Check conversation
            guard conversation.conversationType == .group,
                let moc = self.managedObjectContext,
                team?.remoteIdentifier != nil
                else { return false }
            
            // Check user
            let selfUser = ZMUser.selfUser(in: moc)
            guard selfUser.isTeamMember,
                !selfUser.isGuest(in: conversation),
                selfUser.team == self.team,
                isTeamMember,
                conversation.isSelfAnActiveMember else {
                    return false
            }
            
            return permissions?.contains(.modifyConversationMetaData) ?? false
        }
    }
    
    @objc(canModifyTitleInConversation:)
    func canModifyTitle(in conversation: ZMConversation) -> Bool {
        if conversation.conversationType == .group {
            return hasRoleWithAction(actionName: ConversationAction.modifyConversationName.name, conversation: conversation)
        } else {
            guard conversation.isSelfAnActiveMember else { return false }
            return permissions?.contains(.modifyConversationMetaData) ?? true
        }
    }
    
    @objc(canLeave:)
    func canLeave(_ conversation: ZMConversation) -> Bool {
        guard conversation.conversationType == .group else { return true }
        return hasRoleWithAction(actionName: ConversationAction.leaveConversation.name, conversation: conversation)
    }
    
    @objc var canCreateConversation: Bool {
        return permissions?.contains(.member) ?? true
    }
    
    @objc var canCreateService: Bool {
        return permissions?.contains(.member) ?? false
    }
    
    @objc var canManageTeam: Bool {
        return permissions?.contains(.admin) ?? false
    }
    
    func canAccessCompanyInformation(of user: UserType) -> Bool {
        guard
            let otherUser = user as? ZMUser,
            let otherUserTeamID = otherUser.team?.remoteIdentifier,
            let selfUserTeamID = self.team?.remoteIdentifier
            else {
                return false
        }
        
        return selfUserTeamID == otherUserTeamID
    }
    
    @objc func _isGuest(in conversation: ZMConversation) -> Bool {
        if isSelfUser {
            // In case the self user is a guest in a team conversation, the backend will
            // return a 404 when fetching said team and we will delete the team.
            // We store the teamRemoteIdentifier of the team to check if we don't have a local team,
            // but received a teamId in the conversation payload, which means we are a guest in the conversation.
            
            if let team = team {
                // If the self user belongs to a team he/she's a guest in every non team conversation
                return conversation.teamRemoteIdentifier != team.remoteIdentifier
            } else {
                // If the self user doesn't belong to a team he/she's a guest in all team conversations
                return conversation.teamRemoteIdentifier != nil
            }
        } else {
            return !isServiceUser // Bots are never guests
                && ZMUser.selfUser(in: managedObjectContext!).hasTeam // There can't be guests in a team that doesn't exist
                && conversation.localParticipants.contains(self)
                && membership == nil
        }
    }
    
    private func hasRoleWithAction(actionName: String, conversation: ZMConversation) -> Bool {
        let canModifyConversation = self.participantRoles.filter({$0.conversation == conversation}).first?.role?.actions.contains(where: {$0.name == actionName})
        return canModifyConversation ?? false
    }
}
