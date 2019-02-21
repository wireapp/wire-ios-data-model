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
@objcMembers public class ZMAssetClientMessage: ZMOTRMessage {

    /// In memory cache
    var cachedGenericAssetMessage: ZMGenericMessage? = nil
    
    /// Creates a new `ZMAssetClientMessage` with an attached `imageAssetStorage`
    convenience internal init(originalImage imageData: Data,
                              nonce: UUID,
                              managedObjectContext: NSManagedObjectContext,
                              expiresAfter timeout: TimeInterval = 0)
    {
        self.init(nonce: nonce, managedObjectContext: managedObjectContext)
        
        // We update the size once the preprocessing is done
        // mimeType is assigned first, to make sure UI can handle animated GIF file correctly
        let mimeType = ZMAssetMetaDataEncoder.contentType(forImageData: imageData) ?? ""
        let asset = ZMAsset.asset(originalWithImageSize: CGSize.zero, mimeType: mimeType, size: UInt64(imageData.count))
        let message = ZMGenericMessage.message(content: asset, nonce: nonce, expiresAfter: timeout)
        
        add(message)
        preprocessedSize = ZMImagePreprocessor.sizeOfPrerotatedImage(with: imageData)
        transferState = .uploading
        version = 3
    }
    
    
    /// Inserts a new `ZMAssetClientMessage` in the `moc` and updates it with the given file metadata
    convenience internal init?(with metadata: ZMFileMetadata,
                              nonce: UUID,
                              managedObjectContext: NSManagedObjectContext,
                              expiresAfter timeout: TimeInterval = 0) {
        guard metadata.fileURL.isFileURL else { return nil } // just in case it tries to load from network!
        
        self.init(nonce: nonce, managedObjectContext: managedObjectContext)
        
        transferState = .uploading
        version = 3
        
        add(ZMGenericMessage.message(content: metadata.asset, nonce: nonce, expiresAfter: timeout))
    }
    
    public override var hashOfContent: Data? {
        guard let serverTimestamp = serverTimestamp else { return nil }
        
        return genericAssetMessage?.hashOfContent(with: serverTimestamp)
    }
    
    public override func prepareForDeletion() {
        super.prepareForDeletion()
        self.dataSet.map { $0 as! ZMGenericMessageData } .forEach {
            $0.managedObjectContext?.delete($0)
        }
    }
    
    /// Remote asset ID
    @objc public var assetId: UUID? {
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
    
    /// Current download / upload progress
    @NSManaged public var progress: Float
    
    /// True if we are current in the process of downloading the asset
    @NSManaged public var isDownloading: Bool
    
    /// State of the file transfer from the uploader's perspective
    @NSManaged public private(set) var transferState: AssetTransferState
    
    public func updateTransferState(_ transferState: AssetTransferState, synchronize: Bool) {
        self.transferState = transferState
        
        if synchronize {
            setLocallyModifiedKeys([#keyPath(ZMAssetClientMessage.transferState)])
        }
    }
    
    /// Download state
    public var downloadState: AssetDownloadState {
        if hasDownloadedFile {
            return .downloaded
        } else if isDownloading {
            return .downloading
        } else {
            return .unavailable
        }
    }
    
    /// Whether the image preview has been downloaded
    @objc public var hasDownloadedPreview: Bool {
        return self.asset?.hasDownloadedPreview ?? false
    }
    
    /// Whether the file has been downloaded
    @objc public var hasDownloadedFile: Bool {
        return self.asset?.hasDownloadedFile ?? false
    }
    
    // Wheather the referenced asset is encrypted
    public var hasEncryptedAsset : Bool {
        var hasEncryptionKeys = false
        
        if self.fileMessageData != nil {
            if let remote = self.genericAssetMessage?.assetData?.preview.remote, remote.hasOtrKey() {
                hasEncryptionKeys = true
            }
        } else if self.imageMessageData != nil {
            if let imageAsset = mediumGenericMessage?.imageAssetData, imageAsset.hasOtrKey() {
                hasEncryptionKeys = true
            }
        }
        
        return hasEncryptionKeys
    }
    
    /// The asset endpoint version used to generate this message
    /// values lower than 3 represent an enpoint version of 2
    @NSManaged public var version: Int16
    
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
        
        updateTransferState(.uploadingFailed, synchronize: false)
    }
    
    public override func resend() {
        self.transferState = .uploading
        self.progress = 0

        super.resend()
    }
    
    public override func update(withPostPayload payload: [AnyHashable : Any], updatedKeys: Set<AnyHashable>?) {
        if let serverTimestamp = (payload as NSDictionary).date(forKey: "time") {
            self.serverTimestamp = serverTimestamp
            self.expectsReadConfirmation = self.conversation?.hasReadReceiptsEnabled ?? false
        }
        conversation?.updateTimestampsAfterUpdatingMessage(self)
        
        // NOTE: Calling super since this is method overriden to handle special cases when receiving an asset
        super.startDestructionIfNeeded()
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
                #keyPath(ZMAssetClientMessage.hasDownloadedPreview),
                #keyPath(ZMAssetClientMessage.hasDownloadedFile),
                #keyPath(ZMAssetClientMessage.dataSet),
                #keyPath(ZMAssetClientMessage.downloadState),
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

@objc public enum AssetDownloadState: Int16 {
    case unavailable = 0
    case downloaded
    case downloading
}

@objc public enum AssetTransferState: Int16 {
    case uploading = 0
    case uploaded
    case uploadingFailed
    case uploadingCancelled
}

@objc public enum AssetProcessingState: Int16 {
    case done = 0
    case preprocessing
    case uploading
}

struct CacheAsset: Asset {
    
    enum AssetType {
        case image, file, thumbnail
    }
    
    var owner: ZMAssetClientMessage
    var type: AssetType
    var cache: FileAssetCache
    
    var needsPreprocessing: Bool {
        switch type {
        case .file:
            return false
        case .image, .thumbnail:
            return true
        }
    }
    
    var hasOriginal: Bool {
        if case .file = type  {
            return cache.hasDataOnDisk(owner, encrypted: false)
        } else {
            return cache.hasDataOnDisk(owner, format: .original, encrypted: false)
        }
    }
    
    var original: Data? {
        if case .file = type  {
            return cache.assetData(owner, encrypted: false)
        } else {
            return cache.assetData(owner, format: .original, encrypted: false)
        }
    }
    
    var hasPreprocessed: Bool {
        guard needsPreprocessing else { return false }
        
        return cache.hasDataOnDisk(owner, format: .medium, encrypted: false)
    }
    
    var preprocessed: Data? {
        guard needsPreprocessing else { return nil }
        
        return cache.assetData(owner, format: .medium, encrypted: false)
    }
    
    var hasEncrypted: Bool {
        if needsPreprocessing {
            return cache.hasDataOnDisk(owner, format: .medium, encrypted: true)
        } else {
            return cache.hasDataOnDisk(owner, encrypted: true)
        }
    }
    
    var encrypted: Data? {
        if needsPreprocessing {
            return cache.assetData(owner, format: .medium, encrypted: true)
        } else {
            return cache.assetData(owner, encrypted: true)
        }
    }
    
    var isUploaded: Bool {
        guard let genericMessage = owner.genericMessage else { return false }
        
        switch type {
        case .thumbnail:
            return genericMessage.asset.preview.remote.hasAssetId()
        case .file, .image:
            return genericMessage.asset.uploaded.hasAssetId()
        }
        
    }
    
    func updateWithAssetId(_ assetId: String, token: String?) {
        guard let genericMessage = owner.genericMessage else { return }
        
        var updatedGenericMessage: ZMGenericMessage
        switch type {
        case .thumbnail:
            updatedGenericMessage = genericMessage.updatedPreview(withAssetId: assetId, token: token)!
        case .image, .file:
            updatedGenericMessage = genericMessage.updatedUploaded(withAssetId: assetId, token: token)!
        }
        
        owner.add(updatedGenericMessage)
    }
    
    func updateWithPreprocessedData(_ preprocessedImageData: Data, imageProperties: ZMIImageProperties) {
        guard needsPreprocessing else { return }
        guard let genericMessage = owner.genericMessage else { return }
        
        cache.storeAssetData(owner, format: .medium, encrypted: false, data: preprocessedImageData)
        
        var updatedGenericMessage: ZMGenericMessage
        switch (type) {
        case .file:
            return
        case .image:
            updatedGenericMessage = genericMessage.updatedAssetOriginal(withImageProperties: imageProperties)!
        case .thumbnail:
            updatedGenericMessage = genericMessage.updatedAssetPreview(withImageProperties: imageProperties)!
        }
        
        owner.add(updatedGenericMessage)
    }
    
    func encrypt() {
        guard let genericMessage = owner.genericMessage else { return }
        
        var updatedGenericMessage: ZMGenericMessage
        switch type {
        case .file:
            let keys = cache.encryptFileAndComputeSHA256Digest(owner)!
            updatedGenericMessage = genericMessage.updatedAsset(withUploadedOTRKey: keys.otrKey, sha256: keys.sha256!)!
        case .image:
            let keys = cache.encryptImageAndComputeSHA256Digest(owner, format: .medium)!
            updatedGenericMessage = genericMessage.updatedAsset(withUploadedOTRKey: keys.otrKey, sha256: keys.sha256!)!
        case .thumbnail:
            let keys = cache.encryptImageAndComputeSHA256Digest(owner, format: .medium)!
            updatedGenericMessage = genericMessage.updatedAssetPreview(withUploadedOTRKey: keys.otrKey, sha256: keys.sha256!)!
        }
        
        owner.add(updatedGenericMessage)
    }
    
}


extension ZMAssetClientMessage: AssetMessage {
    
    public var assets: [Asset] {
        guard let cache = managedObjectContext?.zm_fileAssetCache else { return [] }
        
        var assets: [Asset] = []
        
        if isFile {
            if cache.hasDataOnDisk(self, encrypted: false) {
                assets.append(CacheAsset(owner: self, type: .file, cache: cache))
            }
            
            if cache.hasDataOnDisk(self, format: .original, encrypted: false) {
                assets.append(CacheAsset(owner: self, type: .thumbnail, cache: cache))
            }
        } else {
            if cache.hasDataOnDisk(self, format: .original, encrypted: false) {
                assets.append(CacheAsset(owner: self, type: .image, cache: cache))
            }
        }
        
        return assets
    }
    
    public var processingState: AssetProcessingState {
        let assets = self.assets
        
        if assets.filter({$0.needsPreprocessing && !$0.hasPreprocessed || !$0.hasEncrypted}).count > 0 {
            return .preprocessing
        }
        
        if assets.filter({!$0.isUploaded}).count > 0 {
            return .uploading
        }
        
        return .done
    }
    
}


public protocol AssetMessage {
    
    var assets: [Asset] { get }
    var processingState: AssetProcessingState { get }
        
}

public protocol Asset {
    
    var hasOriginal: Bool { get }
    var original: Data?  { get }
    
    var needsPreprocessing: Bool { get }
    var hasPreprocessed: Bool { get }
    var preprocessed: Data? { get }
    
    var hasEncrypted: Bool { get }
    var encrypted: Data? { get }
    
    var isUploaded: Bool { get }
    
    func updateWithAssetId(_ assetId: String, token: String?)
    func updateWithPreprocessedData(_ preprocessedImageData: Data, imageProperties: ZMIImageProperties)
    func encrypt()
    
}

