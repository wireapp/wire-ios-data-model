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
import WireSystem

extension Team : ObjectInSnapshot {
    
    static public var observableKeys : Set<String> {
        return [
            #keyPath(Team.name),
            #keyPath(Team.members),
        ]
    }
    
    public var notificationName : Notification.Name {
        return .TeamChange
    }
}


@objc public class TeamChangeInfo : ObjectChangeInfo {
    
    static func changeInfo(for team: Team, changes: Changes) -> TeamChangeInfo? {
        guard changes.changedKeys.count > 0 || changes.originalChanges.count > 0 else { return nil }
        let changeInfo = TeamChangeInfo(object: team)
        changeInfo.changeInfos = changes.originalChanges
        changeInfo.changedKeys = changes.changedKeys
        return changeInfo
    }
    
    public required init(object: NSObject) {
        self.team = object as! Team
        super.init(object: object)
    }
    
    public let team: TeamType
    
    public var membersChanged : Bool {
        return changedKeys.contains(#keyPath(Team.members))
    }

    public var nameChanged : Bool {
        return changedKeys.contains(#keyPath(Team.name))
    }

}



@objc public protocol TeamObserver : NSObjectProtocol {
    func teamDidChange(_ changeInfo: TeamChangeInfo)
}


extension TeamChangeInfo {
    
    // MARK: Registering TeamObservers
    /// Adds an observer for the team if one specified or to all Teams is none is specified
    /// You must hold on to the token and use it to unregister
    @objc(addTeamObserver:forTeam:managedObjectContext:)
    public static func add(observer: TeamObserver, for team: Team?, managedObjectContext: NSManagedObjectContext) -> NSObjectProtocol {
        return ManagedObjectObserverToken(name: .TeamChange, managedObjectContext: managedObjectContext, object: team)
        { [weak observer] (note) in
            guard let `observer` = observer,
                let changeInfo = note.changeInfo as? TeamChangeInfo
                else { return }
            
            observer.teamDidChange(changeInfo)
        }
    }    
}





