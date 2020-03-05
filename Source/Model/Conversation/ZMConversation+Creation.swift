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
    
    @objc(insertGroupConversationIntoManagedObjectContext:withParticipants:)
    static public func insertGroupConversation(moc: NSManagedObjectContext,
                                               participants: [UserType]) -> ZMConversation?
    {
        return self.insertGroupConversation(moc: moc, participants: participants, name: nil)
    }
    
    /// Insert a new group conversation with name into the user session

    @objc
    static public func insertGroupConversation(session: ZMManagedObjectContextProvider,
                                               participants: [UserType],
                                               name: String? = nil,
                                               team: Team? = nil,
                                               allowGuests: Bool = true,
                                               readReceipts: Bool = false,
                                               participantsRole: Role? = nil) -> ZMConversation?
    {
        return self.insertGroupConversation(moc: session.managedObjectContext!,
                                            participants: participants,
                                            name: name,
                                            team: team,
                                            allowGuests: allowGuests,
                                            readReceipts: readReceipts,
                                            participantsRole: participantsRole)
    }
    
    @objc
    static public func insertGroupConversation(moc: NSManagedObjectContext,
                                               participants: [UserType],
                                               name: String? = nil,
                                               team: Team? = nil,
                                               allowGuests: Bool = true,
                                               readReceipts: Bool = false,
                                               participantsRole: Role? = nil) -> ZMConversation?
    {
        return insertGroupConversation(moc: moc,
                                       participants: participants,
                                       name: name,
                                       team: team,
                                       allowGuests: allowGuests,
                                       readReceipts: readReceipts,
                                       participantsRole: participantsRole,
                                       type: .group)
    }
    
    /// insert a conversation with group type
    ///
    /// - Parameters:
    ///   - moc: the NSManagedObjectContext
    ///   - participants: the participants
    ///   - name: the name of the convo
    ///   - team: the team of the convo
    ///   - allowGuests: allow guest or not
    ///   - readReceipts: allow read receipts or not
    ///   - participantsRole: the participants' role
    ///   - type: the convo type want to be created (for permission check)
    /// - Returns: the created conversation, nullable

    static public func insertGroupConversation(moc: NSManagedObjectContext,
                                               participants: [UserType],
                                               name: String? = nil,
                                               team: Team? = nil,
                                               allowGuests: Bool = true,
                                               readReceipts: Bool = false,
                                               participantsRole: Role? = nil,
                                               type: ZMConversationType = .group) -> ZMConversation?
    {
        guard let participants = participants as? [ZMUser] else { return nil }

        let selfUser = ZMUser.selfUser(in: moc)

        if (team != nil && !selfUser.canCreateConversation(type: type)) {
            return nil
        }
        
        let conversation = ZMConversation.insertNewObject(in: moc)
        conversation.lastModifiedDate = Date()
        conversation.conversationType = .group
        conversation.creator = selfUser
        conversation.team = team
        conversation.userDefinedName = name

        if (team != nil) {
            conversation.allowGuests = allowGuests;
            conversation.hasReadReceiptsEnabled = readReceipts;
        }
        
        let participantsIncludingSelf = Set(participants + [selfUser])
        
        // Add the new conversation system message
        conversation.appendNewConversationSystemMessage(at: Date(), users: Set(participantsIncludingSelf))
        
        // Add the participants
        conversation.addParticipantsAndUpdateConversationState(users: participantsIncludingSelf, role: participantsRole)
        
        // We need to check if we should add a 'secure' system message in case all participants are trusted
        conversation.increaseSecurityLevelIfNeededAfterTrusting(
            clients: Set(participantsIncludingSelf.flatMap { $0.clients })
        )

        return conversation
    }
    
    @objc
    static func fetchOrCreateOneToOneTeamConversation(
        moc: NSManagedObjectContext,
        participant: ZMUser,
        team: Team?,
        participantRole: Role? = nil) -> ZMConversation? {
        guard let team = team,
            !participant.isSelfUser
        else { return nil }
        
        if let conversation = self.existingTeamConversation(moc: moc, participant: participant, team: team) {
            return conversation
        }
        
        return insertGroupConversation(moc: moc,
                                       participants: [participant],
                                       name: nil,
                                       team: team,
                                       participantsRole: participantRole,
                                       type:.oneOnOne)
    }
    
    private static func existingTeamConversation(moc: NSManagedObjectContext,
                                                 participant:ZMUser,
                                                 team:Team) -> ZMConversation? {
        
        // We consider a conversation being an existing 1:1 team conversation in case the following point are true:
        //  1. It is a conversation inside the team
        //  2. The only participants are the current user and the selected user
        //  3. It does not have a custom display name
        // We are using predicates because filtering all conversations via relationships will cause a lot of faults
        // and slow down the app

        let selfUser = ZMUser.selfUser(in: moc)
        let sameTeam = ZMConversation.predicateForConversations(in: team)
        let groupConversation = NSPredicate(format: "%K == %d", ZMConversationConversationTypeKey, ZMConversationType.group.rawValue)
        let noUserDefinedName = NSPredicate(format: "%K == NULL", ZMConversationUserDefinedNameKey)
        let sameParticipant = NSPredicate(
            format: "%K.@count == 2 AND ANY %K.user == %@ AND ANY %K.user == %@",
            ZMConversationParticipantRolesKey,
            ZMConversationParticipantRolesKey,
            participant,
            ZMConversationParticipantRolesKey,
            selfUser
        )
        
        let compoundPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            sameTeam,
            groupConversation,
            noUserDefinedName,
            sameParticipant
        ])
        let request = self.sortedFetchRequest(with: compoundPredicate)
        return moc.executeFetchRequestOrAssert(request)?.first as? ZMConversation
    }
}
