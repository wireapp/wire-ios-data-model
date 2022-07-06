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

private let log = ZMSLog(tag: "bytes-conversion")

public typealias Bytes = [UInt8]

public protocol BytesConvertible {
    var bytes: Bytes { get }
    init?(bytes: Bytes)
}

extension BytesConvertible {
    public var bytes: Bytes {
        return Data(from: self).bytes
    }

    public init?(bytes: Bytes) {
        guard let object: Self = bytes.data.object() else {
            return nil
        }
        self = object
    }
}

extension Data {

    enum ByteConversionError: LocalizedError {
        case invalidBufferSize

        var errorDescription: String? {
            switch self {
            case .invalidBufferSize:
                return "raw buffer byte count doesn't match the type's memory layout"
            }
        }
    }

    var bytes: Bytes { Bytes(self) }

    func object<T: BytesConvertible>() -> T? {
        do {
            return try self.withUnsafeBytes {
                guard $0.count == MemoryLayout<T>.size else {
                    throw ByteConversionError.invalidBufferSize
                }

                return $0.load(as: T.self)
            }
        } catch {
            log.error("Failed to load object from raw data: \(error.localizedDescription)")
            return nil
        }
    }

    init<T: BytesConvertible>(from object: T) {
        self = Swift.withUnsafeBytes(of: object) { Data($0) }
    }
}

extension Bytes {
    var data: Data { Data(self) }
}

extension UUID: BytesConvertible {}
extension String: BytesConvertible {}

