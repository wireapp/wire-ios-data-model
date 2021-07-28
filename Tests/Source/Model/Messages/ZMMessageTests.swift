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
    public var messageNonce: UUID?
    
    public var timestamp: Date?
    
    public var conversationUUID: UUID?
    
    public var senderUUID: UUID?
}

extension ZMMessageTests {
    @objc(mockEventOfType:forConversation:sender:data:)
    public func mockEventOf(_ type: ZMUpdateEventType, for conversation: ZMConversation?, sender senderID: UUID?, data: [AnyHashable : Any]?) -> MockUpdateEvent {
        let updateEvent = MockUpdateEvent()
//        (updateEvent?.stub().andReturnValue(OCMOCK_VALUE(type)) as? ZMUpdateEvent)?.type()
//        let serverTimeStamp: Date? = (conversation?.lastServerTimeStamp ? conversation?.lastServerTimeStamp.addingTimeInterval(5) : Date()) as? Date
//        let from = senderID ?? NSUUID.createUUID
//        var payload: [StringLiteralConvertible : UnknownType?]? = nil
//        if let transportString = conversation?.remoteIdentifier.transportString, let transportString1 = serverTimeStamp?.transportString, let transportString2 = from?.transportString, let data = data {
//            payload = [
//                "conversation": transportString,
//                "time": transportString1,
//                "from": transportString2,
//                "data": data
//            ]
//        }
//        (updateEvent?.stub().andReturn(payload) as? ZMUpdateEvent)?.payload()
//
//        ///TODO: messageNonce can not be marked @objc since it is extended in DM, and it can not be stubed
//        //    NSUUID *nonce = [NSUUID UUID];
//        //    (void)[(ZMUpdateEvent *)[[(id)updateEvent stub] andReturn:nonce] messageNonce];
//        (updateEvent?.stub().andReturn(serverTimeStamp) as? ZMUpdateEvent)?.timestamp()
//        (updateEvent?.stub().andReturn(conversation?.remoteIdentifier) as? ZMUpdateEvent)?.conversationUUID()
//        (updateEvent?.stub().andReturn(from) as? ZMUpdateEvent)?.senderUUID()
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
