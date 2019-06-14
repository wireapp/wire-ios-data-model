//
// Wire
// Copyright (C) 2019 Wire Swiss GmbH
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

/**
 * A protocol for objects that provide the legal hold status for the self user.
 */

public protocol SelfLegalHoldSubject {

    /// The current legal hold status of the user.
    var legalHoldStatus: UserLegalHoldStatus { get }

    /// Whether the user needs to acknowledge the current legal hold status.
    var needsToAcknowledgeLegalHoldStatus: Bool { get }

    /// Call this method when the user received a legal hold request.
    func userDidReceiveLegalHoldRequest(_ request: LegalHoldRequest)

    /// Call this method when the user accepts a legal hold request.
    func userDidAcceptLegalHoldRequest(_ request: LegalHoldRequest)

    /// Call this method when the user acknowledges their legal hold status.
    func acknowledgeLegalHoldStatus()

}

/**
 * Describes the status of legal hold for the user.
 */

public enum UserLegalHoldStatus: Equatable {
    /// Legal hold is enabled for the user.
    case enabled

    /// A legal hold request is pending the user's approval.
    case pending(LegalHoldRequest)

    /// Legal hold is disabled for the user.
    case disabled
}

/**
 * Describes a request to enable legal hold, created from the update event.
 */

public struct LegalHoldRequest: Codable, Hashable {

    /**
     * Represents a prekey in the legal hold request.
     */

    public struct Prekey: Codable, Hashable {

        /// The ID of the key.
        public let id: Int

        /// The body of the key.
        public let key: Data

        public init(id: Int, key: Data) {
            self.id = id
            self.key = key
        }

    }

    /// The ID of the admin who sent the request.
    public let requesterIdentifier: UUID

    /// The ID of the user that should receive legal hold.
    public let targetUserIdentifier: UUID

    /// The ID of the legal hold client.
    public let clientIdentifier: String

    /// The last prekey for the legal hold client.
    public let lastPrekey: Prekey

    // MARK: Initialization

    public init(requesterIdentifier: UUID, targetUserIdentifier: UUID, clientIdentifier: String, lastPrekey: Prekey) {
        self.requesterIdentifier = requesterIdentifier
        self.targetUserIdentifier = targetUserIdentifier
        self.clientIdentifier = clientIdentifier
        self.lastPrekey = lastPrekey
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case requesterIdentifier = "requester"
        case targetUserIdentifier = "target_user"
        case clientIdentifier = "client_id"
        case lastPrekey = "last_prekey"
    }

    static func decode(from data: Data) -> LegalHoldRequest? {
        let decoder = JSONDecoder()
        decoder.dataDecodingStrategy = .base64
        return try? decoder.decode(LegalHoldRequest.self, from: data)
    }

    func encode() -> Data? {
        let encoder = JSONEncoder()
        encoder.dataEncodingStrategy = .base64
        return try? encoder.encode(self)
    }

}

extension ZMUserKeys {
    /// The key path to access the current legal hold request.
    static let legalHoldRequest = "legalHoldRequest"
}

extension ZMUser: SelfLegalHoldSubject {

    // MARK: - Legal Hold Status

    /// The keys that affect the legal hold status for the user.
    static func keysAffectingLegalHoldStatus() -> Set<String> {
        return [#keyPath(ZMUser.clients), ZMUserKeys.legalHoldRequest]
    }

    /// The current legal hold status for the user.
    public var legalHoldStatus: UserLegalHoldStatus {
        if clients.any(\.isLegalHoldDevice) {
            return .enabled
        } else if let legalHoldRequest = self.legalHoldRequest {
            return .pending(legalHoldRequest)
        } else {
            return .disabled
        }
    }

    // MARK: - Legal Hold Request

    @NSManaged private var primitiveLegalHoldRequest: Data?

    var legalHoldRequest: LegalHoldRequest? {
        get {
            willAccessValue(forKey: ZMUserKeys.legalHoldRequest)
            let value = primitiveLegalHoldRequest.flatMap(LegalHoldRequest.decode)
            didAccessValue(forKey: ZMUserKeys.legalHoldRequest)
            return value
        }
        set {
            willChangeValue(forKey: ZMUserKeys.legalHoldRequest)
            primitiveLegalHoldRequest = newValue.flatMap { $0.encode() }
            didChangeValue(forKey: ZMUserKeys.legalHoldRequest)
        }
    }

    /**
     * Call this method when the user accepted the legal hold request.
     * - parameter request: The request that the user received.
     */

    public func userDidAcceptLegalHoldRequest(_ request: LegalHoldRequest) {
        guard request == self.legalHoldRequest else {
            // The request must match the current request to avoid nil-ing it out by mistake
            return
        }

        addLegalHoldClient(from: request)
        legalHoldRequest = nil
        needsToAcknowledgeLegalHoldStatus = true
    }

    private func addLegalHoldClient(from request: LegalHoldRequest) {
        #warning("TODO: Create new UserClient from the request.")
    }

    /**
     * Call this method when the user received a legal hold request from their admin.
     * - parameter request: The request that the user received.
     */

    public func userDidReceiveLegalHoldRequest(_ request: LegalHoldRequest) {
        guard request.targetUserIdentifier == self.remoteIdentifier else {
            // Do not handle requests if the user ID doesn't match the self user ID
            return
        }

        legalHoldRequest = request
        needsToAcknowledgeLegalHoldStatus = true
    }

    // MARK: - Status Acknowledgement

    /// Whether the user needs to be notified about a legal hold status change.
    @NSManaged internal(set) public var needsToAcknowledgeLegalHoldStatus: Bool

    /**
     * Call this method when the user acknowledged the last legal hold status.
     */

    public func acknowledgeLegalHoldStatus() {
        needsToAcknowledgeLegalHoldStatus = false
    }

}
