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

public typealias Bytes = [UInt8]

/// Represents the identifer for an MLS group.

public struct MLSGroupID: Equatable {

    let data: Data

    /// Base 64 encoded representation, used when sending the
    /// id over the network.

    public var base64EncodedString: String {
        return data.base64EncodedString()
    }

    /// The byte array representing the id.

    public var bytes: Bytes {
        return data.bytes
    }

    public init(data: Data) {
        self.data = data
    }

    public init(bytes: Bytes) {
        data = bytes.data
    }

}

extension Bytes {

    var data: Data {
        return .init(self)
    }

}

extension Data {

    var bytes: Bytes {
        return .init(self)
    }

}
