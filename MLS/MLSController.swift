//
// Wire
// Copyright (C) 2022 Wire Swiss GmbH
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

public final class MLSController {

    // MARK: - Properties

    private weak var context: NSManagedObjectContext?
    private let coreCrypto: CoreCryptoProtocol
    private let logger = ZMSLog(tag: "core-crypto")

    // MARK: - Life cycle

    init(
        context: NSManagedObjectContext,
        coreCrypto: CoreCryptoProtocol
    ) {
        self.context = context
        self.coreCrypto = coreCrypto

        do {
            try generatePublicKeysIfNeeded()
        } catch {
            logger.error("failed to generate public keys: \(String(describing: error))")
        }
    }

    // MARK: - Methods

    private func generatePublicKeysIfNeeded() throws {
        guard
            let context = context,
            let selfClient = ZMUser.selfUser(in: context).selfClient()
        else {
            return
        }

        var keys = selfClient.mlsPublicKeys

        if keys.ed25519 == nil {
            let keyBytes = try coreCrypto.wire_clientPublicKey()
            let keyData = Data(keyBytes)
            keys.ed25519 = keyData.base64EncodedString()
        }

        selfClient.mlsPublicKeys = keys
        context.saveOrRollback()
    }

}

// Uploading new key packages
extension MLSController {

    public func uploadKeyPackagesIfNeeded() {

        guard let context = context else { return }

        let user = ZMUser.selfUser(in: context)

        guard
            let clientId = user.selfClient()?.remoteIdentifier
        else {
            return
        }

        // TODO: Here goes the logic to determine how check to remaining key packages and re filling the new key packages after calculating number of welcome messages it receives by the client.

        /// For now temporarily we generate and upload at most 100 new key packages

        fetchMLSKeyPackagesCount(clientId: clientId) { count in

            if count < 100 {

                do {
                    let amount = UInt32(100 - count)
                    let keyPackages = try self.generateKeyPackages(amountRequested: amount)

                    try self.uploadKeyPackages(clientId: clientId, keyPackages: keyPackages, context: context.notificationContext)

                }
                catch {
                    self.logger.error("failed to generate new key packages: \(String(describing: error))")
                }
            }
        }
    }

    private func fetchMLSKeyPackagesCount(clientId: String, completion: @escaping (Int) -> Void) {

        /// Count MLS key packages
        CountSelfMLSKeyPackagesAction(clientID: clientId) { result in

            switch result {

            case .success(let count):
                completion(count)

            case .failure(let error):
                fatalError("failed to fetch MLS key packages count with error: \(error)")
            }
        }
        .send(in: context!.notificationContext)
    }

    private func generateKeyPackages(amountRequested: UInt32) throws -> [String] {

        var keyPackages = [[UInt8]]()

        do {
            /// Generate newly  key packages
            keyPackages = try coreCrypto.wire_clientKeypackages(amountRequested: amountRequested)

        } catch let error {
            logger.error("failed to generate new key packages: \(String(describing: error))")
            throw MLSKeyPackagesError.failedToGenerateKeyPackages
        }

        /// Check newly generated packages are non empty
        if keyPackages.isEmpty {
            logger.error("CoreCrypto generated empty key packages array")
            throw MLSKeyPackagesError.emptyKeyPackages
        }

        /// Convert received key packages into base64 encoded string
        return getBase64Encoded(keyPackages: keyPackages)

    }

    private func getBase64Encoded(keyPackages: [[UInt8]]) -> [String] {
        keyPackages.map { Data($0).base64EncodedString() }
    }

    private func uploadKeyPackages(clientId: String, keyPackages: [String], context: NotificationContext) throws {

        /// Upload  MLS key packages
        UploadSelfMLSKeyPackagesAction(clientID: clientId, keyPackages: keyPackages) { result in

            switch result {

            case .success(_):
                break

            case .failure(let error):
                self.logger.error("failed to generate new key packages: \(String(describing: error))")

            }
        }
        .send(in: context)
    }
}

enum MLSKeyPackagesError: Error {
    case failedToGenerateKeyPackages
    case emptyKeyPackages
}
