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
import WireSystem

protocol ObjectInSnapshot {
    static var observableKeys : Set<String> { get }
    var notificationName : Notification.Name { get }
}

extension ZMUser : ObjectInSnapshot {
    
    static public var observableKeys : Set<String> {
        return [
            #keyPath(ZMUser.name),
            #keyPath(ZMUser.accentColorValue),
            #keyPath(ZMUser.imageMediumData),
            #keyPath(ZMUser.imageSmallProfileData),
            #keyPath(ZMUser.emailAddress),
            #keyPath(ZMUser.phoneNumber),
            #keyPath(ZMUser.canBeConnected),
            #keyPath(ZMUser.isConnected),
            #keyPath(ZMUser.isPendingApprovalByOtherUser),
            #keyPath(ZMUser.isPendingApprovalBySelfUser),
            #keyPath(ZMUser.clients),
            #keyPath(ZMUser.handle),
            #keyPath(ZMUser.team)
        ]
    }

    public var notificationName : Notification.Name {
        return .UserChange
    }
}


@objc open class UserChangeInfo : ObjectChangeInfo {

    static let UserClientChangeInfoKey = "clientChanges"
    
    static func changeInfo(for user: ZMUser, changes: Changes) -> UserChangeInfo? {
        guard changes.changedKeys.count > 0 || changes.originalChanges.count > 0 else { return nil }

        var originalChanges = changes.originalChanges
        let clientChanges = originalChanges.removeValue(forKey: UserClientChangeInfoKey) as? [NSObject : [String : Any]]
        
        if let clientChanges = clientChanges {
            var userClientChangeInfos = [UserClientChangeInfo]()
            clientChanges.forEach {
                let changeInfo = UserClientChangeInfo(object: $0)
                changeInfo.changedKeys = Set($1.keys)
                userClientChangeInfos.append(changeInfo)
            }
            originalChanges[UserClientChangeInfoKey] = userClientChangeInfos as NSObject?
        }
        guard originalChanges.count > 0 || changes.changedKeys.count > 0 else { return nil }
        
        let changeInfo = UserChangeInfo(object: user)
        changeInfo.changeInfos = originalChanges
        changeInfo.changedKeys = changes.changedKeys
        return changeInfo
    }
    
    public required init(object: NSObject) {
        self.user = object as! ZMBareUser
        super.init(object: object)
    }

    open var nameChanged : Bool {
        return changedKeysContain(keys: #keyPath(ZMUser.name))
    }
    
    open var accentColorValueChanged : Bool {
        return changedKeysContain(keys: #keyPath(ZMUser.accentColorValue))
    }

    open var imageMediumDataChanged : Bool {
        return changedKeysContain(keys: #keyPath(ZMUser.imageMediumData))
    }

    open var imageSmallProfileDataChanged : Bool {
        return changedKeysContain(keys: #keyPath(ZMUser.imageSmallProfileData))
    }

    open var profileInformationChanged : Bool {
        return changedKeysContain(keys: #keyPath(ZMUser.emailAddress), #keyPath(ZMUser.phoneNumber))
    }

    open var connectionStateChanged : Bool {
        return changedKeysContain(keys: #keyPath(ZMUser.isConnected),
                                  #keyPath(ZMUser.canBeConnected),
                                  #keyPath(ZMUser.isPendingApprovalByOtherUser),
                                  #keyPath(ZMUser.isPendingApprovalBySelfUser))
    }

    open var trustLevelChanged : Bool {
        return userClientChangeInfos.count != 0
    }

    open var clientsChanged : Bool {
        return changedKeysContain(keys: #keyPath(ZMUser.clients))
    }

    public var handleChanged : Bool {
        return changedKeysContain(keys: #keyPath(ZMUser.handle))
    }

    public var teamsChanged : Bool {
        return changedKeys.contains(#keyPath(ZMUser.team))
    }

    open let user: ZMBareUser
    open var userClientChangeInfos : [UserClientChangeInfo] {
        return changeInfos[UserChangeInfo.UserClientChangeInfoKey] as? [UserClientChangeInfo] ?? []
    }
}



@objc public protocol ZMUserObserver : NSObjectProtocol {
    func userDidChange(_ changeInfo: UserChangeInfo)
}


extension UserChangeInfo {

    // MARK: Registering UserObservers
    /// Adds an observer for the user if one specified or to all ZMUsers is none is specified
    /// You must hold on to the token and use it to unregister
    @objc(addUserObserver:forUser:managedObjectContext:)
    public static func add(observer: ZMUserObserver, for user: ZMUser?, managedObjectContext: NSManagedObjectContext) -> NSObjectProtocol {
        return ManagedObjectObserverToken(name: .UserChange, managedObjectContext: managedObjectContext, object: user)
        { [weak observer] (note) in
            guard let `observer` = observer,
                let changeInfo = note.changeInfo as? UserChangeInfo
                else { return }
            
            observer.userDidChange(changeInfo)
        }
    }
    
    // MARK: Registering SearchUserObservers
    /// Adds an observer for the searchUser if one specified or to all ZMSearchUser is none is specified
    /// You must hold on to the token and use it to unregister
    @objc(addSearchUserObserver:forSearchUser:managedObjectContext:)
    public static func add(searchUserObserver observer: ZMUserObserver,
                           for user: ZMSearchUser?,
                           managedObjectContext: NSManagedObjectContext
                           ) -> NSObjectProtocol
    {
        return ManagedObjectObserverToken(name: .SearchUserChange, managedObjectContext: managedObjectContext, object: user)
        { [weak observer] (note) in
            guard let `observer` = observer,
                let changeInfo = note.changeInfo as? UserChangeInfo
                else { return }
            
            observer.userDidChange(changeInfo)
        }
    }
    
    // MARK: Registering ZMBareUser
    /// Adds an observer for the ZMUser or ZMSearchUser
    /// You must hold on to the token and use it to unregister
    @objc(addObserver:forBareUser:managedObjectContext:)
    public static func add(observer: ZMUserObserver,
                           forBareUser user: ZMBareUser,
                           managedObjectContext: NSManagedObjectContext) -> NSObjectProtocol?
    {
        if let user = user as? ZMSearchUser {
            return add(searchUserObserver: observer, for: user, managedObjectContext: managedObjectContext)
        }
        else if let user = user as? ZMUser {
            return add(observer: observer, for:user, managedObjectContext: managedObjectContext)
        }
        return nil
    }
}





