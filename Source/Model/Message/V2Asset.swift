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
import MobileCoreServices


extension String {
    var isGIF: Bool {
        guard let UTIString = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, self as CFString, nil)?.takeRetainedValue() else { return false }
        return UTIString == kUTTypeGIF
    }
}


@objc public class V2Asset: NSObject, ZMImageMessageData {

    fileprivate let assetClientMessage: ZMAssetClientMessage
    fileprivate let moc: NSManagedObjectContext
    fileprivate let assetStorage: ImageAssetStorage

    public init?(with message: ZMAssetClientMessage) {
        guard message.version < 3 else { return nil }
        let storage = message.imageAssetStorage
        assetClientMessage = message
        assetStorage = storage
        moc = message.managedObjectContext!
    }

    public var imageMessageData: ZMImageMessageData? {
        guard nil != assetStorage.mediumGenericMessage || nil != assetStorage.previewGenericMessage else { return nil }
        return self
    }

    // MARK: - ZMImageMessageData

    public var mediumData: Data? {
        if assetStorage.mediumGenericMessage?.imageAssetData?.width > 0 {
            return assetClientMessage.imageAssetStorage.imageData(for: .medium, encrypted: false)
        }
        return nil
    }

    public var imageData: Data? {
        return mediumData ?? assetStorage.imageData(for: .original, encrypted: false)
    }

    public var imageDataIdentifier: String? {
        return imageDataIdentifier(for: assetStorage.mediumGenericMessage) ??
               imageDataIdentifier(for: assetStorage.previewGenericMessage) ??
               assetClientMessage.assetId?.uuidString ??
               imageData.map { String(format: "orig-%p", $0 as NSData) }
    }

    public var imagePreviewDataIdentifier: String? {
        return previewData != nil ? assetClientMessage.nonce.uuidString : nil
    }

    public var previewData: Data? {
        if assetStorage.previewGenericMessage?.imageAssetData?.width > 0 {
            // Image preview data
            return assetStorage.imageData(for: .original, encrypted: false)
        } else if nil != assetClientMessage.fileMessageData, assetClientMessage.hasDownloadedImage {
            // File preview data
            return imageData(for: .original) ?? imageData(for: .medium)
        }

        return nil
    }

    public var isAnimatedGIF: Bool {
        return assetStorage.mediumGenericMessage?.imageAssetData?.mimeType.isGIF ?? false
    }

    public var imageType: String? {
        return assetStorage.mediumGenericMessage?.imageAssetData?.mimeType ??
               assetStorage.previewGenericMessage?.imageAssetData?.mimeType
    }

    public var originalSize: CGSize {
        let genericMessage = assetStorage.mediumGenericMessage ?? assetStorage.previewGenericMessage
        guard let asset = genericMessage?.imageAssetData, asset.originalWidth > 0 else { return assetStorage.preprocessedSize }
        let size = CGSize(width: Int(asset.originalWidth), height: Int(asset.originalHeight))
        if size != .zero {
            return size
        }

        return assetClientMessage.preprocessedSize
    }

    // MARK: - Helper

    private func imageDataIdentifier(for message: ZMGenericMessage?) -> String? {
        guard let assetData = message?.imageAssetData else { return nil }
        return String(format: "%@-w%d-%@", assetClientMessage.nonce.transportString(), Int(assetData.width), NSNumber(value: assetClientMessage.hasDownloadedImage))

    }

    private func imageData(for format: ZMImageFormat) -> Data? {
        return moc.zm_imageAssetCache.assetData(assetClientMessage.nonce, format: format, encrypted: false)
    }

    fileprivate func hasImageData(for format: ZMImageFormat) -> Bool {
        return nil != imageData(for: format)
    }

}


extension V2Asset: AssetProxyType {

    public var hasDownloadedImage: Bool {
        guard assetClientMessage.imageMessageData != nil || assetClientMessage.fileMessageData != nil else { return false }
        return hasImageData(for: .medium) || hasImageData(for: .original)
    }

    public var hasDownloadedFile: Bool {
        guard assetClientMessage.fileMessageData != nil, let name = assetClientMessage.filename else { return false }
        return moc.zm_fileAssetCache.hasDataOnDisk(assetClientMessage.nonce, fileName: name, encrypted: false)
    }

    public var fileURL: URL? {
        guard let name = assetClientMessage.filename else { return nil }
        return moc.zm_fileAssetCache.accessAssetURL(assetClientMessage.nonce, fileName: name)
    }

    public func imageData(for format: ZMImageFormat, encrypted: Bool) -> Data? {
        if format != .original {
            let message = format == .medium ? assetStorage.mediumGenericMessage : assetStorage.previewGenericMessage
            guard message?.imageAssetData?.size > 0 else { return nil }
            if encrypted && message?.imageAssetData?.otrKey.count == 0 {
                return nil
            }
        }

        return moc.zm_imageAssetCache.assetData(assetClientMessage.nonce, format: format, encrypted: encrypted)
    }

    public func requestFileDownload() {
        guard assetClientMessage.fileMessageData != nil else { return }
        assetClientMessage.transferState = hasDownloadedFile ? .downloaded : .downloading
    }

    public func requestImageDownload() {
        guard !assetClientMessage.objectID.isTemporaryID, let moc = self.moc.zm_userInterface else { return }
        NotificationInContext(name: ZMAssetClientMessage.imageDownloadNotificationName, context: moc.notificationContext, object: assetClientMessage.objectID).post()
    }

    public var requiredImageFormats: NSOrderedSet {
        if nil != assetClientMessage.fileMessageData {
            return NSOrderedSet(object: ZMImageFormat.medium.rawValue)
        } else if nil != imageMessageData {
            return NSOrderedSet(array: [ZMImageFormat.medium.rawValue,  ZMImageFormat.preview.rawValue])
        } else {
            return NSOrderedSet()
        }
    }

    public func processAddedImage(format: ZMImageFormat, properties: ZMIImageProperties, keys: ZMImageAssetEncryptionKeys) {
        switch format {
        case .medium: processAddedMediumImage(properties: properties, keys: keys)
        case .preview: processAddedPreviewImage(properties: properties, keys: keys)
        default: fatal("Unexpected format in -processAddedImage: \(format)")
        }
    }

    func processAddedMediumImage(properties: ZMIImageProperties, keys: ZMImageAssetEncryptionKeys) {
        let messageID = assetClientMessage.nonce.transportString()

        let mediumMessage = ZMGenericMessage.genericMessage(
            mediumImageProperties: properties,
            processedImageProperties: properties,
            encryptionKeys: keys,
            nonce: messageID,
            format: .medium,
            expiresAfter: NSNumber(value: assetClientMessage.deletionTimeout)
        )
        assetClientMessage.add(mediumMessage)

        if var preview = assetStorage.genericMessage(for: .preview), preview.imageAssetData?.size > 0 { // if the preview is there, update it with the medium size
            preview = ZMGenericMessage.genericMessage(
                mediumImageProperties: imageProperties(from: mediumMessage),
                processedImageProperties: imageProperties(from: preview),
                encryptionKeys: encryptionKeys(from: preview),
                nonce: messageID,
                format: .preview,
                expiresAfter: NSNumber(value: assetClientMessage.deletionTimeout)
            )

            assetClientMessage.add(preview)
        }
    }

    func processAddedPreviewImage(properties: ZMIImageProperties, keys: ZMImageAssetEncryptionKeys) {
        let medium = assetStorage.genericMessage(for: .medium)
        let message = ZMGenericMessage.genericMessage(
            mediumImageProperties: medium.map(imageProperties),
            processedImageProperties: properties,
            encryptionKeys: keys,
            nonce: assetClientMessage.nonce.transportString(),
            format: .preview,
            expiresAfter: NSNumber(value: assetClientMessage.deletionTimeout)
        )
        assetClientMessage.add(message)

    }

    func imageProperties(from message: ZMGenericMessage) -> ZMIImageProperties {
        return ZMIImageProperties(
            size: CGSize(width: Int(message.imageAssetData?.width ?? 0), height: Int(message.imageAssetData?.height ?? 0)),
            length: UInt(message.imageAssetData?.size ?? 0),
            mimeType: message.imageAssetData?.mimeType ?? ""
        )
    }

    func encryptionKeys(from message: ZMGenericMessage) -> ZMImageAssetEncryptionKeys {
        let assetData = message.imageAssetData!
        if assetData.hasSha256() == true {
            return ZMImageAssetEncryptionKeys(otrKey: assetData.otrKey, sha256: assetData.sha256)
        } else {
            return ZMImageAssetEncryptionKeys(otrKey: assetData.otrKey, macKey: assetData.macKey, mac: assetData.mac)
        }
    }

}
