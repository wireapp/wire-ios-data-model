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

import XCTest

class ZMManagedObjectFetchingTests: DatabaseBaseTest {

    var mocs: CoreDataStack!

    public override func setUp() {
        super.setUp()
        self.mocs = self.createStorageStackAndWaitForCompletion()
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 1))
    }

    public override func tearDown() {
        self.mocs = nil
        super.tearDown()
    }

    // MARK - Fetch using remote identifier and domain

    func testItFetchesEntityByRemoteIdentifier_WhenObjectIsRegisteredInContext() throws {
        // given
        let uuid = UUID()
        let user = ZMUser.insertNewObject(in: mocs.viewContext)
        user.remoteIdentifier = uuid

        // when
        let fetched = ZMUser.fetch(with: uuid, in: mocs.viewContext)

        // then
        XCTAssertEqual(user, fetched)
    }

    func testItFetchesEntityByRemoteIdentifier_WhenObjectIsNotRegisteredInContext() throws {
        // given
        let uuid = UUID()
        let user = ZMUser.insertNewObject(in: mocs.viewContext)
        user.remoteIdentifier = uuid
        try mocs.viewContext.save()
        mocs.viewContext.refresh(user, mergeChanges: false)

        // when
        let fetched = ZMUser.fetch(with: uuid, in: mocs.viewContext)

        // then
        XCTAssertEqual(user.objectID, fetched?.objectID)
    }

    func testItDoesntFetchEntityByRemoteIdentifier_WhenRemoteIdentifierDoesntMatch() throws {
        // given
        let uuid = UUID()
        let user = ZMUser.insertNewObject(in: mocs.viewContext)
        user.remoteIdentifier = uuid

        // when
        let fetched = ZMUser.fetch(with: UUID(), in: mocs.viewContext)

        // then
        XCTAssertNil(fetched)
    }

    func testItDoesntFetchEntityByRemoteIdentifier_WhenEntityDoesntMatch() throws {
        // given
        let uuid = UUID()
        let conversation = ZMConversation.insertNewObject(in: mocs.viewContext)
        conversation.remoteIdentifier = uuid

        // when
        let fetched = ZMUser.fetch(with: uuid, in: mocs.viewContext)

        // then
        XCTAssertNil(fetched)
    }

    // MARK - Fetch using remote identifier and domain

    func testThatItFetchesEntityByDomain_WhenObjectIsRegisteredInContext() throws {
        // given
        let domain = "example.com"
        let selfUser = ZMUser.selfUser(in: mocs.viewContext)
        selfUser.domain = domain

        let uuid = UUID()
        let user = ZMUser.insertNewObject(in: mocs.viewContext)
        user.remoteIdentifier = uuid
        user.domain = domain

        // when
        let fetched = ZMUser.fetch(with: uuid, domain: domain, in: mocs.viewContext)

        // then
        XCTAssertEqual(user.objectID, fetched?.objectID)
    }

    func testThatItFetchesEntityByDomain_WhenObjectIsNotRegisteredInContext() throws {
        // given
        let selfUser = ZMUser.selfUser(in: mocs.viewContext)
        selfUser.domain = "example.com"

        let uuid = UUID()
        let user = ZMUser.insertNewObject(in: mocs.viewContext)
        user.remoteIdentifier = uuid
        user.domain = "example.com"
        try mocs.viewContext.save()
        mocs.viewContext.refresh(user, mergeChanges: false)

        // when
        let fetched = ZMUser.fetch(with: uuid, in: mocs.viewContext)

        // then
        XCTAssertEqual(user.objectID, fetched?.objectID)
    }

    func testThatItFetchesEntityByDomain_WhenEntityDomainIsNilAndSearchDomainMatchesSelfUserDomain() throws {
        // given
        let domain = "example.com"
        let selfUser = ZMUser.selfUser(in: mocs.viewContext)
        selfUser.domain = "example.com"

        let uuid = UUID()
        let user = ZMUser.insertNewObject(in: mocs.viewContext)
        user.remoteIdentifier = uuid

        // when
        let fetched = ZMUser.fetch(with: uuid, domain: domain, in: mocs.viewContext)

        // then
        XCTAssertEqual(user.objectID, fetched?.objectID)
    }

    func testThatItFetchesEntityByDomain_WhenEntityDomainIsNilAndSelfUserDomainIsNil() throws {
        // given
        let uuid = UUID()
        let user = ZMUser.insertNewObject(in: mocs.viewContext)
        user.remoteIdentifier = uuid

        // when
        let fetched = ZMUser.fetch(with: uuid, domain: "different.com", in: mocs.viewContext)

        // then
        XCTAssertEqual(user.objectID, fetched?.objectID)
    }

    func testThatItDoesntFetchEntityByDomain_WhenEntityDomainDoesntMatchSearchDomain() throws {
        // given
        let domain = "example.com"
        let selfUser = ZMUser.selfUser(in: mocs.viewContext)
        selfUser.domain = domain

        let uuid = UUID()
        let user = ZMUser.insertNewObject(in: mocs.viewContext)
        user.remoteIdentifier = uuid
        user.domain = domain

        // when
        let fetched = ZMUser.fetch(with: uuid, domain: "different.com", in: mocs.viewContext)

        // then
        XCTAssertNil(fetched)
    }

    func testThatItDoesntFetchEntityByDomain_WhenEntityDomainIsNonNilAndSearchDomainIsNil() throws {
        // given
        let selfUser = ZMUser.selfUser(in: mocs.viewContext)
        selfUser.domain = "different.com"

        let domain = "example.com"
        let uuid = UUID()
        let user = ZMUser.insertNewObject(in: mocs.viewContext)
        user.remoteIdentifier = uuid
        user.domain = domain

        // when
        let fetched = ZMUser.fetch(with: uuid, domain: nil, in: mocs.viewContext)

        // then
        XCTAssertNil(fetched)
    }

    func testThatItDoesntFetchEntityByDomain_WhenEntityDomainIsNonNilAndSelfUserDomainIsNil() throws {
        // given
        let selfUser = ZMUser.selfUser(in: mocs.viewContext)
        selfUser.domain = nil

        let domain = "example.com"
        let uuid = UUID()
        let user = ZMUser.insertNewObject(in: mocs.viewContext)
        user.remoteIdentifier = uuid
        user.domain = domain

        // when
        let fetched = ZMUser.fetch(with: uuid, domain: nil, in: mocs.viewContext)

        // then
        XCTAssertNil(fetched)
    }

}
