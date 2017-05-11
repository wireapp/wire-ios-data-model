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


class Conversationtests_Teams: BaseTeamTests {

    var team: Team!
    var user: ZMUser!
    var member: Member!
    var otherUser: ZMUser!

    override func setUp() {
        super.setUp()

        user = .selfUser(in: uiMOC)
        team = .insertNewObject(in: uiMOC)
        member = .insertNewObject(in: uiMOC)
        otherUser = .insertNewObject(in: uiMOC)
        member.user = user
        member.team = team
        member.permissions = .member

        let otherUserMember = Member.insertNewObject(in: uiMOC)
        otherUserMember.team = team
        otherUserMember.user = otherUser

        XCTAssert(uiMOC.saveOrRollback())
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.1))
    }

    override func tearDown() {
        team = nil
        user = nil
        member = nil
        otherUser = nil
        super.tearDown()
    }

    func testThatItCreatesAOneToOneConversationInATeam() {
        // given
        otherUser.remoteIdentifier = .create()

        // when
        let conversation = ZMConversation.fetchOrCreateTeamConversation(in: uiMOC, withParticipant: otherUser, team: team)

        // then
        XCTAssertNotNil(conversation)
        XCTAssertEqual(conversation?.conversationType, .group)
        XCTAssertEqual(conversation?.otherActiveParticipants, [otherUser])
        XCTAssertEqual(conversation?.team, team)
    }

    func testThatItReturnsAnExistingOneOnOneConversationIfThereAlreadyIsOneInATeam() {
        // given
        let conversation = ZMConversation.fetchOrCreateTeamConversation(in: uiMOC, withParticipant: otherUser, team: team)
        // when
        let newConversation = ZMConversation.fetchOrCreateTeamConversation(in: uiMOC, withParticipant: otherUser, team: team)

        // then
        XCTAssertEqual(conversation, newConversation)
    }

    func testThatItDoesNotReturnAnExistingConversationFromTheSameTeamWithNoParticipants() {
        // given
        let conversation = ZMConversation.insertNewObject(in: uiMOC)
        conversation.conversationType = .group
        conversation.team = team

        // when
        let newConversation = ZMConversation.fetchOrCreateTeamConversation(in: uiMOC, withParticipant: otherUser, team: team)

        // then
        XCTAssertNotEqual(conversation, newConversation)
    }

    func testThatItReturnsNotNilWhenAskedForOneOnOneConversationWithoutTeam() {
        // given
        let oneOnOne = ZMConversation.insertNewObject(in: uiMOC)
        oneOnOne.conversationType = .oneOnOne
        oneOnOne.connection = .insertNewObject(in: uiMOC)
        oneOnOne.connection?.status = .accepted
        let userOutsideTeam = ZMUser.insertNewObject(in: uiMOC)
        oneOnOne.connection?.to = userOutsideTeam

        // then
        let teamConversationWithGuest = userOutsideTeam.oneToOneConversation(in: team)
        XCTAssertNotNil(teamConversationWithGuest)
        XCTAssertNotEqual(teamConversationWithGuest, oneOnOne)
        XCTAssertEqual(userOutsideTeam.oneToOneConversation(in: nil), oneOnOne)
    }

    func testThatItCreatesOneOnOneConversationInDifferentTeam() {
        // given
        let otherTeam = Team.insertNewObject(in: uiMOC)
        let otherMember = Member.insertNewObject(in: uiMOC)
        otherMember.permissions = .member
        otherMember.team = otherTeam
        otherMember.user = user
        let otherUserMember = Member.insertNewObject(in: uiMOC)
        otherUserMember.user = otherUser
        otherUserMember.team = otherTeam

        let conversation = ZMConversation.fetchOrCreateTeamConversation(in: uiMOC, withParticipant: otherUser, team: team)
        // when
        let newConversation = ZMConversation.fetchOrCreateTeamConversation(in: uiMOC, withParticipant: otherUser, team: otherTeam)

        // then
        XCTAssertNotEqual(conversation, newConversation)
    }

    func testThatItCanCreateAOneOnOneConversationWithAParticipantNotInTheTeam() {
        // given
        let userOutsideTeam = ZMUser.insertNewObject(in: uiMOC)

        // when
        let conversation = ZMConversation.fetchOrCreateTeamConversation(in: uiMOC, withParticipant: userOutsideTeam, team: team)

        // then
        XCTAssertNotNil(conversation)
        XCTAssertNil(userOutsideTeam.oneToOneConversation(in: nil))
    }

    func testThatItReturnsTeamConversationForOneOnOneConversation() {
        // given
        let oneOnOne = ZMConversation.insertNewObject(in: uiMOC)
        oneOnOne.conversationType = .oneOnOne
        oneOnOne.connection = .insertNewObject(in: uiMOC)
        oneOnOne.connection?.status = .accepted
        oneOnOne.connection?.to = otherUser

        // when
        let teamOneOnOne = ZMConversation.fetchOrCreateTeamConversation(in: uiMOC, withParticipant: otherUser, team: team)

        // then
        XCTAssertEqual(otherUser.oneToOneConversation(in: nil), oneOnOne)
        XCTAssertEqual(otherUser.oneToOneConversation(in: team), teamOneOnOne)
    }

    func testThatItCreatesAConversationWithMultipleParticipantsInATeam() {
        // given
        let user1 = ZMUser.insertNewObject(in: uiMOC)
        let user2 = ZMUser.insertNewObject(in: uiMOC)

        // when
        let conversation = ZMConversation.insertGroupConversation(into: uiMOC, withParticipants: [user1, user2], in: team)

        // then
        XCTAssertNotNil(conversation)
        XCTAssertEqual(conversation?.conversationType, .group)
        XCTAssertEqual(conversation?.otherActiveParticipants, [user1, user2])
        XCTAssertEqual(conversation?.team, team)
    }

    func testThatUIMethodThrowsWhenPermissionsAreInsuficcient() {
        do {
            // given
            member.permissions = Permissions(rawValue: 0)
            let otherUser = ZMUser.insertNewObject(in: uiMOC)

            // when
            _ = try team.addConversation(with: [otherUser])
            XCTFail("Should not be executed")
        } catch {
            // then
            XCTAssertEqual(error as! TeamError, TeamError.insufficientPermissions)
        }
    }

    func testThatItCreatesAConversationWithOnlyAGuest() {
        do {
            // given
            let (team, _) = createTeamAndMember(for: .selfUser(in: uiMOC), with: .member)
            let guest = ZMUser.insertNewObject(in: uiMOC)

            // when
            let conversation = try team.addConversation(with: [guest])
            XCTAssertNotNil(conversation)
        } catch {
            XCTFail("Eror: \(error)")
        }
    }


    func testThatItCreatesAConversationWithAnotherMember() {
        do {
            // given
            let (team, _) = createTeamAndMember(for: .selfUser(in: uiMOC), with: .member)
            let otherUser = ZMUser.insertNewObject(in: uiMOC)
            let otherMember = Member.insertNewObject(in: uiMOC)
            otherMember.team = team
            otherMember.user = otherUser

            // when
            let conversation = try team.addConversation(with: [otherUser])
            XCTAssertNotNil(conversation)
            XCTAssertEqual(conversation?.otherActiveParticipants, [otherUser])
            XCTAssertEqual(conversation?.team, team)
        } catch {
            XCTFail("Eror: \(error)")
        }
    }

}

