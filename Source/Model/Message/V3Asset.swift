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


private let zmLog = ZMSLog(tag: "AssetV3")


/// This protocol is used to hide the implementation of the different
/// asset types (v2 image & file vs. v3 file) from ZMAssetClientMessage.
/// It only includes methods in which these two versions differentiate.
@objc public protocol AssetProxyType {

    var hasDownloadedImage: Bool { get }
    var hasDownloadedFile: Bool { get }
    var imageMessageData: ZMImageMessageData? { get }
    var fileURL: URL? { get }

    var previewData: Data? { get }
    var imagePreviewDataIdentifier: String? { get }

    @objc(imageDataForFormat:encrypted:)
    func imageData(for: ZMImageFormat, encrypted: Bool) -> Data?

    func requestFileDownload()
    func requestImageDownload()

    // Image preprocessing
    var requiredImageFormats: NSOrderedSet { get }
    func processAddedImage(format: ZMImageFormat, properties: ZMIImageProperties, keys: ZMImageAssetEncryptionKeys)
}


@objc public class V3Asset: NSObject, ZMImageMessageData {

    fileprivate let assetClientMessage: ZMAssetClientMessage
    private let assetStorage: ImageAssetStorage
    fileprivate let moc: NSManagedObjectContext

    fileprivate var isImage: Bool {
        return assetClientMessage.genericAssetMessage?.v3_isImage ?? false
    }

    public init?(with message: ZMAssetClientMessage) {
        guard message.version == 3 else { return nil }
        assetClientMessage = message
        assetStorage = message.imageAssetStorage
        moc = message.managedObjectContext!
    }

    public var imageMessageData: ZMImageMessageData? {
        guard isImage else { return nil }
        return self
    }

    public var mediumData: Data? {
        guard nil != assetClientMessage.fileMessageData, isImage else { return nil }
        return imageData(for: .medium, encrypted: false)
    }

    public var imageData: Data? {
        guard nil != assetClientMessage.fileMessageData, isImage else { return nil }
        return mediumData ?? imageData(for: .original, encrypted: false)
    }

    public var imageDataIdentifier: String? {
        if nil != assetClientMessage.fileMessageData, isImage, let image = assetClientMessage.genericAssetMessage?.assetData?.original.image {
            return "\(assetClientMessage.nonce.transportString())-\(image.width)x\(image.height)"
        }

        return imageData.map { String(format: "orig-%p", $0 as NSData) }
    }

    public var imagePreviewDataIdentifier: String? {
        return previewData != nil ? assetClientMessage.genericAssetMessage?.previewAssetId : nil
    }

    public var previewData: Data? {
        guard nil != assetClientMessage.fileMessageData, !isImage, hasDownloadedImage else { return nil }
        return imageData(for: .medium, encrypted: false) ?? imageData(for: .original, encrypted: false)
    }

    public var isAnimatedGIF: Bool {
        return assetClientMessage.genericAssetMessage?.assetData?.original.mimeType.isGIF ?? false
    }

    public var imageType: String? {
        guard isImage else { return nil }
        return assetClientMessage.genericAssetMessage?.assetData?.original.mimeType
    }

    public var originalSize: CGSize {
        guard nil != assetClientMessage.fileMessageData, isImage else { return .zero }
        guard let asset = assetClientMessage.genericAssetMessage?.assetData else { return .zero }
        guard asset.original.hasImage(), asset.original.image.width > 0 else { return assetClientMessage.preprocessedSize }
        let size = CGSize(width: Int(asset.original.image.width), height: Int(asset.original.image.height))
        if size != .zero {
            return size
        }

        return assetClientMessage.preprocessedSize
    }

}

extension V3Asset: AssetProxyType {

    public var hasDownloadedImage: Bool {
        return nil != imageData(for: .medium, encrypted: false)
            || nil != imageData(for: .original, encrypted: false)
    }

    public var hasDownloadedFile: Bool {
        guard !isImage else { return false }
        return hasFile(for: assetClientMessage.genericAssetMessage?.v3_fileCacheKey)
    }

    public var fileURL: URL? {
        guard let key = assetClientMessage.genericAssetMessage?.v3_fileCacheKey else { return nil }
        return moc.zm_fileAssetCache.accessAssetURL(assetClientMessage.nonce, fileName: key)
    }

    public func imageData(for format: ZMImageFormat, encrypted: Bool) -> Data? {
        guard assetClientMessage.fileMessageData != nil else { return nil }
        return moc.zm_imageAssetCache.assetData(assetClientMessage.nonce, format: format, encrypted: encrypted)
    }

    public func requestFileDownload() {
        guard assetClientMessage.fileMessageData != nil else { return }
        if (isImage && !hasDownloadedImage) || (!isImage && !hasDownloadedFile) {
            assetClientMessage.transferState = .downloading
        }
    }

    public func requestImageDownload() {
        if isImage {
            requestFileDownload()
        } else if assetClientMessage.genericAssetMessage?.assetData?.hasPreview() == true {
            guard !assetClientMessage.objectID.isTemporaryID else { return }
            NotificationInContext(name: ZMAssetClientMessage.imageDownloadNotificationName,
                                  context: self.moc.notificationContext,
                                  object: assetClientMessage.objectID
                                ).post()
        } else {
            return zmLog.info("Called \(#function) on a v3 asset that doesn't represent an image or has a preview")
        }
    }

    public var requiredImageFormats: NSOrderedSet {
        return NSOrderedSet(object: ZMImageFormat.medium.rawValue)
    }

    public func processAddedImage(format: ZMImageFormat, properties: ZMIImageProperties, keys: ZMImageAssetEncryptionKeys) {
        guard format == .medium, let sha256 = keys.sha256 else { return zmLog.error("Tried to process non-medium v3 image for \(assetClientMessage)") }
        let messageID = assetClientMessage.nonce.transportString()

        let original = ZMGenericMessage.genericMessage(
            withImageSize: properties.size,
            mimeType: properties.mimeType,
            size: UInt64(properties.length),
            nonce: messageID,
            expiresAfter: NSNumber(value: assetClientMessage.deletionTimeout)
        )
        let uploaded = ZMGenericMessage.genericMessage(
            withUploadedOTRKey: keys.otrKey,
            sha256: sha256,
            messageID: messageID,
            expiresAfter: NSNumber(value: assetClientMessage.deletionTimeout)
        )

        assetClientMessage.add(original)
        assetClientMessage.add(uploaded)
    }

    // MARK: - Helper

    private func hasFile(for key: String?) -> Bool {
        guard let cacheKey = key else { return false }
        return moc.zm_fileAssetCache.hasDataOnDisk(assetClientMessage.nonce, fileName: cacheKey, encrypted: false)
    }
}
