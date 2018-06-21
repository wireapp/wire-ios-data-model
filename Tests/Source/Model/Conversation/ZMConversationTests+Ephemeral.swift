//
// Wire
// Copyright (C) 2016 Wire Swiss GmbH
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
@testable import WireDataModel

class ZMConversationMessageDestructionTimeoutTests : XCTestCase {

    func testThatItReturnsTheCorrectTimeouts(){
        XCTAssertEqual(MessageDestructionTimeoutValue.none.rawValue, 0)
        XCTAssertEqual(MessageDestructionTimeoutValue.tenSeconds.rawValue, 10)
        XCTAssertEqual(MessageDestructionTimeoutValue.fiveMinutes.rawValue, 300)
        XCTAssertEqual(MessageDestructionTimeoutValue.oneHour.rawValue, 3600)
        XCTAssertEqual(MessageDestructionTimeoutValue.oneDay.rawValue, 86400)
        XCTAssertEqual(MessageDestructionTimeoutValue.oneWeek.rawValue, 604800)
        XCTAssertEqual(MessageDestructionTimeoutValue.fourWeeks.rawValue, 2419200)
    }

    func testThatItCreatesAValidTimeOut() {
        XCTAssertEqual(MessageDestructionTimeoutValue(rawValue: -2), .custom(-2))
        XCTAssertEqual(MessageDestructionTimeoutValue(rawValue: 0), .none)
        XCTAssertEqual(MessageDestructionTimeoutValue(rawValue: 10), .tenSeconds)
        XCTAssertEqual(MessageDestructionTimeoutValue(rawValue: 300), .fiveMinutes)
        XCTAssertEqual(MessageDestructionTimeoutValue(rawValue: 3600), .oneHour)
        XCTAssertEqual(MessageDestructionTimeoutValue(rawValue: 86400), .oneDay)
        XCTAssertEqual(MessageDestructionTimeoutValue(rawValue: 604800), .oneWeek)
        XCTAssertEqual(MessageDestructionTimeoutValue(rawValue: 690000), .custom(690000))
        XCTAssertEqual(MessageDestructionTimeoutValue(rawValue: 2419200), .fourWeeks)
        XCTAssertEqual(MessageDestructionTimeoutValue(rawValue: 1234567890), .custom(1234567890))
    }

}

extension ZMConversation {
    func setLocalMessageDestructionTimeout(to newValue: TimeInterval) {
        if newValue == 0 {
            messageDestructionTimeout = .local(MessageDestructionTimeoutValue(rawValue: newValue))
        }
        else {
            messageDestructionTimeout = nil
        }
    }
}

class ZMConversationTests_Ephemeral : BaseZMMessageTests {

    func testThatItAllowsSettingTimeoutsOnGroupConversations(){
        // given
        let conversation = ZMConversation.insertNewObject(in: uiMOC)
        conversation.conversationType = .group
        
        // when
        conversation.messageDestructionTimeout = .local(.tenSeconds)
        
        // then
        XCTAssertEqual(conversation.messageDestructionTimeoutValue, 10)
    }

    func testThatItAllowsSettingSyncedTimeoutsOnGroupConversations(){
        // given
        let conversation = ZMConversation.insertNewObject(in: uiMOC)
        conversation.conversationType = .group
        
        // when
        conversation.messageDestructionTimeout = .synced(.tenSeconds)
        
        // then
        XCTAssertEqual(conversation.messageDestructionTimeoutValue, 10)
    }
    
    func testThatItAllowsSettingTimeoutsOnOneOnOneConversations(){
        // given
        let conversation = ZMConversation.insertNewObject(in: uiMOC)
        conversation.conversationType = .oneOnOne
        
        // when
        conversation.messageDestructionTimeout = .local(.tenSeconds)
        
        // then
        XCTAssertEqual(conversation.messageDestructionTimeoutValue, 10)
    }
}

