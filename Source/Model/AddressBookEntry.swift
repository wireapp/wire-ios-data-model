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

import Foundation
import Contacts
import AddressBook

public class AddressBookEntry : ZMManagedObject {
    
    enum Fields : String {
        case localIdentifier = "localIdentifier"
        case user = "user"
        case cachedName = "cachedName"
    }
    
    @NSManaged public var localIdentifier : String?
    @NSManaged public var user : ZMUser?
    @NSManaged public var cachedName : String?
    
    public override func keysTrackedForLocalModifications() -> Set<String> {
        return []
    }
    
    public override static func entityName() -> String {
        return "AddressBookEntry"
    }
    
    public override static func sortKey() -> String? {
        return Fields.localIdentifier.rawValue
    }
}

extension AddressBookEntry {
    
    @available(iOSApplicationExtension 9.0, *)
    @objc(createFromContact:managedObjectContext:user:)
    static public func create(from contact: CNContact, managedObjectContext: NSManagedObjectContext, user: ZMUser? = nil) -> AddressBookEntry {
        let entry = AddressBookEntry.insertNewObject(in: managedObjectContext)
        entry.localIdentifier = contact.identifier
        entry.cachedName = CNContactFormatter.string(from: contact, style: .fullName)
        entry.user = user
        return entry
    }
}

