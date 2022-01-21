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
import XCTest
@testable import WireDataModel

class ZMConversationAccessModeTests: ZMConversationTestsBase {
    func conversation() -> ZMConversation {
        return ZMConversation.insertNewObject(in: self.uiMOC)
    }

    var sut: ZMConversation!
    var team: Team!

    override func setUp() {
        super.setUp()
        team = Team.insertNewObject(in: self.uiMOC)
        sut = conversation()
    }

    override func tearDown() {
        team = nil
        sut = nil
        super.tearDown()
    }

    func testThatItCanSetTheMode() {
        sut.accessMode = .teamOnly
        XCTAssertEqual(sut.accessMode, .teamOnly)
        // when
        sut.accessMode = .allowGuests
        // then
        XCTAssertEqual(sut.accessMode, .allowGuests)
    }

    func testAllowingGuests() {
        // GIVEN
        sut.accessRoles = [.teamMember, .service]
        sut.accessMode = .teamOnly

        // WHEN
        sut.allowGuests = true

        XCTAssertEqual(sut.accessMode, .allowGuests)
        XCTAssertEqual(sut.accessRoles, [.teamMember, .service, .guest])
    }

    func testDisallowingGuests() {
        // GIVEN
        sut.accessRoles = [.teamMember, .service, .guest]
        sut.accessMode = .allowGuests

        // WHEN
        sut.allowGuests = false

        XCTAssertEqual(sut.accessMode, .teamOnly)
        XCTAssertEqual(sut.accessRoles, [.teamMember, .service])
    }

    func testAllowingServices() {
        // GIVEN
        sut.accessRoles = [.teamMember]

        // WHEN
        sut.allowServices = true

        // THEN
        XCTAssertEqual(sut.accessRoles, [.teamMember, .service])
    }

    func testDisallowingServices() {
        // GIVEN
        sut.accessRoles = [.teamMember, .service]

        // WHEN
        sut.allowServices = false

        // THEN
        XCTAssertEqual(sut.accessRoles, [.teamMember])
    }

    func testAllowingGuestsAndServices() {
        // GIVEN
        sut.accessRoles = [.teamMember]
        sut.accessMode = .teamOnly

        // WHEN
        sut.allowGuests = true
        sut.allowServices = true

        // THEN
        XCTAssertEqual(sut.accessMode, .allowGuests)
        XCTAssertEqual(sut.accessRoles, [.teamMember, .guest, .service])
    }

    func testDisallowingGuestsAndServices() {
        // GIVEN
        sut.accessRoles = [.teamMember, .guest, .service]
        sut.accessMode = .allowGuests

        // WHEN
        sut.allowGuests = false
        sut.allowServices = false

        // THEN
        XCTAssertEqual(sut.accessMode, .teamOnly)
        XCTAssertEqual(sut.accessRoles, [.teamMember])
    }

    func testDefaultMode() {
        // when & then
        XCTAssertEqual(sut.accessMode, nil)
    }

    func testThatItCanReadTheMode() {
        // when
        sut.accessMode = []
        // then
        XCTAssertEqual(sut.accessMode, [])
    }

    func testThatItIgnoresAccessModeStringsKey() {
        // given
        sut.accessModeStrings = ["invite"]
        // when
        XCTAssertTrue(self.uiMOC.saveOrRollback())
        // then
        XCTAssertFalse(sut.keysThatHaveLocalModifications.contains("accessModeStrings"))

    }

    func testThatItIgnoresAccessRoleStringsKeyV2() {
        // given
        sut.accessModeStrings = ["guest"]
        // when
        XCTAssertTrue(self.uiMOC.saveOrRollback())
        // then
        XCTAssertFalse(sut.keysThatHaveLocalModifications.contains("accessRoleV2Strings"))
    }

    let testSetAccessMode: [(ConversationAccessMode?, [String]?)] = [(nil, nil),
                                                                     (ConversationAccessMode.teamOnly, []),
                                                                     (ConversationAccessMode.code, ["code"]),
                                                                     (ConversationAccessMode.`private`, ["private"]),
                                                                     (ConversationAccessMode.invite, ["invite"]),
                                                                     (ConversationAccessMode.legacy, ["invite"]),
                                                                     (ConversationAccessMode.allowGuests, ["code", "invite"])]


    func testThatModeSetWithOptionSetReflectedInStrings() {
        testSetAccessMode.forEach {
            // when
            sut.accessMode = $0
            // then
            if let strings = $1 {
                XCTAssertEqual(Set(sut.accessModeStrings!), Set(strings))
            }
            else {
                XCTAssertTrue(sut.accessModeStrings == nil)
            }
        }
    }


    func testThatModeSetWithStringsIsReflectedInOptionSet() {
        testSetAccessMode.forEach {
            // when
            sut.accessModeStrings = $1
            // then
            if let optionSet = $0 {
                XCTAssertEqual(sut.accessMode!, optionSet)
            }
            else {
                XCTAssertTrue(sut.accessMode == nil)
            }
        }
    }


    func testThatChangingAllowGuestsSetsAccessModeStrings() {
        [(true, ["code", "invite"], ConversationAccessRole.nonActivated.rawValue),
         (false, [], ConversationAccessRole.team.rawValue)].forEach {
            // when
            sut.allowGuests = $0.0
            // then
            XCTAssertEqual(Set(sut.accessModeStrings!), Set($0.1))
            XCTAssertEqual(Set(sut.accessRoleString!), Set($0.2))
        }
    }

    func testThatAccessModeStringsChangingAllowGuestsSets() {
        let values = [
            (true, ["code", "invite"], ConversationAccessRole.nonActivated.rawValue),
            (false, [], ConversationAccessRole.team.rawValue),
            (true, ["invite"], ConversationAccessRole.nonActivated.rawValue),
            (true, ["invite"], ConversationAccessRole.activated.rawValue)
        ]

        for (allowGuests, accessMode, accessRole) in values {
            // when
            sut.accessModeStrings = accessMode
            sut.accessRoleString = accessRole

            // then
            XCTAssertEqual(sut.allowGuests, allowGuests)
        }
    }

    func testThatTheConversationIsInsertedWithCorrectAccessModeAccessRole_Default_WithTeam() {
        // when
        let conversation = ZMConversation.insertGroupConversation(moc: self.uiMOC,
                                                                  participants: [],
                                                                  name: "Test Conversation",
                                                                  team: team)!
        // then
        XCTAssertEqual(Set(conversation.accessModeStrings!), ["code", "invite"])
        XCTAssertEqual(conversation.accessRoleString!, ConversationAccessRole.nonActivated.rawValue)
    }

    func testThatTheConversationIsInsertedWithCorrectAccessModeAccessRole_Default_NoTeam() {
        // when
        let conversation = ZMConversation.insertGroupConversation(moc: self.uiMOC,
                                                                  participants: [],
                                                                  name: "Test Conversation",
                                                                  team: nil)!
        // then
        XCTAssertTrue(conversation.accessModeStrings == nil)
        XCTAssertEqual(conversation.accessRoleString, nil)
    }

    func testThatTheConversationIsInsertedWithCorrectAccessModeAccessRole() {
        [(true, ["code", "invite"], ConversationAccessRole.nonActivated.rawValue),
         (false, [], ConversationAccessRole.team.rawValue)].forEach {
            // when
            let conversation = ZMConversation.insertGroupConversation(moc: self.uiMOC,
                                                                      participants: [],
                                                                      name: "Test Conversation",
                                                                      team: team,
                                                                      allowGuests: $0.0)!
            // then
            XCTAssertEqual(Set(conversation.accessModeStrings!), Set($0.1))
            XCTAssertEqual(Set(conversation.accessRoleString!), Set($0.2))
        }
    }

    let testSetAccessRole: [(ConversationAccessRole?, String?)] = [(ConversationAccessRole.activated, "activated"),
                                                                   (ConversationAccessRole.nonActivated, "non_activated"),
                                                                   (ConversationAccessRole.team, "team"),
                                                                   (nil, nil)]


    func testThatAccessRoleSetAccessRoleString() {
        testSetAccessRole.forEach {
            // when
            sut.accessRole = $0.0
            // then
            XCTAssertEqual(sut.accessRoleString, $0.1)
        }
    }

    func testThatAccessRoleStringSetAccesseRole() {
        testSetAccessRole.forEach {
            // when
            sut.accessRoleString = $0.1
            // then
            XCTAssertEqual(sut.accessRole, $0.0)
        }
    }
}
