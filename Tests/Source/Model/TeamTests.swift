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


class TeamTests: BaseTeamTests {

    func testThatItCreatesANewTeamIfThereIsNone() {
        syncMOC.performGroupedBlockAndWait {
            let uuid = UUID.create()
            let sut = Team.fetchOrCreate(with: uuid, create: true, in: self.syncMOC)
            XCTAssertNotNil(sut)
            XCTAssertEqual(sut?.remoteIdentifier, uuid)
        }
    }

    func testThatItReturnsAnExistingTeamIfThereIsOne() {
        // given
        let sut = Team.insertNewObject(in: uiMOC)
        let uuid = UUID.create()
        sut.remoteIdentifier = uuid

        XCTAssert(uiMOC.saveOrRollback())
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.2))

        // when
        let existing = Team.fetchOrCreate(with: uuid, create: false, in: uiMOC)

        // then
        XCTAssertNotNil(existing)
        XCTAssertEqual(existing, sut)
    }

    func testThatItReturnsGuestsOfATeam() {
        do {
            // given
            let (team, _) = createTeamAndMember(for: .selfUser(in: uiMOC), with: .member)

            // we add actual team members as well
            createUserAndAddMember(to: team)
            createUserAndAddMember(to: team)

            // when
            let guest = ZMUser.insertNewObject(in: uiMOC)
            let conversation = try team.addConversation(with: [guest])!

            // then
            XCTAssertTrue(guest.isGuest(in: conversation))
            XCTAssertFalse(guest.isMember(of: team))
        } catch {
            XCTFail("Eror: \(error)")
        }
    }

    func testThatItDoesNotReturnGuestsOfOtherTeams() {
        do {
            // given
            let (team1, _) = createTeamAndMember(for: .selfUser(in: uiMOC), with: .member)
            let (team2, _) = createTeamAndMember(for: .selfUser(in: uiMOC), with: .member)

            // we add actual team members as well
            createUserAndAddMember(to: team1)
            let (otherUser, _) = createUserAndAddMember(to: team2)

            let guest = ZMUser.insertNewObject(in: uiMOC)

            // when
            let conversation1 = try team1.addConversation(with: [guest])!
            let conversation2 = try team2.addConversation(with: [otherUser])!

            // then
            XCTAssertTrue(guest.isGuest(in: conversation1))
            XCTAssertFalse(guest.isGuest(in: conversation2))
            XCTAssertFalse(guest.isGuest(in: conversation2))
            XCTAssertFalse(otherUser.isGuest(in: conversation1))
            XCTAssertFalse(guest.isMember(of: team1))
            XCTAssertFalse(guest.isMember(of: team2))
        } catch {
            XCTFail("Eror: \(error)")
        }
    }

    func testThatItUpdatesATeamWithPayload() {
        syncMOC.performGroupedBlockAndWait {
            // given
            let team = Team.insertNewObject(in: self.syncMOC)
            let userId = UUID.create()
            let assetId = UUID.create().transportString(), assetKey = UUID.create().transportString()

            let payload = [
                "name": "Wire GmbH",
                "creator": userId.transportString(),
                "icon": assetId,
                "icon_key": assetKey
            ]

            // when
            team.update(with: payload)

            // then
            XCTAssertEqual(team.creator?.remoteIdentifier, userId)
            XCTAssertEqual(team.name, "Wire GmbH")
            XCTAssertEqual(team.pictureAssetId, assetId)
            XCTAssertEqual(team.pictureAssetKey, assetKey)
        }
    }
    
}
