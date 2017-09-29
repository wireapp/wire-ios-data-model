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

/// An asset message (image, file, ...)
@objc public class ZMAssetClientMessage: ZMOTRMessage {

    /// In memory cache
    var cachedGenericAssetMessage: ZMGenericMessage? = nil
    
    /// Remote asset ID
    public var assetId: UUID? {
        get { return self.transientUUID(forKey: #keyPath(ZMAssetClientMessage.assetId)) }
        set { self.setTransientUUID(newValue, forKey: #keyPath(ZMAssetClientMessage.assetId)) }
    }
    
    public static func keyPathsForValuesAffectingAssetID() -> Set<String> {
        return Set(arrayLiteral: #keyPath(ZMAssetClientMessage.assetID_data))
    }
    
    /// Preprocessed size of image
    public var preprocessedSize: CGSize {
        get { return self.transientCGSize(forKey: #keyPath(ZMAssetClientMessage.preprocessedSize)) }
        set { self.setTransientCGSize(newValue, forKey: #keyPath(ZMAssetClientMessage.preprocessedSize)) }
    }
    
    public static func keyPathsForValuesPreprocessedSize() -> Set<String> {
        return Set(arrayLiteral: #keyPath(ZMAssetClientMessage.assetID_data))
    }
    
    /// Original file size
    public var size: UInt64 {
        guard let asset = self.genericAssetMessage?.assetData else { return 0 }
        let originalSize = asset.original.size
        let previewSize = asset.preview.size
    
        if originalSize == 0 {
            return previewSize
        }
        return originalSize
    }
    
    /// Currend download / upload progress
    @NSManaged public var progress: Float
    
    /// File transfer state
    @NSManaged public var transferState: ZMFileTransferState

    /// Upload state
    public var uploadState: AssetUploadState {
        get {
            let key = #keyPath(ZMAssetClientMessage.uploadState)
            self.willAccessValue(forKey: key)
            let value = (self.primitiveValue(forKey: key) as? Int16) ?? 0
            self.didAccessValue(forKey: key)
            return AssetUploadState(rawValue: value) ?? .done
        }
        set {
            let key = #keyPath(ZMAssetClientMessage.uploadState)
            self.willChangeValue(forKey: key)
            self.setPrimitiveValue(newValue.rawValue, forKey: key)
            self.didChangeValue(forKey: key)
            self.setLocallyModifiedKeys(Set([key]))
        }
    }
    
    /// Whether the image was downloaded
    public var hasDownloadedImage: Bool {
        return self.asset?.hasDownloadedImage ?? false
    }
    
    /// Whether the file was downloaded
    public var hasDownloadedFile: Bool {
        return self.asset?.hasDownloadedFile ?? false
    }
    
    /// The asset endpoint version used to generate this message
    /// values lower than 3 represent an enpoint version of 2
    @NSManaged public var version: Int16

    // The image metaData if if this `ZMAssetClientMessage` represents an image
    // or `nil` otherwise
    public var imageAssetStorage: ImageAssetStorage {
        return self
    }
    
    /// Used to associate and persist the task identifier of the `NSURLSessionTask`
    /// with the upload or download of the file data. Can be used to verify that the
    /// data of a `FileMessage` is being down- or uploaded after a termination event
    public var associatedTaskIdentifier: ZMTaskIdentifier? {
        get {
            let key = #keyPath(ZMAssetClientMessage.associatedTaskIdentifier_data)
            self.willAccessValue(forKey: key)
            let data = self.primitiveValue(forKey: key) as? Data
            self.didAccessValue(forKey: key)
            let value = data.flatMap { ZMTaskIdentifier(from: $0) }
            return value
        }
        set {
            let key = #keyPath(ZMAssetClientMessage.associatedTaskIdentifier_data)
            self.willChangeValue(forKey: key)
            self.setPrimitiveValue(newValue?.data, forKey: key)
            self.didChangeValue(forKey: key)
        }
    }

    static func keyPathsForValuesAffectingAssociatedTaskIdentifier() -> Set<String> {
        return Set(arrayLiteral: #keyPath(ZMAssetClientMessage.associatedTaskIdentifier_data))
    }
    
    /// Creates a new `ZMAssetClientMessage` with an attached `imageAssetStorage`
    public static func assetClientMessage(originalImage imageData: Data,
                                   nonce: UUID,
                                   managedObjectContext: NSManagedObjectContext,
                                   expiresAfter timeout: TimeInterval) -> ZMAssetClientMessage
    {

        managedObjectContext.zm_imageAssetCache.storeAssetData(nonce,
                                                               format: .original,
                                                               encrypted: false,
                                                               data: imageData)
        let message = ZMAssetClientMessage.insertNewObject(in: managedObjectContext)
        let originalSize = ZMImagePreprocessor.sizeOfPrerotatedImage(with: imageData)
        
        // We update the size and mimeType once the preprocesing is done
        let assetMessage = ZMGenericMessage.genericMessage(withImageSize: CGSize.zero,
                                                           mimeType: "",
                                                           size: UInt64(imageData.count),
                                                           nonce: nonce.transportString(),
                                                           expiresAfter: timeout as NSNumber)
        message.add(assetMessage)
        message.preprocessedSize = originalSize
        message.uploadState = .uploadingFullAsset
        message.transferState = .uploading
        message.version = 3
        
        return message
    }
    
    
    /// Inserts a new `ZMAssetClientMessage` in the `moc` and updates it with the given file metadata
    public static func assetClientMessage(with metadata: ZMFileMetadata,
                                   nonce: UUID,
                                   managedObjectContext: NSManagedObjectContext,
                                   expiresAfter timeout: TimeInterval
        ) -> ZMAssetClientMessage?
    {
        guard metadata.fileURL.isFileURL else { return nil } // just in case it tries to load from network!
        guard let data = try? Data(contentsOf: metadata.fileURL, options: .mappedIfSafe) else { return nil }
        
        managedObjectContext.zm_fileAssetCache.storeAssetData(nonce,
                                                              fileName: metadata.fileURL.lastPathComponent,
                                                              encrypted: false,
                                                              data: data)
        let message = ZMAssetClientMessage.insertNewObject(in: managedObjectContext)
        message.transferState = .uploading
        message.uploadState = .uploadingPlaceholder
        message.add(ZMGenericMessage.genericMessage(fileMetadata: metadata,
                                                    messageID: nonce.transportString(),
                                                    expiresAfter: timeout as NSNumber
        ))
        message.delivered = false
        message.version = 3
        
        if let thumbnail = metadata.thumbnail {
            managedObjectContext.zm_imageAssetCache.storeAssetData(nonce, format: .original,
                                                                   encrypted: false,
                                                                   data: thumbnail)
        }
        
        return message
    }
    
    /// Marks file to be downloaded
    override public func requestFileDownload() {
        self.asset?.requestFileDownload()
    }

    override public func requestImageDownload() {
        self.asset?.requestImageDownload()
    }
    
    var v2Asset: V2Asset? {
        return V2Asset(with: self)
    }
    
    var v3Asset: V3Asset? {
        return V3Asset(with: self)
    }
    
    var asset: AssetProxyType? {
        return self.v2Asset ?? self.v3Asset
    }
    
    public override func expire() {
        super.expire()
        
        guard !self.delivered && self.transferState == .uploading else { return }

        self.transferState = .failedUpload
        
        // When we expire an asset message because the conversation degraded we do not want to send
        // a `NOT UPLOADED` message. In all other cases we do want to sent a `NOT UPLOADED` 
        // message to let the reveicers know we stopped uploading.
        if self.uploadState == .uploadingPlaceholder {
            self.uploadState = .done
        } else {
            self.didFailToUploadFileData()
        }

    }
    
    public override func resend() {
        if self.v3_isImage {
            self.uploadState = .uploadingFullAsset
        } else {
            self.uploadState = .uploadingPlaceholder
        }
        
        self.transferState = .uploading
        self.progress = 0
        self.removeNotUploaded()
        
        super.resend()
    }
    
    private func removeNotUploaded() {
        for data in self.dataSet.array.map({ $0 as! ZMGenericMessageData }) {
            if let assetData = data.genericMessage.assetData,
                assetData.hasNotUploaded() {
                data.asset = nil
                self.managedObjectContext?.delete(data)
                self.cachedGenericAssetMessage = nil
                return
            }
        }
    }
    
    //For image messages we have two events - for preview and medium format
    //To preserve messages order we need to keep the earliest serverTimestamp of these two events
    public override func updateTimestamp(_ timestamp: Date?, isUpdatingExistingMessage isUpdate: Bool) {
        if isUpdate {
            self.serverTimestamp = NSDate.earliest(of: self.serverTimestamp, and: timestamp)
        } else if timestamp != nil {
            self.serverTimestamp = timestamp
        }
    }
    
    public override func update(withPostPayload payload: [AnyHashable : Any], updatedKeys: Set<AnyHashable>?) {
        guard let updatedKeys = updatedKeys,
            updatedKeys.contains(#keyPath(ZMAssetClientMessage.uploadState))
        else { return }
        
        let shouldUpdate = self.uploadState == .uploadingPlaceholder
            || (self.uploadState == .uploadingFullAsset && self.v3_isImage)
        
        
        if shouldUpdate {
            if let serverTimestamp = (payload as NSDictionary).date(forKey: "time") {
                self.serverTimestamp = serverTimestamp
                self.conversation?.updateLastReadServerTimeStampIfNeeded(withTimeStamp: serverTimestamp, andSync: false)
            }
            self.conversation?.resortMessages(withUpdatedMessage: self)
            self.conversation?.update(with: self, timeStamp: serverTimestamp)
        }
        
        _ = self.startDestructionIfNeeded()
    }
    
    // Private implementation
    @NSManaged fileprivate var assetID_data: Data
    @NSManaged fileprivate var preprocessedSize_data: Data
    @NSManaged fileprivate var associatedTaskIdentifier_data: Data

}

// MARK: - Core data
extension ZMAssetClientMessage {
    
    override public func awakeFromInsert() {
        super.awakeFromInsert()
        self.nonce = nil
        self.cachedGenericAssetMessage = nil
    }
    
    override public func awakeFromFetch() {
        super.awakeFromFetch()
        self.cachedGenericAssetMessage = nil
    }
    
    override public func awake(fromSnapshotEvents flags: NSSnapshotEventType) {
        super.awake(fromSnapshotEvents: flags)
        self.cachedGenericAssetMessage = nil
    }
    
    override public func didTurnIntoFault() {
        super.didTurnIntoFault()
        self.cachedGenericAssetMessage = nil
    }
    
    public override static func entityName() -> String {
        return "AssetClientMessage"
    }
    
    public override var ignoredKeys: Set<AnyHashable>? {
        return (super.ignoredKeys ?? Set())
            .union([
                #keyPath(ZMAssetClientMessage.assetID_data),
                #keyPath(ZMAssetClientMessage.preprocessedSize_data),
                #keyPath(ZMAssetClientMessage.hasDownloadedImage),
                #keyPath(ZMAssetClientMessage.hasDownloadedFile),
                #keyPath(ZMAssetClientMessage.dataSet),
                #keyPath(ZMAssetClientMessage.transferState),
                #keyPath(ZMAssetClientMessage.progress),
                #keyPath(ZMAssetClientMessage.associatedTaskIdentifier_data),
                #keyPath(ZMAssetClientMessage.version)
            ])
        
    }
    
    override static public func predicateForObjectsThatNeedToBeUpdatedUpstream() -> NSPredicate? {
        return nil
    }
}

@objc public enum AssetClientMessageDataType: UInt {
    case placeholder = 1
    case fullAsset = 2
    case thumbnail = 3
}

@objc public enum AssetUploadState: Int16 {
    case done = 0
    case uploadingPlaceholder = 1
    case uploadingThumbnail = 2
    case uploadingFullAsset = 3
    case uploadingFailed = 4
}


