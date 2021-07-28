//
//  ZMMessage.swift
//  WireDataModel
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

extension ZMMessage {
    @objc
    func setServerTimestamp(updateEvent: ZMUpdateEvent) {
        serverTimestamp = updateEvent.timestamp;
    }
    
    @objc(conversationForUpdateEvent:inContext:prefetchResult:)
    public class func conversation(for event: ZMUpdateEvent?,
                                   in moc: NSManagedObjectContext?,
                                   prefetchResult: ZMFetchRequestBatchResult?) -> ZMConversation? {
        guard let conversationUUID = event?.conversationUUID,
              let moc = moc else { return nil }
        
        if let conversation = prefetchResult?.conversationsByRemoteIdentifier[conversationUUID] {
            return conversation
        }
        
        return ZMConversation(remoteID: conversationUUID,
                              createIfNeeded: true,
                              in: moc)
    }
    
    @objc
    public func sender(event: ZMUpdateEvent) -> ZMUser? {
        guard let senderUUID = event.senderUUID,
              let managedObjectContext = managedObjectContext else { return nil }
        
        return ZMUser(remoteID: senderUUID,
                      createIfNeeded: true,
                      in: managedObjectContext)
    }
}
