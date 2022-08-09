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
@testable import WireDataModel

final class ZMConversationTests_MLS: ZMConversationTestsBase {

    func testThatItFetchesConversationWithGroupID() {
        syncMOC.performGroupedBlockAndWait { [self] in
            // Given
            let groupID = MLSGroupID([1, 2, 3])
            let domain = "example.com"
            let conversation = self.createConversation(groupID: groupID, domain: domain)

            // When
            let fetchedConversation = ZMConversation.fetch(with: groupID, domain: domain, in: syncMOC)

            // Then
            XCTAssertEqual(fetchedConversation, conversation)
        }
    }

    private func createConversation(groupID: MLSGroupID, domain: String) -> ZMConversation? {
        let conversation = ZMConversation.insertNewObject(in: syncMOC)
        conversation.remoteIdentifier = NSUUID.create()
        conversation.mlsGroupID = groupID
        conversation.domain = domain
        XCTAssert(syncMOC.saveOrRollback())
        return conversation
    }

}
