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

/// A type that can be used an attribute value.
public protocol AnalyticsAttributeValue {

    /// The string representation of the value.
    var analyticsValue: String { get }

}

/// An numeric container used to protect the privacy of integer values.
///
/// This is achieved by rounding an exact value by a certain factor. The
/// rounding is logarithmic, meaning that small numbers are only slighly
/// rounded whereas larger numbers will be rounded more. This kind of
/// rounding is roughly equivalent to having buckets of increasing size.
public struct RoundedInt: AnalyticsAttributeValue {

    public let analyticsValue: String

    /// Create a rounded integer by a certain factor.
    ///
    /// - Parameters:
    ///     - exactValue: The integer value to round.
    ///     - factor: Determines how much the value is rounded.
    public init(_ exactValue: Int, factor: Int) {
        let exactValue = Double(exactValue)
        let factor = Double(factor)
        let roundedValue = Int(ceil(pow(2, (floor(factor * log2(exactValue)) / factor))))
        analyticsValue = String(describing: roundedValue)
    }

}

public extension Int {

    func rounded(byFactor factor: Int) -> RoundedInt {
        return RoundedInt(self, factor: factor)
    }

}

extension UUID: AnalyticsAttributeValue {

    public var analyticsValue: String {
        return transportString()
    }

}

extension String: AnalyticsAttributeValue {

    public var analyticsValue: String {
        return self
    }

}

extension TeamRole: AnalyticsAttributeValue {

    public var analyticsValue: String {
        switch self {
            case .member, .admin, .owner:
                return "member"
            case .partner:
                return "external"
            case .none:
                return "wireless"
        }
    }

}
