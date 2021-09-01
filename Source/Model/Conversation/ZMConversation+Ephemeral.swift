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

public enum MessageDestructionTimeoutKind {

    // TODO: These need better names

    case team
    case groupConversation
    case selfUser

}


public enum MessageDestructionTimeoutValue: RawRepresentable, Hashable {

    case none
    case tenSeconds
    case fiveMinutes
    case oneHour
    case oneDay
    case oneWeek
    case fourWeeks

    case custom(TimeInterval)

    public init(rawValue: TimeInterval) {
        switch rawValue {
        case 0: self = .none
        case 10: self = .tenSeconds
        case 300: self = .fiveMinutes
        case 3600: self = .oneHour
        case 86400: self = .oneDay
        case 604800: self = .oneWeek
        case 2419200: self = .fourWeeks
        default: self = .custom(rawValue)
        }
    }

    public var rawValue: TimeInterval {
        switch self {
        case .none: return 0
        case .tenSeconds: return 10
        case .fiveMinutes: return 300
        case .oneHour: return 3600
        case .oneDay: return 86400
        case .oneWeek: return 604800
        case .fourWeeks: return 2419200
        case .custom(let duration): return duration
        }
    }
    

}

extension MessageDestructionTimeoutValue: ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral {

    public init(integerLiteral value: TimeInterval) {
        self.init(rawValue: value)
    }
    
    public init(floatLiteral value: TimeInterval) {
        self.init(rawValue: value)
    }
}

public extension MessageDestructionTimeoutValue {

    static var all: [MessageDestructionTimeoutValue] {
        return [
            .none,
            .tenSeconds,
            .fiveMinutes,
            .oneHour,
            .oneDay,
            .oneWeek,
            .fourWeeks
        ]
    }
}

public extension MessageDestructionTimeoutValue {

    var isKnownTimeout: Bool {
        if case .custom = self {
            return false
        }
        return true
    }

}

public enum MessageDestructionTimeout: Equatable {
    case local(MessageDestructionTimeoutValue)
    case synced(MessageDestructionTimeoutValue)
}

fileprivate let longStyleFormatter: DateComponentsFormatter = {
    let formatter = DateComponentsFormatter()
    formatter.includesApproximationPhrase = false
    formatter.maximumUnitCount = 1
    formatter.unitsStyle = .full
    formatter.allowedUnits = [.year, .weekOfMonth, .day, .hour, .minute, .second]
    formatter.zeroFormattingBehavior = .dropAll
    return formatter
}()

public extension MessageDestructionTimeoutValue {
    
    var displayString: String? {
        guard .none != self else { return NSLocalizedString("input.ephemeral.timeout.none", comment: "") }
        return longStyleFormatter.string(from: TimeInterval(rawValue))
    }
    
    var shortDisplayString: String? {
        if isSeconds { return String(Int(rawValue)) }
        if isMinutes { return String(Int(rawValue / 60)) }
        if isHours { return String(Int(rawValue / 3600)) }
        if isDays { return String(Int(rawValue / 86400)) }
        if isWeeks { return String(Int(rawValue / 604800)) }
        if isYears { return String(Int(rawValue / TimeInterval.oneYearSinceNow())) }
        return nil
    }
    
}

public extension MessageDestructionTimeoutValue {
    
    var isSeconds: Bool {
        return rawValue < 60
    }
    
    var isMinutes: Bool {
        return 60..<3600 ~= rawValue
    }
    
    var isHours: Bool {
        return 3600..<86400 ~= rawValue
    }
    
    var isDays: Bool {
        return 86400..<604800 ~= rawValue
    }

    var isWeeks: Bool {
        return rawValue >= 604800 && !isYears
    }

    var isYears: Bool {
        return rawValue >= TimeInterval.oneYearSinceNow()
    }

}


extension TimeInterval {
    static func oneYearSinceNow() -> TimeInterval {
        let now = Date()
        let oneYear = Calendar.current.date(byAdding: .year, value: 1, to: now)

        return oneYear!.timeIntervalSince(now)
    }
}

public extension ZMConversation {

    /// The timeout value actively used with new messages.

    var activeMessageDestructionTimeoutValue: MessageDestructionTimeoutValue? {
        guard let kind = activeMessageDestructionTimeoutKind else { return nil }
        return messageDestructionTimeoutValue(for: kind)
    }

    /// The type of timeout used with new messages.

    var activeMessageDestructionTimeoutKind: MessageDestructionTimeoutKind? {
        if forcedMessageDestructionTimeout != nil {
            return .team
        } else if hasSyncedMessageDestructionTimeout {
            return .groupConversation
        } else if hasLocalMessageDestructionTimeout {
            return .selfUser
        } else {
            return nil
        }
    }

    /// The message destruction timeout value used for the given kind.
    ///
    /// This is not necessarily the timeout used when appending new messages. See `activeTimeoutValue`.

    func messageDestructionTimeoutValue(for kind: MessageDestructionTimeoutKind) -> MessageDestructionTimeoutValue {
        switch kind {
        case .team:
            return .init(rawValue: teamMessageDestructionTimeout)
        case .groupConversation:
            return .init(rawValue: syncedMessageDestructionTimeout)
        case .selfUser:
            return .init(rawValue: localMessageDestructionTimeout)
        }
    }

    var hasSyncedMessageDestructionTimeout: Bool {
        return messageDestructionTimeoutValue(for: .groupConversation) != .none
    }

    var hasLocalMessageDestructionTimeout: Bool {
        return messageDestructionTimeoutValue(for: .selfUser) != .none
    }

    @NSManaged internal var localMessageDestructionTimeout: TimeInterval
    @NSManaged internal var syncedMessageDestructionTimeout: TimeInterval


    private var forcedMessageDestructionTimeout: Double? {
        guard let context = managedObjectContext else { return nil }
        let selfDeletingMessageFeature = FeatureService(context: context).fetchSelfDeletingMesssages()

        if selfDeletingMessageFeature.isForcedOff {
            return 0
        } else if selfDeletingMessageFeature.isForcedOn {
            return Double(selfDeletingMessageFeature.config.enforcedTimeoutSeconds)
        } else {
            return nil
        }
    }

    private var teamMessageDestructionTimeout: TimeInterval {
        guard let context = managedObjectContext else { return 0 }
        let selfDeletingMessageFeature = FeatureService(context: context).fetchSelfDeletingMesssages()
        guard selfDeletingMessageFeature.status == .enabled else { return 0 }
        return TimeInterval(selfDeletingMessageFeature.config.enforcedTimeoutSeconds)
    }

    @objc
    @discardableResult
    func appendMessageTimerUpdateMessage(fromUser user: ZMUser, timer: Double, timestamp: Date) -> ZMSystemMessage {
        let message = appendSystemMessage(
            type: .messageTimerUpdate,
            sender: user,
            users: [user],
            clients: nil,
            timestamp: timestamp,
            messageTimer: timer
        )
        
        if isArchived && mutedMessageTypes == .none {
            isArchived = false
        }
        
        managedObjectContext?.enqueueDelayedSave()
        return message
    }

}

private extension Feature.SelfDeletingMessages {

    var isForcedOff: Bool {
        return status == .disabled
    }

    var isForcedOn: Bool {
        return config.enforcedTimeoutSeconds > 0
    }

    var timeoutValue: MessageDestructionTimeoutValue {
        return .init(rawValue: Double(config.enforcedTimeoutSeconds))
    }

}
