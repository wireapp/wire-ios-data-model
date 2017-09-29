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

extension ZMAssetClientMessage {
    
    func genericMessageDataFromDataSet(for format: ZMImageFormat) -> ZMGenericMessageData? {
        return self.dataSet.array
            .flatMap { $0 as? ZMGenericMessageData }
            .filter { $0.genericMessage.imageAssetData?.imageFormat() == format }
            .first
    }
    
    public var mediumGenericMessage: ZMGenericMessage? {
        return self.genericMessageDataFromDataSet(for: .medium)?.genericMessage
    }
    
    static func keyPathsForValuesAffectingMediumGenericMessage() -> Set<String> {
        return Set([#keyPath(ZMOTRMessage.dataSet), #keyPath(ZMOTRMessage.dataSet)+".data"])
    }
    
    public var previewGenericMessage: ZMGenericMessage? {
        return self.genericMessageDataFromDataSet(for: .preview)?.genericMessage
    }
    
    static func keyPathsForValuesAffectingPreviewGenericMessage() -> Set<String> {
        return Set([#keyPath(ZMOTRMessage.dataSet), #keyPath(ZMOTRMessage.dataSet)+".data"])
    }
    
    /// The generic asset message that is constructed by merging
    /// all generic messages from the dataset that contain an asset
    public var genericAssetMessage: ZMGenericMessage? {
        
        if self.cachedGenericAssetMessage == nil {
            self.cachedGenericAssetMessage = self.genericMessageMergedFromDataSet(filter: {
                $0.assetData != nil
            })
        }
        return self.cachedGenericAssetMessage
    }
    
    public func add(_ genericMessage: ZMGenericMessage) {
        let messageData = self.mergeWithExistingData(data: genericMessage.data())
        if self.nonce == nil {
            self.nonce = UUID(uuidString: messageData.genericMessage.messageId)
        }
        
        if (self.mediumGenericMessage?.imageAssetData?.otrKey.count ?? 0) > 0
            && (self.previewGenericMessage?.imageAssetData?.width ?? 0) > 0
            && self.deliveryState == .pending
        {
            self.uploadState = .uploadingPlaceholder
        }
    }
    
    func mergeWithExistingData(data: Data) -> ZMGenericMessageData {
        self.cachedGenericAssetMessage = nil
        
        let genericMessage = ZMGenericMessageBuilder().merge(from: data).build()! as! ZMGenericMessage
        
        if let imageFormat = genericMessage.imageAssetData?.imageFormat(),
            let existingMessageData = self.genericMessageDataFromDataSet(for: imageFormat)
        {
            existingMessageData.data = data
            return existingMessageData
        } else {
            return self.createNewGenericMessage(with: data)
        }
    }
    
    /// Creates a new generic message from the given data
    func createNewGenericMessage(with data: Data) -> ZMGenericMessageData {
        guard let moc = self.managedObjectContext else { fatalError() }
        let messageData = ZMGenericMessageData.insertNewObject(in: moc)
        messageData.data = data
        messageData.asset = self
        moc.processPendingChanges()
        return messageData
    }
    
    /// Merge all generic messages in the dataset that pass the filter
    func genericMessageMergedFromDataSet(filter: (ZMGenericMessage)->Bool) -> ZMGenericMessage? {
        
        let filteredMessages = self.dataSet.array
            .flatMap { ($0 as? ZMGenericMessageData)?.genericMessage }
            .filter(filter)
        
        guard !filteredMessages.isEmpty else {
            return nil
        }
        
        let builder = ZMGenericMessage.builder()!
        filteredMessages.forEach { builder.merge(from: $0) }
        return builder.build()
    }
    
    /// Returns the generic message for the given representation
    func genericMessage(dataType: AssetClientMessageDataType) -> ZMGenericMessage? {
        
        if self.fileMessageData != nil {
            switch dataType {
            case .fullAsset:
                guard let genericMessage = self.genericAssetMessage,
                    let assetData = genericMessage.assetData,
                    assetData.hasUploaded()
                    else { return nil }
                return genericMessage
            case .placeholder:
                return self.genericMessageMergedFromDataSet(filter: { (message) -> Bool in
                    guard let assetData = message.assetData else { return false }
                    return assetData.hasOriginal() || assetData.hasNotUploaded()
                })
            case .thumbnail:
                return self.genericMessageMergedFromDataSet(filter: { (message) -> Bool in
                    guard let assetData = message.assetData else { return false }
                    return assetData.hasPreview() && !assetData.hasUploaded()
                })
            }
        }
        
        if self.imageMessageData != nil {
            switch dataType {
            case .fullAsset:
                return self.mediumGenericMessage
            case .placeholder:
                return self.previewGenericMessage
            default:
                return nil
            }
        }
        
        return nil
    }
    
    
    override public var imageMessageData: ZMImageMessageData? {
        return self.asset?.imageMessageData
    }
    
    override public var fileMessageData: ZMFileMessageData? {
        let isFileMessage = self.genericAssetMessage?.assetData != nil
        return isFileMessage ? self : nil
    }
    
    public override func update(with message: ZMGenericMessage!, updateEvent: ZMUpdateEvent!) {
        self.add(message)
        
        if self.nonce == nil {
            self.nonce = UUID(uuidString: message.messageId)
        }
        
        let eventData = ((updateEvent.payload["data"]) as? [String: Any]) ?? [:]
        
        if let imageAssetData = message.imageAssetData {
            if imageAssetData.tag == "medium", let uuid = eventData["id"] as? String {
                self.assetId = UUID(uuidString: uuid)
            }
            
            if let inlinedDataString = eventData["data"] as? String,
                let inlinedData = Data(base64Encoded: inlinedDataString)
            {
                _ = self.updateMessage(imageData: inlinedData, for: .preview)
                return
            }
        }
        
        if let assetData = message.assetData,
            assetData.hasUploaded()
        {
            let isVersion_3 = assetData.uploaded.hasAssetId()
            if isVersion_3 { // V3, we directly access the protobuf for the assetId
                self.version = 3
            } else { // V2
                self.assetId = (eventData["id"] as? String).flatMap { UUID(uuidString: $0) }
            }
            
            self.transferState = .uploaded
        }
        
        if let assetData = message.assetData,
            assetData.hasNotUploaded() {
            switch assetData.notUploaded {
            case .CANCELLED:
                self.transferState = .cancelledUpload
            case .FAILED:
                self.transferState = .failedUpload
            }
        }
        
        // V2, we do not set the thumbnail assetId in case there is one in the protobuf, 
        // then we can access it directly for V3
        
        if let assetData = message.assetData,
            assetData.preview.hasRemote() && !assetData.hasUploaded() {
            
            if !assetData.preview.remote.hasAssetId() {
                if let thumbnailId = eventData["id"] as? String {
                    self.fileMessageData?.thumbnailAssetID = thumbnailId
                }
            } else {
                self.version = 3
            }
        }
        
        if let assetData = message.assetData,
            assetData.original.hasImage() {
            self.version = 3
        }
    }
}
