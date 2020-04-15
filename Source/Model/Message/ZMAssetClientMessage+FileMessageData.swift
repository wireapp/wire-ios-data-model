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

// MARK: - ZMFileMessageData
@objc public protocol ZMFileMessageData: NSObjectProtocol {
    
    /// MIME type of the file being transfered (implied from file extension)
    var mimeType: String? { get }
    
    /// Original file size
    var size: UInt64 { get }
    
    /// File transfer state
    var transferState: AssetTransferState { get }
    
    /// Download state (.downloaded, downloading, ...)
    var downloadState: AssetDownloadState { get }
    
    /// File name as was sent
    var filename: String? { get }
    
    /// Currend download / upload progress
    var progress: Float { get set }
    
    /// The file location on the filesystem
    var fileURL: URL? { get }
    
    /// The asset ID of the thumbnail, if any
    var thumbnailAssetID: String? { get set }
    
    /// Duration of the media in milliseconds
    var durationMilliseconds: UInt64 { get }
    
    /// Dimensions of the video
    var videoDimensions: CGSize { get }
    
    /// File thumbnail preview image
    var previewData: Data? { get }
    
    /// This can be used as a cache key for @c -previewData
    var imagePreviewDataIdentifier: String? { get }
    
    /// Normalized loudness of audio data
    var normalizedLoudness: [Float]? { get }
    
    /// Marks file to be downloaded
    func requestFileDownload()
    
    /// Marks file image preview to be downloaded
    func requestImagePreviewDownload()
    
    /// Video-message related properties
    /// if MIME type is indicating the video content
    var isVideo: Bool { get }

    /// if MIME type is indicating the PKPass content
    var isPass: Bool { get }

    /// Cancels the pending download or upload of the file.
    /// Deisgned to be used in case the file transfer on sender side is
    /// in `ZMFileMessageStateUploading` state, or in `ZMFileMessageStateDownloading`
    /// state on receiver side.
    func cancelTransfer()
    
    /// Audio-message related properties
    /// if MIME type is indicating the audio content
    var isAudio: Bool { get }
    
    /// Whether the file message represents a v3 image
    var v3_isImage: Bool { get }
    
    /// Fetch preview image data from disk
    func fetchImagePreviewData(queue: DispatchQueue, completionHandler: @escaping (_ imageData: Data?) -> Void)
    
}


extension ZMAssetClientMessage: ZMFileMessageData {
    
    /// Notification name for canceled file upload
    public static let didCancelFileDownloadNotificationName = Notification.Name(rawValue: "ZMAssetClientMessageDidCancelFileDownloadNotification")

    
    // MIME type of the file being transfered (implied from file extension)
    public var mimeType: String? {
        
        guard let asset = self.genericAssetMessage?.assetData else { return nil }
        if asset.original.hasMimeType() {
            return asset.original.mimeType
        }
        
        if asset.preview.hasMimeType() {
            return asset.preview.mimeType
        }
        
        if let assetData = self.previewGenericMessage?.imageAssetData,
            assetData.hasMimeType
        {
            return assetData.mimeType
        }
        
        if let assetData = self.mediumGenericMessage?.imageAssetData,
            assetData.hasMimeType
        {
            return assetData.mimeType
        }
        
        return nil
    }

    /// If the asset is a rich file type, this returns its type.
    public var richAssetType: RichAssetFileType? {
        return mimeType.flatMap(RichAssetFileType.init)
    }
    
    public var fileURL: URL? {
        guard let assetURL = asset?.fileURL,
            let filename = filename,
            let temporaryDirectoryURL = temporaryDirectoryURL else { return nil }
        
        var temporaryFileURL = temporaryDirectoryURL.appendingPathComponent(filename)
        
        if let fileExtension = fileExtension,
            richAssetType == .audio,
            temporaryFileURL.pathExtension != fileExtension {
            temporaryFileURL.appendPathExtension(fileExtension)
        }
        
        if FileManager.default.fileExists(atPath: temporaryFileURL.path) {
            return temporaryFileURL
        }
        
        do {
            try FileManager.default.createDirectory(at: temporaryFileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            try FileManager.default.linkItem(at: assetURL, to: temporaryFileURL)
        } catch {
            return nil
        }
        
        return temporaryFileURL
    }
    
    private var fileExtension: String? {
        guard let mime = mimeType,
            let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, mime as CFString, nil),
            let extensionUTI = UTTypeCopyPreferredTagWithClass(uti.takeRetainedValue(), kUTTagClassFilenameExtension) else {
                return nil
        }
        return String(extensionUTI.takeRetainedValue())
    }
    
    public var temporaryDirectoryURL: URL? {
        guard let cacheKey = FileAssetCache.cacheKeyForAsset(self) else { return nil }
        var temporaryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        temporaryURL.appendPathComponent(cacheKey)
        return temporaryURL
    }
    
    public var previewData: Data? {
        return self.asset?.previewData
    }
    
    public func fetchImagePreviewData(queue: DispatchQueue, completionHandler: @escaping (Data?) -> Void) {
        guard nil != self.fileMessageData, !isImage else { return completionHandler(nil) }
        
        self.asset?.fetchImageData(with: queue, completionHandler: completionHandler)
    }
    
    /// File name as was sent or `nil` in case of an image asset
    public var filename: String? {
        return self.genericAssetMessage?.assetData?.original.name.removingExtremeCombiningCharacters
    }
    
    public var thumbnailAssetID: String? {
        
        get {
            guard self.fileMessageData != nil else { return nil }
            guard let assetData = self.genericMessage(dataType: .thumbnail)?.assetData,
                assetData.preview.remote.hasAssetID,
                !assetData.preview.remote.assetID.isEmpty
                else { return nil }
            return assetData.preview.remote.assetID
        }
        
        set {
            
            // This method has to inject this value in the currently existing thumbnail message.
            // Unfortunately it is immutable. So I need to create a copy, modify and then replace.
            guard let thumbnailMessage = self.genericMessage(dataType: .thumbnail) else { return }
            var message = GenericMessage()
            guard var assetData = thumbnailMessage.assetData,
                assetData.hasPreview,
                assetData.preview.hasRemote else { return }
            assetData.preview.remote.assetID = newValue ?? ""
            
            try? message.merge(serializedData: thumbnailMessage.serializedData())
            message.update(asset: assetData)
            self.replaceGenericMessageForThumbnail(with: message)
        }
    }
    
    private func replaceGenericMessageForThumbnail(with genericMessage: GenericMessage) {
        self.cachedUnderlyingAssetMessage = nil
        
        self.dataSet
            .map { $0 as! ZMGenericMessageData }
            .forEach { data in
                let dataMessage = data.underlyingMessage
                if let assetData = dataMessage?.assetData,
                    assetData.hasPreview {
                    do {
                        let genericMessageData = try genericMessage.serializedData()
                        data.data =  genericMessageData
                    } catch {}
                }
        }
    }
    
    public var imagePreviewDataIdentifier: String? {
        return self.asset?.imagePreviewDataIdentifier
    }

    public var isPass: Bool {
        return richAssetType == .walletPass
    }

    public var isVideo: Bool {
        return richAssetType == .video
    }
    
    public var isAudio: Bool {
        return richAssetType == .audio
    }
    
    public var v3_isImage: Bool {
        return self.genericAssetMessage?.v3_isImage ?? false
    }
    
    public var videoDimensions: CGSize {
        guard let assetData = self.genericAssetMessage?.assetData else { return CGSize.zero }
        let w = assetData.original.video.width
        let h = assetData.original.video.height
        return CGSize(width: Int(w), height: Int(h))
    }

    public var durationMilliseconds: UInt64 {
        guard let assetData = self.genericAssetMessage?.assetData else { return 0 }
        if self.isVideo {
            return assetData.original.video.durationInMillis
        }
        if self.isAudio {
            return assetData.original.audio.durationInMillis
        }
        return 0
    }
    
    public var normalizedLoudness: [Float]? {
        guard self.isAudio,
            let assetData = self.genericAssetMessage?.assetData,
            assetData.original.audio.hasNormalizedLoudness() else
        {
            return nil
        }
        return assetData.original.normalizedLoudnessLevels
    }
    
    public func requestFileDownload() {
        asset?.requestFileDownload()
    }
    
    public func requestImagePreviewDownload() {
        asset?.requestPreviewDownload()
    }
}

extension ZMAssetClientMessage {
    
    public func cancelTransfer() {
        
        switch transferState {
        case .uploading:
            expire()
            updateTransferState(.uploadingCancelled, synchronize: false)
            progress = 0
        case .uploaded:
            self.progress = 0
            self.obtainPermanentObjectID()
            self.managedObjectContext?.saveOrRollback()
            NotificationInContext(
                name: ZMAssetClientMessage.didCancelFileDownloadNotificationName,
                context: self.managedObjectContext!.notificationContext,
                object: self.objectID,
                userInfo: [:]
                ).post()
        default:
            break
        }
    }

    /// Turn temporary object ID into permanet
    private func obtainPermanentObjectID() {
        if self.objectID.isTemporaryID {
            try! self.managedObjectContext!.obtainPermanentIDs(for: [self])
        }
    }
    
}
