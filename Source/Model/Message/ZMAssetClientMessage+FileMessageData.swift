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

// MARK: - ZMFileMessageData
@objc public protocol ZMFileMessageData: NSObjectProtocol {
    
    /// MIME type of the file being transfered (implied from file extension)
    var mimeType: String? { get }
    
    /// Original file size
    var size: UInt64 { get }
    
    /// File transfer state
    var transferState: ZMFileTransferState { get set }
    
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
    
    /// Document preview frame
    var previewData: Data? { get }
    
    /// This can be used as a cache key for @c -previewData
    var imagePreviewDataIdentifier: String? { get }
    
    /// Normalized loudness of audio data
    var normalizedLoudness: [Float]? { get }
    
    /// Marks file to be downloaded
    func requestFileDownload()
    
    /// Video-message related properties
    /// if MIME type is indicating the video content
    var isVideo: Bool { get }
    
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
            assetData.hasMimeType()
        {
            return assetData.mimeType
        }
        
        if let assetData = self.mediumGenericMessage?.imageAssetData,
            assetData.hasMimeType()
        {
            return assetData.mimeType
        }
        
        return nil
    }
    
    public var fileURL: URL? {
        return self.asset?.fileURL;
    }
    
    public var previewData: Data? {
        return self.asset?.previewData
    }
    
    /// File name as was sent or `nil` in case of an image asset
    public var filename: String? {
        return self.genericAssetMessage?.assetData?.original.name.removingExtremeCombiningCharacters
    }
    
    public var thumbnailAssetID: String? {
        
        get {
            guard self.fileMessageData != nil else { return nil }
            guard let assetData = self.genericMessage(dataType: .thumbnail)?.assetData,
                assetData.preview.remote.hasAssetId(),
                let assetId = assetData.preview.remote.assetId,
                !assetId.isEmpty
            else { return nil }
            return assetId
        }
        
        set {
                
            // This method has to inject this value in the currently existing thumbnail message.
            // Unfortunately it is immutable. So I need to create a copy, modify and then replace.
            guard self.fileMessageData != nil else { return }
            
            guard let thumbnailMessage = self.genericMessage(dataType: .thumbnail) else { return }
                
            
            let remoteBuilder = ZMAssetRemoteDataBuilder()
            let previewBuilder = ZMAssetPreviewBuilder()
            let assetBuilder = ZMAssetBuilder()
            let messageBuilder = ZMGenericMessageBuilder()

            if let assetData = thumbnailMessage.assetData {
                if assetData.hasPreview() {
                    if assetData.preview.hasRemote() {
                        remoteBuilder.merge(from:assetData.preview.remote)
                    }
                    previewBuilder.merge(from:assetData.preview)
                }
                assetBuilder.merge(from: assetData)
            }
            messageBuilder.merge(from: thumbnailMessage)
            
            remoteBuilder.setAssetId(newValue)
            previewBuilder.setRemote(remoteBuilder.build())
            assetBuilder.setPreview(previewBuilder.build())
            let asset = assetBuilder.build()!
            
            if self.isEphemeral {
                let ephemeral = ZMEphemeral.ephemeral(pbMessage: asset, expiresAfter: self.deletionTimeout as NSNumber)
                messageBuilder.setEphemeral(ephemeral)
            } else {
                messageBuilder.setAsset(asset)
            }
            
            self.replaceGenericMessageForThumbnail(with: messageBuilder.build())
        }
    }
    
    private func replaceGenericMessageForThumbnail(with genericMessage: ZMGenericMessage) {
        self.cachedGenericAssetMessage = nil
        
        self.dataSet
            .map { $0 as! ZMGenericMessageData }
            .forEach { data in
                let dataMessage = data.genericMessage
                if let assetData = dataMessage?.assetData,
                    assetData.hasPreview() && !assetData.hasUploaded() {
                    data.data = genericMessage.data()
                }
        }
    }
    
    public var imagePreviewDataIdentifier: String? {
        return self.asset?.imagePreviewDataIdentifier
    }

    public var isVideo: Bool {
        return self.mimeType?.isVideoMimeType() ?? false
    }
    
    public var isAudio: Bool {
        return self.mimeType?.isAudioMimeType() ?? false
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
}

extension ZMAssetClientMessage {
    
    private func setAndSyncNotUploaded(_ notUploaded: ZMAssetNotUploaded) {
        if self.genericAssetMessage?.assetData?.hasNotUploaded() == true {
            // already canceled
            return
        }
        
        let notUploadedMessage = ZMGenericMessage.genericMessage(notUploaded: notUploaded,
                                                                 messageID: self.nonce.transportString(),
                                                                 expiresAfter: self.deletionTimeout as NSNumber)
        self.add(notUploadedMessage)
        self.uploadState = .uploadingFailed
    }
    
    public func didFailToUploadFileData() {
        self.setAndSyncNotUploaded(.FAILED)
    }
    
    public func cancelTransfer() {
        
        switch self.transferState {
        case .uploading:
            self.setAndSyncNotUploaded(.CANCELLED)
            self.transferState = .cancelledUpload
            self.progress = 0
            self.expire()
        case .downloading:
            self.transferState = .uploaded
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
            return
        }
    }

    /// Turn temporary object ID into permanet
    private func obtainPermanentObjectID()
    {
        if self.objectID.isTemporaryID {
            try! self.managedObjectContext!.obtainPermanentIDs(for: [self])
        }
    }
    
}
