//
// Wire
// Copyright (C) 2022 Wire Swiss GmbH
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
import WireDataModel

class MockMLSController: MLSControllerProtocol {

    // MARK: - Types

    enum MockError: Error {

        case unmockedMethodCalled

    }

    struct Calls {

        var uploadKeyPackagesIfNeeded = [(String, NotificationContext)]()
        var createGroup = [MLSGroupID]()
        var conversationExists = [MLSGroupID]()
        var processWelcomeMessage = [String]()
        var decrypt = [(String, MLSGroupID)]()
        var addMembersToConversation = [([MLSUser], MLSGroupID)]()
        var removeMembersFromConversation = [([MLSClientID], MLSGroupID)]()

    }

    // MARK: - Properties

    var calls = Calls()

    // MARK: - Methods

    func uploadKeyPackagesIfNeeded(for clientID: String, with context: NotificationContext) async throws {
        calls.uploadKeyPackagesIfNeeded.append((clientID, context))
    }

    func createGroup(for groupID: MLSGroupID) throws {
        calls.createGroup.append(groupID)
    }

    typealias ConversationExistsMock = (MLSGroupID) -> Bool

    var conversationExistsMock: ConversationExistsMock?

    func conversationExists(groupID: MLSGroupID) -> Bool {
        calls.conversationExists.append(groupID)
        return conversationExistsMock?(groupID) ?? false
    }

    typealias ProcessWelcomeMessageMock = (String) throws -> MLSGroupID

    var processWelcomeMessageMock: ProcessWelcomeMessageMock?

    func processWelcomeMessage(welcomeMessage: String) throws -> MLSGroupID {
        calls.processWelcomeMessage.append(welcomeMessage)
        guard let mock = processWelcomeMessageMock else { throw MockError.unmockedMethodCalled }
        return try mock(welcomeMessage)
    }

    typealias DecryptMock = (String, MLSGroupID) throws -> Data?

    var decryptMock: DecryptMock?

    func decrypt(message: String, for groupID: MLSGroupID) throws -> Data? {
        calls.decrypt.append((message, groupID))
        guard let mock = decryptMock else { throw MockError.unmockedMethodCalled }
        return try mock(message, groupID)
    }

    func addMembersToConversation(with users: [MLSUser], for groupID: MLSGroupID) throws {
        calls.addMembersToConversation.append((users, groupID))
    }

    func removeMembersFromConversation(with clientIds: [MLSClientID], for groupID: MLSGroupID) throws {
        calls.removeMembersFromConversation.append((clientIds, groupID))
    }

}
