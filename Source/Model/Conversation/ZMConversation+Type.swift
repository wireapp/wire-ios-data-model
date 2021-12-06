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
public enum ZMConversationType: Int16 {
    case invalid,
         `self`,
         oneOnOne,
         group,
         connection // Incoming & outgoing connection request
}

extension ZMConversation {
    
    var internalConversationType: Int16 {
        get {
            let key = #keyPath(ZMConversation.conversationType)
            
            willAccessValue(forKey: key)
            let value = primitiveValue(forKey: key) as? Int16
            didAccessValue(forKey: key)
            
            return value ?? 0
        }
        
        set {
            let key = #keyPath(ZMConversation.conversationType)
            
            willChangeValue(forKey: key)
            setPrimitiveValue(newValue, forKey: key)
            didChangeValue(forKey: key)
            
        }
    }
    
    public var conversationType: ZMConversationType {
        get {
            guard var internalType = ZMConversationType(rawValue: internalConversationType) else { return .invalid }
            
            if internalType == .group,
               teamRemoteIdentifier != nil,
               (userDefinedName ?? "").isEmpty,
               localParticipantRoles.count == 2,
               localParticipantsExcludingSelf.count == 1 {
                internalType = .oneOnOne
            }
            
            return internalType
        }
        
        set {
            internalConversationType = newValue.rawValue
        }
    }
    
}
