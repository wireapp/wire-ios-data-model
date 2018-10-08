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

class GenericMessageTests_NativePush: BaseZMMessageTests {

    func testThatItSetsNativePushToFalseWhenSendingAConfirmationMessage() {
        let message = ZMGenericMessage.message(content: ZMConfirmation.confirm(messageId: UUID.create()))
        assertThatItSetsNativePush(to: false, for: message)
    }

    func testThatItSetsNativePushToTrueWhenSendingATextMessage() {
        let message = ZMGenericMessage.message(content: ZMText.text(with: "Text"))
        assertThatItSetsNativePush(to: true, for: message)
    }

    func assertThatItSetsNativePush(to nativePush: Bool, for message: ZMGenericMessage, line: UInt = #line) {
        createSelfClient()

        syncMOC.performGroupedBlock {
            // given
            let user = ZMUser.insertNewObject(in: self.syncMOC)
            user.remoteIdentifier = .create()
            let connection = ZMConnection.insertNewObject(in: self.syncMOC)
            connection.to = user

            let conversation = ZMConversation.insertNewObject(in: self.syncMOC)
            conversation.connection = connection
            conversation.conversationType = .oneOnOne

            // when
            let (data, _) = message.encryptedMessagePayloadData(conversation, externalData: nil)!
            let builder = ZMNewOtrMessage.builder()!
            builder.merge(from: data)
            guard let otrMessage = builder.build() else { return XCTFail("Unable to build ZMNewOTRMessage", line: line) }

            // then
            XCTAssertTrue(otrMessage.hasNativePush(), line: line)
            XCTAssertEqual(otrMessage.nativePush(), nativePush, "Wrong value for nativePush", line: line)
        }

        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5), line: line)
    }
    
}


