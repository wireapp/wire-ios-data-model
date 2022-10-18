
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

public final class FetchPublicGroupStateAction: EntityAction {

    // MARK: - Types

    public typealias Result = String

    public enum Failure: Error, Equatable {

        case endpointUnavailable
        case noConversation
        case missingGroupInfo
        case conversationIDOrDomainNotFound
        case malformedResponse
        case emptyParameters
        case unknown(status: Int)

        public var errorDescription: String? {
            switch self {

            case .endpointUnavailable:
                return "Endpoint unavailable."
            case .noConversation:
                return "Conversation not found"
            case .missingGroupInfo:
                return "The conversation has no group information"
            case .conversationIDOrDomainNotFound:
                return "Conversation ID Or domain not found."
            case .malformedResponse:
                return "Malformed response"
            case.emptyParameters:
                return "Empty parameters."
            case .unknown(let status):
                return "Unknown error (response status: \(status))"
            }
        }
    }

    // MARK: - Properties

    public var resultHandler: ResultHandler?
    public var conversationId: String
    public var domain: String

    // MARK: - Life cycle

    public init(
        conversationId: String,
        domain: String,
        resultHandler: ResultHandler? = nil
    ) {
        self.conversationId = conversationId
        self.domain = domain
        self.resultHandler = resultHandler
    }
}
