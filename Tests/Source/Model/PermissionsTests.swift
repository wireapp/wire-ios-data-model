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


class PermissionsTests: BaseZMClientMessageTests {

    private let allPermissions: Permissions = [
        .createConversation,
        .deleteConversation,
        .addTeamMember,
        .removeTeamMember,
        .addRemoveConversationMember,
        .modifyConversationMetaData,
        .getMemberPermissions,
        .getTeamConversations,
        .getBilling,
        .setBilling,
        .setTeamData,
        .deleteTeam,
        .setMemberPermissions
    ]

    func testThatDefaultValueDoesNotHaveAnyPermissions() {
        // given
        let sut = Permissions(rawValue: 0)

        // then
        XCTAssertFalse(sut.contains(.createConversation))
        XCTAssertFalse(sut.contains(.deleteConversation))
        XCTAssertFalse(sut.contains(.addTeamMember))
        XCTAssertFalse(sut.contains(.removeTeamMember))
        XCTAssertFalse(sut.contains(.addRemoveConversationMember))
        XCTAssertFalse(sut.contains(.modifyConversationMetaData))
        XCTAssertFalse(sut.contains(.getMemberPermissions))
        XCTAssertFalse(sut.contains(.getTeamConversations))
        XCTAssertFalse(sut.contains(.getBilling))
        XCTAssertFalse(sut.contains(.setBilling))
        XCTAssertFalse(sut.contains(.setTeamData))
        XCTAssertFalse(sut.contains(.deleteTeam))
        XCTAssertFalse(sut.contains(.setMemberPermissions))
    }

    func testMemberPermissions() {
        XCTAssertEqual(Permissions.member, [.createConversation, .deleteConversation, .addRemoveConversationMember, .modifyConversationMetaData, .getMemberPermissions, .getTeamConversations])
    }

    func testPartnerPermissions() {
        // given
        let permissions: Permissions = [
            .createConversation,
            .getTeamConversations
        ]

        // then
        XCTAssertEqual(Permissions.collaborator, permissions)
    }

    func testAdminPermissions() {
        // given
        let adminPermissions: Permissions = [
            .createConversation,
            .deleteConversation,
            .addRemoveConversationMember,
            .modifyConversationMetaData,
            .getMemberPermissions,
            .getTeamConversations,
            .addTeamMember,
            .removeTeamMember,
            .setTeamData,
            .setMemberPermissions
        ]

        // then
        XCTAssertEqual(Permissions.admin, adminPermissions)
    }

    func testOwnerPermissions() {
        XCTAssertEqual(Permissions.owner, allPermissions)
    }

    // MARK: - Transport Data

    func testThatItCreatesPermissionsFromPayload() {
        XCTAssertEqual(Permissions(rawValue: 5), [.createConversation, .addTeamMember])
        XCTAssertEqual(Permissions(rawValue: 0x401), .collaborator)
        XCTAssertEqual(Permissions(rawValue: 1587), .member)
        XCTAssertEqual(Permissions(rawValue: 5951), .admin)
        XCTAssertEqual(Permissions(rawValue: 8191), .owner)
    }

    func testThatItCreatesEmptyPermissionsFromEmptyPayload() {
        XCTAssertEqual(Permissions(rawValue: 0), [])
    }

    // MARK: - TeamRole (Objective-C Interoperability)

    func testThatItCreatesTheCorrectSwiftPermissions() {
        XCTAssertEqual(TeamRole.collaborator.permissions, .collaborator)
        XCTAssertEqual(TeamRole.member.permissions, .member)
        XCTAssertEqual(TeamRole.admin.permissions, .admin)
        XCTAssertEqual(TeamRole.owner.permissions, .owner)
    }

    func testThatItSetsTeamRolePermissions() {
        // given
        let member = Member.insertNewObject(in: uiMOC)

        // when
        member.setTeamRole(.admin)

        // then
        XCTAssertEqual(member.permissions, .admin)
    }

    func testTeamRoleIsARelationships() {
        XCTAssert(TeamRole.none.isA(role: .none))
        XCTAssertFalse(TeamRole.none.isA(role: .collaborator))
        XCTAssertFalse(TeamRole.none.isA(role: .member))
        XCTAssertFalse(TeamRole.none.isA(role: .admin))
        XCTAssertFalse(TeamRole.none.isA(role: .owner))
        
        XCTAssert(TeamRole.collaborator.isA(role: .none))
        XCTAssert(TeamRole.collaborator.isA(role: .collaborator))
        XCTAssertFalse(TeamRole.collaborator.isA(role: .member))
        XCTAssertFalse(TeamRole.collaborator.isA(role: .admin))
        XCTAssertFalse(TeamRole.collaborator.isA(role: .owner))
        
        XCTAssert(TeamRole.member.isA(role: .none))
        XCTAssert(TeamRole.member.isA(role: .collaborator))
        XCTAssert(TeamRole.member.isA(role: .member))
        XCTAssertFalse(TeamRole.member.isA(role: .admin))
        XCTAssertFalse(TeamRole.member.isA(role: .owner))
        
        XCTAssert(TeamRole.admin.isA(role: .none))
        XCTAssert(TeamRole.admin.isA(role: .collaborator))
        XCTAssert(TeamRole.admin.isA(role: .member))
        XCTAssert(TeamRole.admin.isA(role: .admin))
        XCTAssertFalse(TeamRole.admin.isA(role: .owner))
        
        XCTAssert(TeamRole.owner.isA(role: .none))
        XCTAssert(TeamRole.owner.isA(role: .collaborator))
        XCTAssert(TeamRole.owner.isA(role: .member))
        XCTAssert(TeamRole.owner.isA(role: .admin))
        XCTAssert(TeamRole.owner.isA(role: .owner))
    }
}
