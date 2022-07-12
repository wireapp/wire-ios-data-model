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

public class SendMLSWelcomeAction: EntityAction {

    // MARK: - Types

    public typealias Result = Void

    public enum Failure: LocalizedError, Equatable {

        case emptyParameters
        case endpointUnavailable
        case invalidBody
        case keyPackageRefNotFound
        case unknown(status: Int)

        public var errorDescription: String? {
            switch self {
            case .emptyParameters:
                return "Empty parameter(s)."
            case .endpointUnavailable:
                return "Endpoint unavailable."
            case .invalidBody:
                return "Invalid body."
            case .keyPackageRefNotFound:
                return "A referenced key package could not be mapped to a known client."
            case .unknown(let status):
                return "Unknown error (response status: \(status))"
            }
        }
    }

    // MARK: - Properties

    // TODO: Find out what type the body should be
    public let body: String
    public var resultHandler: ResultHandler?

    public init(body: String, resultHandler: ResultHandler? = nil) {
        self.body = body
        self.resultHandler = resultHandler
    }
}