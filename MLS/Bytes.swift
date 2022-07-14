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

extension Bytes {

    var data: Data {
        return .init(self)
    }

    var base64String: String {
        return data.base64EncodedString()
    }

    init?(base64Encoded: String) {
        self = Data(base64Encoded: base64Encoded)?.bytes
    }
}

extension Data {

    var bytes: Bytes {
        return .init(self)
    }

}
