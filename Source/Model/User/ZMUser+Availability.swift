//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
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

@objc public enum Availability : Int, CaseIterable {
    case none, available, busy, away
}

extension Availability {
    
    public init(_ proto : ZMAvailability) {
        ///TODO: change ZMAvailabilityType to NS_CLOSED_ENUM
        switch proto.type {
        case .NONE:
            self = .none
        case .AVAILABLE:
            self = .available
        case .AWAY:
            self = .away
        case .BUSY:
            self = .busy
        @unknown default:
            self = .none
        }
    }

}

/// Describes how the user should be notified about a change.
public struct NotificationMethod: OptionSet {
    
    public let rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    /// Alert user by local notification
    public static let notification = NotificationMethod(rawValue: 1 << 0)
    /// Alert user by alert dialogue
    public static let alert = NotificationMethod(rawValue: 1 << 1)
    
    public static let all: NotificationMethod = [.notification, .alert]
    
}

extension ZMUser {

    /// A set of all users to receive a broadcast message.
    ///
    /// Broadcast messages are expensive for large teams. Therefore it is necessary broadcast to
    /// a limited subset of all users. Known team members are priortized first, followed by
    /// connected non team members.
    ///
    /// - Parameters:
    ///     - context: The context to search in.
    ///     - maxCount: The maximum number of recipients to return.

    public static func recipientsForBroadcast(in context: NSManagedObjectContext, maxCount: Int) -> Set<ZMUser> {
        var recipients = Set<ZMUser>()
        var remainingSlots = maxCount

        let sortByIdentifer: (ZMUser, ZMUser) -> Bool = {
            $0.remoteIdentifier.transportString() < $1.remoteIdentifier.transportString()
        }

        let teamMembers = knownTeamMembers(in: context)
            .sorted(by: sortByIdentifer)
            .prefix(remainingSlots)

        recipients.formUnion(teamMembers)
        remainingSlots -= recipients.count

        guard remainingSlots > 0 else { return recipients }

        let contacts = connections(in: context)
            .sorted(by: sortByIdentifer)
            .prefix(remainingSlots)

        recipients.formUnion(contacts)

        return recipients
    }

    /// The set of all users who both share the team and a conversation with the self user.

    public static func knownTeamMembers(in context: NSManagedObjectContext) -> Set<ZMUser> {
        let selfUser = ZMUser.selfUser(in: context)

        guard selfUser.hasTeam else { return Set() }

        let teamMembersInConversationWithSelfUser = selfUser.conversations.lazy
            .flatMap { $0.participantRoles }
            .map { $0.user }
            .filter { $0.isOnSameTeam(otherUser: selfUser) }

        return Set(teamMembersInConversationWithSelfUser)
    }

    /// The set of all users connected with the self user.

    public static func connections(in context: NSManagedObjectContext) -> Set<ZMUser> {
        let request = NSFetchRequest<ZMUser>(entityName: ZMUser.entityName())
        request.predicate = ZMUser.predicateForUsers(withConnectionStatuses: [ZMConnectionStatus.accepted.rawValue])

        return Set(context.fetchOrAssert(request: request))
    }

    @objc public var availability : Availability {
        get {
            self.willAccessValue(forKey: AvailabilityKey)
            let value = (self.primitiveValue(forKey: AvailabilityKey) as? NSNumber) ?? NSNumber(value: 0)
            self.didAccessValue(forKey: AvailabilityKey)
            
            return Availability(rawValue: value.intValue) ?? .none
        }
        
        set {
            guard isSelfUser else { return } // TODO move this setter to ZMEditableUser
            
            updateAvailability(newValue)
        }
    }
    
    public var shouldHideAvailability: Bool {
        guard let moc = managedObjectContext, !isSelfUser else { return false }
        
        let selfUserTeam = ZMUser.selfUser(in: moc).team
        
        guard let userTeamId = self.team?.remoteIdentifier, let selfUserTeamId = selfUserTeam?.remoteIdentifier else {
            return false
        }
        
        let userIsTeammate = userTeamId == selfUserTeamId
        let communicateStatus = selfUserTeam?.shouldCommunicateStatus ?? true
        
        return userIsTeammate && !communicateStatus
    }
    
    internal func updateAvailability(_ newValue : Availability) {
        self.willChangeValue(forKey: AvailabilityKey)
        self.setPrimitiveValue(NSNumber(value: newValue.rawValue), forKey: AvailabilityKey)
        self.didChangeValue(forKey: AvailabilityKey)
    }
    
    @objc public func updateAvailability(from genericMessage : ZMGenericMessage) {
        guard let availabilityProtobuffer = genericMessage.availability else { return }
        
        updateAvailability(Availability(availabilityProtobuffer))
    }
    
    private static let needsToNotifyAvailabilityBehaviourChangeKey = "needsToNotifyAvailabilityBehaviourChange"
    
    /// Returns an option set describing how we should notify the user about the change in behaviour for the availability feature
    public var needsToNotifyAvailabilityBehaviourChange: NotificationMethod {
        get {
            guard let rawValue = managedObjectContext?.persistentStoreMetadata(forKey: type(of: self).needsToNotifyAvailabilityBehaviourChangeKey) as? Int else { return [] }
            
            return NotificationMethod(rawValue: rawValue)
        }
        set {
            managedObjectContext?.setPersistentStoreMetadata(newValue.rawValue, key: type(of: self).needsToNotifyAvailabilityBehaviourChangeKey)
        }
    }
    
}
