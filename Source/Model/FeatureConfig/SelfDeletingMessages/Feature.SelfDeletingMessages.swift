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

public extension Feature {

    struct SelfDeletingMessages: Codable {

        // MARK: - Properties

        public let status: Status
        public let config: Config

        // MARK: - Life cycle

        public init(status: Feature.Status = .enabled, config: Config = .init()) {
            self.status = status
            self.config = config
        }

        // MARK: - Types

        public struct Config: Codable {

            /// The number of seconds after which all enforced self-deleting messages
            /// will delete.
            ///
            /// A value of 0 indicates that the self-deleting messages are not mandatory.

            public let enforcedTimeoutSeconds: UInt

            public init(enforcedTimeoutSeconds: UInt = 0) {
                self.enforcedTimeoutSeconds = enforcedTimeoutSeconds
            }

        }

    }

}
