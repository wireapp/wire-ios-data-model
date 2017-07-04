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


public extension ZMUser {

    public var hasTeam: Bool {
        return nil != team
    }

    public var team: Team? {
        return membership?.team
    }
    
    static func keyPathsForValuesAffectingTeam() -> Set<String> {
         return [#keyPath(ZMUser.membership)]
    }

    public var permissions: Permissions? {
        return membership?.permissions
    }

    @objc(canAddUserToConversation:)
    public func canAddUser(to conversation: ZMConversation) -> Bool {
        guard !isGuest(in: conversation), conversation.isSelfAnActiveMember else { return false }
        return permissions?.contains(.addConversationMember) ?? true
    }

    @objc(canRemoveUserFromConversation:)
    public func canRemoveUser(from conversation: ZMConversation) -> Bool {
        guard !isGuest(in: conversation), conversation.isSelfAnActiveMember else { return false }
        return permissions?.contains(.removeConversationMember) ?? true
    }

    public var canCreateConversation: Bool {
        return permissions?.contains(.createConversation) ?? true
    }

    func _isGuest(in conversation: ZMConversation) -> Bool {
        if isSelfUser {
            // In case the self user is a guest in a team conversation, the backend will
            // return a 404 when fetching said team and we will delete the team.
            // We store the teamRemoteIdentifier of the team to check if we don't have a local team,
            // but received a teamId in the conversation payload, which means we are a guest in the conversation.
            return conversation.team == nil
                && conversation.teamRemoteIdentifier != nil
        } else {
            return ZMUser.selfUser(in: managedObjectContext!).hasTeam // There can't be guests in a team that doesn't exist
                && conversation.otherActiveParticipants.contains(self)
                && membership == nil
        }
    }

}
