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
        guard let UTIString = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, self as CFString, nil)?.takeUnretainedValue() else { return false }
        return UTIString == kUTTypeGIF
    }

}


@objc public class V2ImageAsset: NSObject, ZMImageMessageData {

    fileprivate let assetClientMessage: ZMAssetClientMessage
    fileprivate let moc: NSManagedObjectContext
    private let assetStorage: ZMImageAssetStorage

    public init?(with message: ZMAssetClientMessage) {
        guard message.version < 3, let storage = message.imageAssetStorage else { return nil }
        assetClientMessage = message
        assetStorage = storage
        moc = message.managedObjectContext!
    }

    public var mediumData: Data? {
        if assetStorage.mediumGenericMessage?.imageAssetData?.width > 0 {
            return assetClientMessage.imageAssetStorage?.imageData(for: .medium, encrypted: false)
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
        } else if let fileMessage = assetClientMessage.fileMessageData, assetClientMessage.hasDownloadedImage, !fileMessage.isImage() {
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
        guard let asset = genericMessage?.imageAssetData, asset.originalWidth > 0 else { return assetStorage.preprocessedSize() }
        return CGSize(width: Int(asset.originalWidth), height: Int(asset.originalHeight))
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


extension V2ImageAsset: AssetProxyType {

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

}
