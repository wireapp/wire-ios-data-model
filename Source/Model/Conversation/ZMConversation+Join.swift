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

public enum ConversationJoinError: Error {
    
    case unknown,
         tooManyMembers,
         invalidCode,
         noConversation
    
}

public class JoinConversationAction: EntityAction {
    
    public var resultHandler: ResultHandler?
    
    public typealias Result = ZMConversation
    public typealias Failure = ConversationJoinError
    
    public let key: String
    public let code: String
    public let viewContext: NSManagedObjectContext
    
    public required init(key: String,
                         code: String,
                         viewContext: NSManagedObjectContext) {
        self.key = key
        self.code = code
        self.viewContext = viewContext
    }
    
}

extension ZMConversation {
    
    public static func join(key: String,
                            code: String,
                            syncContext: NSManagedObjectContext,
                            viewContext: NSManagedObjectContext,
                            completion: @escaping JoinConversationAction.ResultHandler) {
        var action = JoinConversationAction(key: key, code: code, viewContext: viewContext)
        action.onResult(resultHandler: completion)
        action.send(in: syncContext.notificationContext)
    }
    
}
