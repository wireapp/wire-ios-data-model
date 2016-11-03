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


@objc public protocol AssetProxyType {
    var hasDownloadedImage: Bool { get }
    var hasDownloadedFile: Bool { get }

    var fileURL: URL? { get }
}


@objc public class V3ImageAsset: NSObject, ZMImageMessageData {

    fileprivate let assetClientMessage: ZMAssetClientMessage
    private let assetStorage: ZMImageAssetStorage
    fileprivate let moc: NSManagedObjectContext

    fileprivate var isImage: Bool {
        return assetClientMessage.genericAssetMessage?.v3_isImage ?? false
    }

    public init?(with message: ZMAssetClientMessage) {
        guard message.version == 3, let storage = message.imageAssetStorage else { return nil }
        assetClientMessage = message
        assetStorage = storage
        moc = message.managedObjectContext!
    }

    public var mediumData: Data? {
        guard nil != assetClientMessage.fileMessageData, isImage else { return nil }
        guard let cacheKey = assetClientMessage.genericAssetMessage?.v3_uploadedAssetId else { return nil }
        return moc.zm_fileAssetCache.assetData(assetClientMessage.nonce, fileName: cacheKey, encrypted: false)
    }

    public var imageData: Data? {
        guard nil != assetClientMessage.fileMessageData, isImage else { return nil }
        return mediumData ?? moc.zm_fileAssetCache.assetData(assetClientMessage.nonce, fileName: "", encrypted: false)
    }

    public var imageDataIdentifier: String? {
        if nil != assetClientMessage.fileMessageData, isImage {
            return assetClientMessage.genericAssetMessage?.v3_uploadedAssetId
        }

        return imageData.map { String(format: "orig-%p", $0 as NSData) }
    }

    public var imagePreviewDataIdentifier: String? {
        return previewData != nil ? assetClientMessage.genericAssetMessage?.previewAssetId : nil
    }

    public var previewData: Data? {
        guard nil != assetClientMessage.fileMessageData, isImage, assetClientMessage.hasDownloadedImage else { return nil }
        guard let cacheKey = assetClientMessage.genericAssetMessage?.previewAssetId else { return nil }
        return moc.zm_fileAssetCache.assetData(assetClientMessage.nonce, fileName: cacheKey, encrypted: false)
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
        guard asset.original.hasImage(), asset.original.image.width > 0 else { return .zero }
        return CGSize(width: Int(asset.original.image.width), height: Int(asset.original.image.height))
    }

}

extension V3ImageAsset: AssetProxyType {

    public var hasDownloadedImage: Bool {
        return hasFile(for: assetClientMessage.genericAssetMessage?.v3_imageCacheKey)
    }

    public var hasDownloadedFile: Bool {
        let isImageAndDownloaded = isImage && hasDownloadedImage
        return isImageAndDownloaded || hasFile(for: assetClientMessage.genericAssetMessage?.v3_uploadedAssetId)
    }

    public var fileURL: URL? {
        guard let key = assetClientMessage.genericAssetMessage?.v3_uploadedAssetId else { return nil }
        return moc.zm_fileAssetCache.accessAssetURL(assetClientMessage.nonce, fileName: key)
    }

    // MARK: - Helper

    private func hasFile(for key: String?) -> Bool {
        guard let cacheKey = key else { return false }
        return moc.zm_fileAssetCache.hasDataOnDisk(assetClientMessage.nonce, fileName: cacheKey, encrypted: false)
    }
}
