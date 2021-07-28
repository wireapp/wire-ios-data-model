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
public final class MockUpdateEvent: NSObject, UpdateEvent {
    public var messageNonce: UUID? = UUID()
    
    public var timestamp: Date?
    
    public var conversationUUID: UUID?
    
    public var senderUUID: UUID?
    
    public var type: ZMUpdateEventType
    public var payload: [AnyHashable : Any] = [:]
    
    public var participantsRemovedReason: ZMParticipantsRemovedReason = .none

    init(type: ZMUpdateEventType) {
        self.type = type
    }
}

extension ZMMessageTests {
    @objc(mockEventOfType:forConversation:sender:data:)
    public func mockEventOf(_ type: ZMUpdateEventType,
                            for conversation: ZMConversation?,
                            sender senderID: UUID?,
                            data: [AnyHashable : Any]?) -> MockUpdateEvent {
        let updateEvent = MockUpdateEvent(type: type)

        let serverTimeStamp: Date
                    
        if let lastServerTimeStamp = conversation?.lastServerTimeStamp {
            serverTimeStamp = lastServerTimeStamp.addingTimeInterval(5)
        } else {
            serverTimeStamp = Date()
        }
        
        let from = senderID ?? UUID()
        
        if let remoteIdentifier = conversation?.remoteIdentifier?.transportString,
           let data = data {
            let payload = [
                "conversation": remoteIdentifier,
                "time": serverTimeStamp.transportString,
                "from": from.transportString,
                "data": data
            ] as [String : Any]

            updateEvent.payload = payload
        }
        
        updateEvent.timestamp = serverTimeStamp
        updateEvent.conversationUUID = conversation?.remoteIdentifier
        updateEvent.senderUUID = from

        return updateEvent
    }
    
    func testThatSpecialKeysAreNotPartOfTheLocallyModifiedKeysForClientMessages() {
        // when
        let message = ZMClientMessage(nonce: NSUUID.create(), managedObjectContext: uiMOC)
        
        // then
        let keysThatShouldBeTracked = Set<AnyHashable>(["dataSet", "linkPreviewState"])
        XCTAssertEqual(message.keysTrackedForLocalModifications(), keysThatShouldBeTracked)
    }
}
