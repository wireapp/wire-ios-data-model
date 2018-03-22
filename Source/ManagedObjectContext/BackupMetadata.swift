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

public struct BackupMetadata: Codable {
    public enum Platform: String, Codable {
        case iOS
    }
    
    public let platform: Platform
    public let appVersion, modelVersion: String
    public let creationTime: Date
    public let userIdentifier: UUID
    public let clientIdentifier: String
    
    public init(
        appVersion: String,
        modelVersion: String,
        creationTime: Date = .init(),
        userIdentifier: UUID,
        clientIdentifier: String
        ) {
        platform = .iOS
        self.appVersion = appVersion
        self.modelVersion = modelVersion
        self.creationTime = creationTime
        self.userIdentifier = userIdentifier
        self.clientIdentifier = clientIdentifier
    }
    
    public init?(
        client: UserClient,
        appVersionProvider: VersionProvider = Bundle.main,
        modelVersionProvider: VersionProvider = NSManagedObjectModel.loadModel()
        ) {
        guard let clientIdentifier = client.remoteIdentifier,
            let userIdentifier = client.user?.remoteIdentifier else { return nil }
        self.init(
            appVersion: appVersionProvider.version,
            modelVersion: modelVersionProvider.version,
            userIdentifier: userIdentifier,
            clientIdentifier: clientIdentifier
        )
    }
}

// MARK: - Equatable

extension BackupMetadata: Equatable {}

public func ==(lhs: BackupMetadata, rhs: BackupMetadata) -> Bool {
    return lhs.platform == rhs.platform
        && lhs.appVersion == rhs.appVersion
        && lhs.modelVersion == rhs.modelVersion
        && lhs.creationTime == rhs.creationTime
        && lhs.userIdentifier == rhs.userIdentifier
        && lhs.clientIdentifier == rhs.clientIdentifier
}

// MARK: - Serialization Helper

public extension BackupMetadata {
    
    func write(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: url)
    }
    
    init(url: URL) throws {
        let data = try Data(contentsOf: url)
        self = try JSONDecoder().decode(type(of: self), from: data)
    }
    
}

// MARK: - Verification

public extension BackupMetadata {
    
    enum VerificationError: Error {
        case backupFromNewerAppVersion
        case userMismatch
    }
    
    func verify(using user: ZMUser, appVersionProvider: VersionProvider = Bundle.main) -> VerificationError? {
        guard userIdentifier == user.remoteIdentifier else { return .userMismatch }
        let current = ZMVersion(versionString: appVersionProvider.version)
        let backup = ZMVersion(versionString: appVersion)

        // Backup has been created on a newer app version.
        guard current >= backup else { return .backupFromNewerAppVersion }
        return nil
    }
    
}

// MARK: - Version Helper

public protocol VersionProvider {
    var version: String { get }
}

extension NSManagedObjectModel: VersionProvider {
    public var version: String {
        return firstVersionIdentifier
    }
}

extension Bundle: VersionProvider {
    public var version: String {
        return infoDictionary!["CFBundleShortVersionString"] as! String
    }
}

// MARK: - ZMVersion Comparable Operators

extension ZMVersion: Comparable {}

public func ==(lhs: ZMVersion, rhs: ZMVersion) -> Bool {
    return lhs.compare(with: rhs) == .orderedSame
}

public func <(lhs: ZMVersion, rhs: ZMVersion) -> Bool {
    return lhs.compare(with: rhs) == .orderedAscending
}
