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

@testable import WireDataModel

extension ZMConversationTests {
    func testThatItRecalculatesActiveParticipantsWhenOtherActiveParticipantsKeyChanges() {
        // given
        let conversation = ZMConversation.insertNewObject(in: uiMOC)
        conversation.conversationType = .group
        conversation.isSelfAnActiveMember = true
        
        let user1 = ZMUser.insertNewObject(in: uiMOC)
        let user2 = ZMUser.insertNewObject(in: uiMOC)
        let isFromLocal = false
        conversation.internalAddParticipants([user1, user2], isFromLocal: isFromLocal)
        
        XCTAssert(conversation.isSelfAnActiveMember)
        XCTAssertEqual(conversation.lastServerSyncedActiveParticipants.count, 2)
        XCTAssertEqual(conversation.activeParticipants.count, 3)
        
        // expect
        keyValueObservingExpectation(for: conversation, keyPath: "activeParticipants", expectedValue: nil)
        
        // when
        
        conversation.internalRemoveParticipants([user2],
                                                sender: user1,
                                                isFromLocal: isFromLocal)
        
        uiMOC.processPendingChanges() ///TODO: put this inside internalRemoveParticipants?

        // then
        XCTAssert(conversation.isSelfAnActiveMember)
        XCTAssertEqual(conversation.lastServerSyncedActiveParticipants.count, 1)
        XCTAssertEqual(conversation.activeParticipants.count, 2)
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
    }
}
