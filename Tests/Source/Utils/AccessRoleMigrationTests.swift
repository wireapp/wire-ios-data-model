//
//  AccessRoleMigrationTests.swift
//  WireDataModelTests
//
//  Created by Agisilaos Tsaraboulidis on 07.02.22.
//  Copyright © 2022 Wire Swiss GmbH. All rights reserved.
//

import Foundation
import XCTest
@testable import WireDataModel

class AccessRoleMigrationTests: DiskDatabaseTest {

    func testForcingToFetchConversationAccessRoles() {

        // GIVEN
        let selfUser = ZMUser.selfUser(in: moc)
        let team = createTeam()
        team.remoteIdentifier = UUID.create()
        _ = createMembership(user: selfUser, team: team)

        let groupConvo = createConversation()
        groupConvo.addParticipantAndUpdateConversationState(user: selfUser, role: nil)
        groupConvo.userDefinedName = "Group"
        groupConvo.needsToBeUpdatedFromBackend = false

        let groupConvoInTeam = createConversation()
        groupConvoInTeam.addParticipantAndUpdateConversationState(user: selfUser, role: nil)
        groupConvoInTeam.userDefinedName = "Group"
        groupConvoInTeam.needsToBeUpdatedFromBackend = false
        groupConvoInTeam.team = team

        let groupConvoInAnotherTeam = createConversation()
        groupConvoInAnotherTeam.addParticipantAndUpdateConversationState(user: selfUser, role: nil)
        groupConvoInAnotherTeam.userDefinedName = "Group"
        groupConvoInAnotherTeam.needsToBeUpdatedFromBackend = false
        groupConvoInAnotherTeam.teamRemoteIdentifier = UUID.create()

        let oneToOneConvo = createConversation()
        oneToOneConvo.addParticipantAndUpdateConversationState(user: selfUser, role: nil)
        oneToOneConvo.conversationType = .oneOnOne
        oneToOneConvo.userDefinedName = "OneToOne"
        oneToOneConvo.needsToBeUpdatedFromBackend = false

        self.moc.saveOrRollback()

        // WHEN
        WireDataModel.ZMConversation.forceToFetchConversationAccessRoles(in: moc)

        // THEN
        XCTAssertTrue(oneToOneConvo.needsToBeUpdatedFromBackend)
        XCTAssertTrue(groupConvoInTeam.needsToBeUpdatedFromBackend)
        XCTAssertTrue(groupConvo.needsToBeUpdatedFromBackend)
        XCTAssertTrue(groupConvoInAnotherTeam.needsToBeUpdatedFromBackend)
    }

}
