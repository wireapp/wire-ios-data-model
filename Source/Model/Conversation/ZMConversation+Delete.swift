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

public enum ConversationDeleteError: Error {
    case unknown,
         invalidOperation,
         conversationNotFound
}

public class DeleteConversationAction: EntityAction {
    public var resultHandler: ResultHandler?
    
    public typealias Result = Void
    public typealias Failure = ConversationDeleteError
    
    public let conversationID: UUID
    public let teamID: UUID
    
    public required init(conversationID: UUID, teamID: UUID) {
        self.conversationID = conversationID
        self.teamID = teamID
    }
    
}

extension ZMConversation {
    
    public func delete(completion: @escaping DeleteConversationAction.ResultHandler) {
        guard
            let context = managedObjectContext,
            ZMUser.selfUser(in: context).canDeleteConversation(self),
            let conversationID = remoteIdentifier,
            let teamID = teamRemoteIdentifier
        else {
            return completion(.failure(ConversationDeleteError.invalidOperation))
        }
        
        var action = DeleteConversationAction(conversationID: conversationID, teamID: teamID)
        action.onResult(resultHandler: completion)
        action.send(in: context.notificationContext)
    }
    
}
