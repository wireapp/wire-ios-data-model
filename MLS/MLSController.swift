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
            let clientId = user.selfClient()?.remoteIdentifier,
            let mlsQualifiedClientId = MLSQualifiedClientID(user: user).mlsQualifiedClientId
        else {
            return
        }

        fetchMLSKeyPackagesCount(clientId: clientId) { count in

        // TODO: Here goes the logic to determine if new key packages needs to be uploaded and re filling the new key packages after calculating number of welcome messages it receives by the client.
        // For now we generate and upload new key packages if its less then 100
            if count <= 100 {
                /// Generate and upload new key packages
                self.generateAndUploadKeyPackages(clientId: mlsQualifiedClientId)
            }
        }
    }

    private func fetchMLSKeyPackagesCount(clientId: String, completion: @escaping (Int) -> Void) {

        /// Count MLS key packages
        CountSelfMLSKeyPackagesAction(clientID: clientId) { result in

            switch result {

            case .success(let count):
                print("a---> = \(count)")
                completion(count)

            case .failure(let error):
                fatalError("failed to fetch MLS key packages count with error: \(error)")
            }
        }
        .send(in: context!.notificationContext)
    }

    private func generateAndUploadKeyPackages(clientId: String, amountRequested: UInt32 = 100) {

        /// Generate new key packages
        do {
            let keyPackages = try coreCrypto.wire_clientKeypackages(amountRequested: amountRequested)

            if !keyPackages.isEmpty {
                fatalError("coreCrypto failed to generate client key packages")
            }

            /// Convert received key packages into base64 encoded string
            let keyPackagesEncodedStrings = convertKeyPackagesToBase64EncodedString(keyPackages: keyPackages)

            /// Upload  MLS key packages
            UploadSelfMLSKeyPackagesAction(clientID: clientId, keyPackages: keyPackagesEncodedStrings) { result in

                switch result {

                case .success(let value):
                    print(value)
                    print(value)
                    /// key packages uploaded successfully
                    break

                case .failure(let error):
                    fatalError("failed to upload MLS key packages with error: \(error)")
                }

            }
            .send(in: context!.notificationContext)

        } catch {
            logger.error("failed to generate new key packages: \(String(describing: error))")
        }
    }

    func convertKeyPackagesToBase64EncodedString(keyPackages: [[UInt8]]) -> [String] {
        keyPackages.map { Data($0).base64EncodedString() }
    }
}
