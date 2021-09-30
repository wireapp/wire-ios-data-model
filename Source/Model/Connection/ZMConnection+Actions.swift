//
//  ZMConnection+Actions.swift
//  WireDataModel
//
//  Created by Jacob Persson on 24.09.21.
//  Copyright © 2021 Wire Swiss GmbH. All rights reserved.
//

import Foundation

public enum ConnectToUserError: Error {
    case unknown
    case noIdentity
    case connectionLimitReached
    case missingLegalholdConsent
    case internalInconsistency
}

public enum UpdateConnectionError: Error {
    case unknown
    case noIdentity
    case notConnected
    case connectionLimitReached
    case missingLegalholdConsent
    case internalInconsistency
}

public struct ConnectToUserAction: EntityAction {

    public typealias Result = Void
    public typealias Failure = ConnectToUserError

    public var resultHandler: ResultHandler?
    public let userID: UUID
    public let domain: String?

    public init(userID: UUID, domain: String?) {
        self.userID = userID
        self.domain = domain
    }
}

public struct UpdateConnectionAction: EntityAction {

    public typealias Result = Void
    public typealias Failure = UpdateConnectionError

    public var resultHandler: ResultHandler?
    public let connectionID: NSManagedObjectID
    public let newStatus: ZMConnectionStatus

    public init(connection: ZMConnection, newStatus: ZMConnectionStatus) {
        self.connectionID = connection.objectID
        self.newStatus = newStatus
    }
}

public extension ZMUser {

    func sendConnectionRequest(to user: UserType, completion: @escaping ConnectToUserAction.ResultHandler) {
        guard
            let userID = user.remoteIdentifier,
            let context = managedObjectContext
        else {
            return completion(.failure(.internalInconsistency))
        }

        var action = ConnectToUserAction(userID: userID, domain: user.domain)
        action.onResult(resultHandler: completion)
        action.send(in: context.notificationContext)
    }

}

public extension ZMConnection {

    func updateStatus(_ status: ZMConnectionStatus, completion: @escaping UpdateConnectionAction.ResultHandler) {
        guard let context = managedObjectContext else {
            return completion(.failure(.internalInconsistency))
        }

        var action = UpdateConnectionAction(connection: self, newStatus: status)
        action.onResult(resultHandler: completion)
        action.send(in: context.notificationContext)
    }
    
}
