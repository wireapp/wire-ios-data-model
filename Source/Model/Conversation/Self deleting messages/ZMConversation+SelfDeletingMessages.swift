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







public enum MessageDestructionTimeout: Equatable {
    case local(MessageDestructionTimeoutValue)
    case synced(MessageDestructionTimeoutValue)
}


public extension ZMConversation {

    /// The timeout value actively used with new messages.

    var activeMessageDestructionTimeoutValue: MessageDestructionTimeoutValue? {
        guard let type = activeMessageDestructionTimeoutType else { return nil }
        return messageDestructionTimeoutValue(for: type)
    }

    /// The type of timeout used with new messages.

    var activeMessageDestructionTimeoutType: MessageDestructionTimeoutType? {
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

    /// The message destruction timeout value used for the given type.
    ///
    /// This is not necessarily the timeout used when appending new messages. See `activeTimeoutValue`.

    func messageDestructionTimeoutValue(for type: MessageDestructionTimeoutType) -> MessageDestructionTimeoutValue {
        switch type {
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
