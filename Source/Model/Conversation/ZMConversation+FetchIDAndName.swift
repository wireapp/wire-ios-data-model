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

public enum ConversationFetchIDAndNameError: Error {
    
    case unknown,
         noTeamMember,
         accessDenied,
         invalidCode,
         noConversation
    
}

public class FetchIDAndNameAction: EntityAction {
    
    public var resultHandler: ResultHandler?
    
    public typealias Result = (UUID, String)
    public typealias Failure = ConversationFetchIDAndNameError
    
    public let key: String
    public let code: String
    
    public required init(key: String, code: String) {
        self.key = key
        self.code = code
    }
    
}

extension ZMConversation {
    
    public static func fetchIDAndName(context: NotificationContext,
                                      key: String,
                                      code: String,
                                      completion: @escaping FetchIDAndNameAction.ResultHandler) {
        var action = FetchIDAndNameAction(key: key, code: code)
        action.onResult(resultHandler: completion)
        action.send(in: context)
    }
    
}
