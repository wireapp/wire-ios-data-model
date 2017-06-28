//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
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


import WireTesting
@testable import WireDataModel


class MemberTests: BaseTeamTests {

    func testThatItStoresThePermissionsOfAMember() {
        // given
        let sut = Member.insertNewObject(in: uiMOC)

        // when
        sut.permissions = .member
        XCTAssert(uiMOC.saveOrRollback())
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.1))

        // then
        XCTAssertEqual(sut.permissions, .member)
    }

    func testThatItReturnsThePermissionsOfAUser() {
        // given
        let user = ZMUser.insertNewObject(in: uiMOC)

        // when
        createTeamAndMember(for: user, with: .member)

        XCTAssert(uiMOC.saveOrRollback())
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.1))

        // then
        XCTAssertEqual(user.permissions, .member)
    }

    func testThatItReturnsIfAUserIsMemberOfATeam() {
        // given
        let user = ZMUser.insertNewObject(in: uiMOC)

        // when
        createTeamAndMember(for: user, with: .member)

        XCTAssert(uiMOC.saveOrRollback())
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.1))

        // then
        XCTAssertTrue(user.isTeamMember)
    }

    func testThatItReturnsIfAUserIsNotAMemberOfATeam() {
        // given
        let user = ZMUser.insertNewObject(in: uiMOC)

        // when
        XCTAssert(uiMOC.saveOrRollback())
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.1))

        // then
        XCTAssertFalse(user.hasTeam)
    }

    func testThatItReturnsIfAUserHasTeams() {
        // given
        let user = ZMUser.insertNewObject(in: uiMOC)

        // when
        createTeamAndMember(for: user, with: .member)

        XCTAssert(uiMOC.saveOrRollback())
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.1))

        // then
        XCTAssertTrue(user.hasTeam)
    }

    func testThatItReturnsTheTeamOfAUser() {
        // given
        let user = ZMUser.insertNewObject(in: uiMOC)

        // when
        let (team, _) = createTeamAndMember(for: user, with: .member)

        XCTAssert(uiMOC.saveOrRollback())
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.1))

        // then
        XCTAssertTrue(user.isTeamMember)
        XCTAssertEqual(user.team, team)
        XCTAssertTrue(user.hasTeam)
        XCTAssertEqual(user.permissions, .member)
    }

    func testThatItReturnsExistingMemberOfAUserInATeam() {
        // given
        let user = ZMUser.insertNewObject(in: uiMOC)
        let (team, existingMember) = createTeamAndMember(for: user)

        // when
        let member = Member.getOrCreateMember(for: user, in: team, context: uiMOC)

        // then
        XCTAssertEqual(member, existingMember)
    }

    func testThatItCreatesNewMemberIfUserHasNoMemberInTeam() {
        // given
        let user = ZMUser.insertNewObject(in: uiMOC)
        let team = Team.insertNewObject(in: uiMOC)

        // when
        let member = Member.getOrCreateMember(for: user, in: team, context: uiMOC)

        // then
        XCTAssertNotNil(member)
        XCTAssertEqual(member.user, user)
        XCTAssertEqual(member.team, team)
    }
    
    func testThatItSetsTheUsersRemoteIDAsMemberRemoteId() {
        // given
        let user = ZMUser.insertNewObject(in: uiMOC)
        user.remoteIdentifier = UUID()
        let team = Team.insertNewObject(in: uiMOC)
        
        // when
        let member = Member.getOrCreateMember(for: user, in: team, context: uiMOC)
        
        // then
        XCTAssertNotNil(member.remoteIdentifier)
        XCTAssertEqual(member.remoteIdentifier, user.remoteIdentifier)
    }

}


// MARK: - Transport


extension MemberTests {

    func testThatItUpdatesAMemberWithResponsePayload() {
        // given
        let user = ZMUser.insertNewObject(in: uiMOC)
        user.remoteIdentifier = .create()
        let team = Team.insertNewObject(in: uiMOC)
        let member = Member.getOrCreateMember(for: user, in: team, context: uiMOC)

        let payload: [String: Any] = [
            "user": user.remoteIdentifier!.transportString(),
            "permissions": ["self": 33, "copy": 0]
        ]

        // when
        member.updatePermissions(with: payload)

        // then
        XCTAssertEqual(member.permissions, [.createConversation, .removeConversationMember])
    }

    func testThatItCreatesAndUpdatesAMemberFromTransportData() {
        syncMOC.performAndWait {
            // given
            let team = Team.insertNewObject(in: self.syncMOC)
            team.remoteIdentifier = .create()
            let userId = UUID.create()

            let payload: [String: Any] = [
                "user": userId.transportString(),
                "permissions": ["self": 5951, "copy": 0]
            ]

            // when
            guard let member = Member.createOrUpdate(with: payload, in: team, context: self.syncMOC) else { return XCTFail("No member created") }

            // then
            XCTAssertEqual(member.user?.remoteIdentifier, userId)
            XCTAssertEqual(member.permissions, .admin)
            XCTAssertEqual(member.team, team)
        }
    }
    
}
