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


public class Member: ZMManagedObject {

    @NSManaged public var team: Team?
    @NSManaged public var user: ZMUser?
    @NSManaged public var remoteIdentifier_data : Data?
    @NSManaged private var permissionsRawValue: Int64

    public var permissions: Permissions {
        get { return Permissions(rawValue: permissionsRawValue) }
        set { permissionsRawValue = newValue.rawValue }
    }

    public override static func entityName() -> String {
        return "Member"
    }

    public override static func isTrackingLocalModifications() -> Bool {
        return false
    }

    public override static func defaultSortDescriptors() -> [NSSortDescriptor] {
        return []
    }
    
    public var remoteIdentifier: UUID? {
        get { return remoteIdentifier_data.flatMap { NSUUID(uuidBytes: $0.withUnsafeBytes(UnsafePointer<UInt8>.init)) } as UUID? }
        set { remoteIdentifier_data = (newValue as NSUUID?)?.data() }
    }

    @objc(getOrCreateMemberForUser:inTeam:context:)
    public static func getOrCreateMember(for user: ZMUser, in team: Team, context: NSManagedObjectContext) -> Member {
        if let existing = user.membership {
            return existing
        }
        else if let userId = user.remoteIdentifier, let existing = Member.fetch(withRemoteIdentifier: userId, in: context) {
            return existing
        }

        let member = insertNewObject(in: context)
        member.team = team
        member.user = user
        member.remoteIdentifier = user.remoteIdentifier
        return member
    }

}


// MARK: - Transport


fileprivate enum ResponseKey: String {
    case user, permissions

    enum Permissions: String {
        case `self`, copy
    }
}


extension Member {

    @discardableResult
    public static func createOrUpdate(with payload: [String: Any], in team: Team, context: NSManagedObjectContext) -> Member? {
        guard let id = (payload[ResponseKey.user.rawValue] as? String).flatMap(UUID.init),
            let user = ZMUser(remoteID: id, createIfNeeded: true, in: context) else { return nil }

        let member = getOrCreateMember(for: user, in: team, context: context)
        member.updatePermissions(with: payload)
        return member
    }

    public func updatePermissions(with payload: [String: Any]) {
        guard let userID = (payload[ResponseKey.user.rawValue] as? String).flatMap(UUID.init) else { return }
        precondition(remoteIdentifier == userID, "Trying to update member with non-matching payload: \(payload), \(self)")
        guard let permissionsPayload = payload[ResponseKey.permissions.rawValue] as? [String: Any] else { return }
        guard let selfPermissions = permissionsPayload[ResponseKey.Permissions.`self`.rawValue] as? NSNumber else { return }
        permissions = Permissions(rawValue: selfPermissions.int64Value)
    }

}
