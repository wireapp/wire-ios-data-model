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


extension ZMGenericMessageBuilder {

    func setGeneratedMessage(message: PBGeneratedMessage) {
        switch message {
        case let location as ZMLocation:
            setLocation(location)
        case let asset as ZMAsset:
            setAsset(asset)
        case let image as ZMImageAsset:
            setImage(image)
        case let knock as ZMKnock:
            setKnock(knock)
        case let text as ZMText:
            setText(text)
        case let external as ZMExternal:
            setExternal(external)
        case let lastRead as ZMLastRead:
            setLastRead(lastRead)
        case let reaction as ZMReaction:
            setReaction(reaction)
        case let hide as ZMMessageHide:
            setHidden(hide)
        case let edit as ZMMessageEdit:
            setEdited(edit)
        case let delete as ZMMessageDelete:
            setDeleted(delete)
        case let confirmation as ZMConfirmation:
            setConfirmation(confirmation)
        case let cleared as ZMCleared:
            setCleared(cleared)
        default:
            preconditionFailure("Message type is not mapped yet. Add it to this enum.")
        }
    }
}

public extension ZMGenericMessage {
    
    @objc public static func genericMessage(pbMessage: PBGeneratedMessage, messageID: UUID, expiresAfter timeout: NSNumber? = nil) -> ZMGenericMessage {
        let builder = ZMGenericMessage.builder()!
        builder.setMessageId(messageID.transportString())
        if let timeout = timeout, timeout.compare(0) == .orderedDescending  {
            builder.setEphemeral(ZMEphemeral.ephemeral(pbMessage: pbMessage, expiresAfter: timeout))
        } else {
            builder.setGeneratedMessage(message: pbMessage)
        }
        return builder.build()
    }
}

@objc public extension ZMGenericMessage {

    var v3_isImage: Bool {
        return assetData?.original.hasRasterImage ?? false
    }

    var v3_uploadedAssetId: String? {
        guard assetData?.uploaded.hasAssetId() == true else { return nil }
        return assetData?.uploaded.assetId
    }

    var previewAssetId: String? {
        guard assetData?.preview.remote.hasAssetId() == true else { return nil }
        return assetData?.preview.remote.assetId
    }

}

public extension ZMGenericMessage {

    @objc public static func genericMessage(external: ZMExternal, messageID: UUID) -> ZMGenericMessage {
        return genericMessage(pbMessage: external, messageID: messageID)
    }
    
    @objc public static func genericMessage(withKeyWithChecksum keys: ZMEncryptionKeyWithChecksum, messageID: UUID) -> ZMGenericMessage {
        let external = ZMExternal.external(withKeyWithChecksum: keys)
        return ZMGenericMessage.genericMessage(external: external, messageID: messageID)
    }
    
    // MARK: ZMLocationMessageData
    
    @objc public static func genericMessage(location: ZMLocation, messageID: UUID, expiresAfter timeout: NSNumber? = nil) -> ZMGenericMessage {
        return genericMessage(pbMessage: location, messageID: messageID, expiresAfter: timeout)

    }
    
    // MARK: ZMAssetClientMessage
    
    @objc public static func genericMessage(asset: ZMAsset, messageID: UUID, expiresAfter timeout: NSNumber? = nil) -> ZMGenericMessage {
        return genericMessage(pbMessage: asset, messageID: messageID, expiresAfter: timeout)
    }
    
    @objc public static func genericMessage(withAssetSize size: UInt64,
                                                    mimeType: String,
                                                    name: String,
                                                    messageID: UUID,
                                       expiresAfter timeout: NSNumber? = nil) -> ZMGenericMessage {
        
        let asset = ZMAsset.asset(withOriginal: .original(withSize: size, mimeType: mimeType, name: name))
        return ZMGenericMessage.genericMessage(asset: asset, messageID: messageID, expiresAfter: timeout)
    }
    
    @objc public static func genericMessage(fileMetadata: ZMFileMetadata, messageID: UUID, expiresAfter timeout: NSNumber? = nil) -> ZMGenericMessage {
        return ZMGenericMessage.genericMessage(asset: fileMetadata.asset, messageID: messageID, expiresAfter: timeout)
    }
    
    @objc public static func genericMessage(withUploadedOTRKey otrKey: Data, sha256: Data, messageID: UUID, expiresAfter timeout: NSNumber? = nil) -> ZMGenericMessage {
        return ZMGenericMessage.genericMessage(asset: .asset(withUploadedOTRKey: otrKey, sha256: sha256), messageID: messageID, expiresAfter: timeout)
    }
    
    @objc public static func genericMessage(notUploaded: ZMAssetNotUploaded, messageID: UUID, expiresAfter timeout: NSNumber? = nil) -> ZMGenericMessage {
        return ZMGenericMessage.genericMessage(asset: .asset(withNotUploaded: notUploaded), messageID: messageID, expiresAfter: timeout)
    }
    
    @objc public static func genericMessage(imageData: Data, format:ZMImageFormat, nonce: UUID, expiresAfter timeout: NSNumber? = nil) -> ZMGenericMessage {
        let asset = ZMImageAsset(data: imageData, format: format)!
        return genericMessage(pbMessage: asset, messageID: nonce, expiresAfter: timeout)
    }
    
    @objc public static func genericMessage(mediumImageProperties: ZMIImageProperties?, processedImageProperties:ZMIImageProperties?, encryptionKeys: ZMImageAssetEncryptionKeys?, nonce: UUID, format:ZMImageFormat, expiresAfter timeout: NSNumber? = nil) -> ZMGenericMessage {
        let asset = ZMImageAsset(mediumProperties: mediumImageProperties, processedProperties: processedImageProperties, encryptionKeys: encryptionKeys, format: format)
        return genericMessage(pbMessage: asset, messageID: nonce, expiresAfter: timeout)
    }

    @objc public static func genericMessage(withImageSize imageSize: CGSize, mimeType: String, size: UInt64, nonce: UUID, expiresAfter timeout: NSNumber? = nil) -> ZMGenericMessage {
        let imageMeta = ZMAssetImageMetaData.imageMetaData(withWidth: Int32(imageSize.width), height: Int32(imageSize.height))
        let original = ZMAssetOriginal.original(withSize: size, mimeType: mimeType, name: nil, imageMetaData: imageMeta)
        let asset = ZMAsset.asset(withOriginal: original, preview: nil)
        return ZMGenericMessage.genericMessage(asset: asset, messageID: nonce, expiresAfter: timeout)
    }
        
    @objc public static func genericMessage(withAvailability availability : Availability) -> ZMGenericMessage {
        let messageBuilder = ZMGenericMessage.builder()!
        _ = messageBuilder.setAvailability(ZMAvailability.availability(availability))
        _ = messageBuilder.setMessageId(UUID().transportString())
        return messageBuilder.build()
    }
    
    // MARK: Text

    @objc public static func message(text: String, nonce: UUID, expiresAfter timeout: NSNumber? = nil) -> ZMGenericMessage {
        return message(text:text, linkPreview:nil, nonce:nonce, expiresAfter: timeout)
    }
    
    @objc public static func message(text: String, linkPreview: ZMLinkPreview?, nonce: UUID, expiresAfter timeout: NSNumber? = nil) -> ZMGenericMessage {
        return message(text:text, linkPreview:linkPreview, nonce:nonce, expiresAfter: timeout, mentions: [])
    }

    @objc public static func message(text: String, linkPreview: ZMLinkPreview?, nonce: UUID, expiresAfter timeout: NSNumber? = nil, mentions: [ZMMention]) -> ZMGenericMessage {
        let zmtext = ZMText(message:text, linkPreview:linkPreview, mentions: mentions)!
        return genericMessage(pbMessage: zmtext, messageID: nonce, expiresAfter: timeout)
    }

    // MARK: Knock

    @objc public static func knock(nonce: UUID, expiresAfter timeout: NSNumber? = nil) -> ZMGenericMessage {
        let knockBuilder = ZMKnock.builder()!
        knockBuilder.setHotKnock(false)
        return genericMessage(pbMessage: knockBuilder.build(), messageID: nonce, expiresAfter: timeout)
    }

    // MARK: Updating assets with asset ID and token
    @objc public func updatedUploaded(withAssetId assetId: String, token: String?) -> ZMGenericMessage? {
        guard let asset = assetData, let remote = asset.uploaded, asset.hasUploaded() else { return nil }
        let newRemote = remote.updated(withId: assetId, token: token)
        let builder = toBuilder()!
        if hasAsset() {
            let assetBuilder = asset.toBuilder()
            _ = assetBuilder?.setUploaded(newRemote)
            builder.setAsset(assetBuilder)
        } else if hasEphemeral() && ephemeral.hasAsset() {
            let ephemeralBuilder = ephemeral.toBuilder()
            let assetBuilder = ephemeral.asset.toBuilder()
            _ = assetBuilder?.setUploaded(newRemote)
            _ = ephemeralBuilder?.setAsset(assetBuilder)
            builder.setEphemeral(ephemeralBuilder)
        } else {
            return nil
        }

        return builder.buildAndValidate()
    }

    @objc public func updatedPreview(withAssetId assetId: String, token: String?) -> ZMGenericMessage? {
        guard let asset = assetData, let preview = asset.preview, let remote = preview.remote, preview.hasRemote() else { return nil }
        let newRemote = remote.updated(withId: assetId, token: token)
        let previewBuilder = preview.toBuilder()
        _ = previewBuilder?.setRemote(newRemote)
        let builder = toBuilder()!
        if hasAsset() {
            let assetBuilder = asset.toBuilder()
            _ = assetBuilder?.setPreview(previewBuilder)
            builder.setAsset(assetBuilder)
        } else if hasEphemeral() && ephemeral.hasAsset() {
            let ephemeralBuilder = ephemeral.toBuilder()
            let assetBuilder = ephemeral.asset.toBuilder()
            _ = assetBuilder?.setPreview(previewBuilder)
            _ = ephemeralBuilder?.setAsset(assetBuilder)
            builder.setEphemeral(ephemeralBuilder)
        } else {
            return nil
        }

        return builder.buildAndValidate()
    }

}

@objc extension ZMAssetRemoteData {

    public func updated(withId assetId: String, token: String?) -> ZMAssetRemoteData {
        let builder = toBuilder()!
        builder.setAssetId(assetId)
        if let token = token {
            builder.setAssetToken(token)
        }
        return builder.build()
    }

}

extension ZMGenericMessage {
    
    // Accessor helpers for linkpreviews
    @objc public var linkPreviews: [ZMLinkPreview] {
        if hasText(), let previews = text.linkPreview {
            return previews.compactMap { $0 }
        }
        if hasEdited(), let previews = edited.text.linkPreview {
            return previews.compactMap { $0 }
        }
        if hasEphemeral() && ephemeral.hasText(), let previews = ephemeral.text.linkPreview {
            return previews.compactMap { $0 }
        }
        return []
    }
    
    // Accessor helpers for ephemeral images
    @objc public var imageAssetData : ZMImageAsset? {
        if hasRasterImage {
            return image
        }
        if hasEphemeral() && ephemeral.hasRasterImage {
            return ephemeral.image
        }
        return nil
    }

    @objc public var locationData : ZMLocation? {
        if hasLocation() {
            return location
        }
        if hasEphemeral() && ephemeral.hasLocation() {
            return ephemeral.location
        }
        return nil
    }
    
    @objc public var assetData : ZMAsset? {
        if hasAsset() {
            return asset
        }
        if hasEphemeral() && ephemeral.hasAsset() {
            return ephemeral.asset
        }
        return nil
    }
    
    @objc public var knockData : ZMKnock? {
        if hasKnock() {
            return knock
        }
        if hasEphemeral() && ephemeral.hasKnock() {
            return ephemeral.knock
        }
        return nil
    }
    
    @objc public var textData : ZMText? {
        if hasText() {
            return text
        }
        if hasEdited() && edited.hasText() {
            return edited.text
        }
        if hasEphemeral() && ephemeral.hasText() {
            return ephemeral.text
        }
        return nil
    }

}

public extension ZMEphemeral {
    
    @objc public static func ephemeral(pbMessage: PBGeneratedMessage, expiresAfter timeout: NSNumber) -> ZMEphemeral? {
        let ephBuilder = ZMEphemeral.builder()!
        switch pbMessage {
        case let location as ZMLocation:
            ephBuilder.setLocation(location)
        case let asset as ZMAsset:
            ephBuilder.setAsset(asset)
        case let image as ZMImageAsset:
            ephBuilder.setImage(image)
        case let knock as ZMKnock:
            ephBuilder.setKnock(knock)
        case let text as ZMText:
            ephBuilder.setText(text)
        default:
            return nil
        }
        let doubleTimeout = timeout.doubleValue
        ephBuilder.setExpireAfterMillis(Int64(doubleTimeout*1000))
        return ephBuilder.build()
    }
}


public extension ZMLocation {

    public static func location(withLatitude latitude: Float, longitude: Float, name: String? = nil, zoomLevel: Int32? = nil) -> ZMLocation {
        let builder = ZMLocation.builder()!
        builder.setLatitude(latitude)
        builder.setLongitude(longitude)
        if let name = name {
            builder.setName(name)
        }
        if let zoomLevel = zoomLevel {
            builder.setZoom(zoomLevel)
        }
        return builder.build()
    }
}

public extension ZMExternal {
    
    @objc public static func external(withOTRKey otrKey: Data, sha256: Data) -> ZMExternal {
        let builder = ZMExternal.builder()!
        builder.setOtrKey(otrKey)
        builder.setSha256(sha256)
        return builder.build()
    }
    
    @objc public static func external(withKeyWithChecksum keys: ZMEncryptionKeyWithChecksum) -> ZMExternal {
        return ZMExternal.external(withOTRKey: keys.aesKey, sha256: keys.sha256)
    }
    
}

public extension ZMClientEntry {
    
    @objc public static func entry(withClient client: UserClient, data: Data) -> ZMClientEntry {
        let builder = ZMClientEntry.builder()!
        builder.setClient(client.clientId)
        builder.setText(data)
        return builder.build()
    }
    
}

public extension ZMUserEntry {
    
    @objc public static func entry(withUser user: ZMUser, clientEntries: [ZMClientEntry]) -> ZMUserEntry {
        let builder = ZMUserEntry.builder()!
        builder.setUser(user.userId())
        builder.setClientsArray(clientEntries)
        return builder.build()
    }
    
}

public extension ZMNewOtrMessage {
    
    @objc public static func message(withSender sender: UserClient, nativePush: Bool, recipients: [ZMUserEntry], blob: Data? = nil) -> ZMNewOtrMessage {
        let builder = ZMNewOtrMessage.builder()!
        builder.setNativePush(nativePush)
        builder.setSender(sender.clientId)
        builder.setRecipientsArray(recipients)
        if nil != blob {
            builder.setBlob(blob)
        }
        return builder.build()
    }
    
}

public extension ZMOtrAssetMeta {
    
    @objc public static func otrAssetMeta(withSender sender: UserClient, nativePush: Bool, inline: Bool, recipients: [ZMUserEntry]) -> ZMOtrAssetMeta {
        let builder = ZMOtrAssetMeta.builder()!
        builder.setNativePush(nativePush)
        builder.setIsInline(inline)
        builder.setSender(sender.clientId)
        builder.setRecipientsArray(recipients)
        return builder.build()
    }
    
}


public extension ZMArticle {

    @objc public static func article(withPermanentURL permanentURL: String, title: String?, summary: String?, imageAsset: ZMAsset?) -> ZMArticle {
        let articleBuilder = ZMArticle.builder()!
        articleBuilder.setPermanentUrl(permanentURL)
        if let title = title {
            articleBuilder.setTitle(title)
        }
        if let summary = summary {
            articleBuilder.setSummary(summary)
        }
        if let image = imageAsset {
            articleBuilder.setImage(image)
        }
        return articleBuilder.build()
    }
    
}

public extension ZMLinkPreview {
    
    @objc public static func linkPreview(withOriginalURL originalURL: String, permanentURL: String, offset: Int32, title: String?, summary: String?, imageAsset: ZMAsset?) -> ZMLinkPreview {
        return linkPreview(withOriginalURL: originalURL, permanentURL: permanentURL, offset: offset, title: title, summary: summary, imageAsset: imageAsset, tweet: nil)
    }
    
    @objc public static func linkPreview(withOriginalURL originalURL: String, permanentURL: String, offset: Int32, title: String?, summary: String?, imageAsset: ZMAsset?, tweet: ZMTweet?) -> ZMLinkPreview {
        let article = ZMArticle.article(withPermanentURL: permanentURL, title: title, summary: summary, imageAsset: imageAsset)
        return linkPreview(withOriginalURL: originalURL, permanentURL: permanentURL, offset: offset, title: title, summary: summary, imageAsset: imageAsset, article: article, tweet: tweet)
    }
    
    fileprivate static func linkPreview(withOriginalURL originalURL: String, permanentURL: String, offset: Int32, title: String?, summary: String?, imageAsset: ZMAsset?, article: ZMArticle?, tweet: ZMTweet?) -> ZMLinkPreview {
        let linkPreviewBuilder = ZMLinkPreview.builder()!
        linkPreviewBuilder.setUrl(originalURL)
        linkPreviewBuilder.setPermanentUrl(permanentURL)
        linkPreviewBuilder.setUrlOffset(offset)
        
        if let title = title {
            linkPreviewBuilder.setTitle(title)
        }
        if let summary = summary {
            linkPreviewBuilder.setSummary(summary)
        }
        if let imageAsset = imageAsset {
            linkPreviewBuilder.setImage(imageAsset)
        }
        if let tweet = tweet {
            linkPreviewBuilder.setTweet(tweet)
        }
        if let article = article {
            linkPreviewBuilder.setArticle(article)
        }
        
        return linkPreviewBuilder.build()
    }

    func update(withOtrKey otrKey: Data, sha256: Data) -> ZMLinkPreview {
        return update(withOtrKey: otrKey, sha256: sha256, original: nil)
    }
    
    func update(withOtrKey otrKey: Data, sha256: Data, original: ZMAssetOriginal?) -> ZMLinkPreview {
        let linkPreviewbuilder = toBuilder()!
        
        if hasArticle() {
            let articleBuilder = article.toBuilder()!
            let assetBuilder = article.image.toBuilder()!
            assetBuilder.setUploaded(remoteBuilder(withOTRKey: otrKey, sha256: sha256))
            if let original = original {
                assetBuilder.setOriginal(original)
            }
            articleBuilder.setImage(assetBuilder)
            linkPreviewbuilder.setArticle(articleBuilder)
        }
        
        let newAssetBuilder = image.toBuilder()!
        newAssetBuilder.setUploaded(remoteBuilder(withOTRKey: otrKey, sha256: sha256))
        if let original = original {
            newAssetBuilder.setOriginal(original)
        }
        linkPreviewbuilder.setImage(newAssetBuilder)
        
        return linkPreviewbuilder.build()
    }
    
    func update(withAssetKey assetKey: String, assetToken: String?) -> ZMLinkPreview {
        
        let linkPreviewbuilder = toBuilder()!
        
        if hasArticle() {
            let articleRemoteBuilder = article.image.uploaded.builder(withAssetID: assetKey, token: assetToken)
            let articleBuilder = article.toBuilder()!
            let assetBuilder = article.image.toBuilder()!
            assetBuilder.setUploaded(articleRemoteBuilder)
            articleBuilder.setImage(assetBuilder)
            linkPreviewbuilder.setArticle(articleBuilder)
        }
        
        let newAssetRemoteBuilder = image.uploaded.builder(withAssetID: assetKey, token: assetToken)
        let newImageBuilder = image.toBuilder()!
        newImageBuilder.setUploaded(newAssetRemoteBuilder)
        linkPreviewbuilder.setImage(newImageBuilder)
        
        return linkPreviewbuilder.build()
    }
    
    fileprivate func remoteBuilder(withOTRKey otrKey: Data, sha256: Data) -> ZMAssetRemoteDataBuilder {
        let remoteDataBuilder = ZMAssetRemoteData.builder()!
        remoteDataBuilder.setOtrKey(otrKey)
        remoteDataBuilder.setSha256(sha256)
        return remoteDataBuilder
    }
    
    fileprivate func uploadedBuilder(withAssetKey key: String, token: String?) -> ZMAssetRemoteDataBuilder {
        let remoteDataBuilder = ZMAssetRemoteData.builder()!
        remoteDataBuilder.setAssetId(key)
        if let token = token {
            remoteDataBuilder.setAssetToken(token)
        }
        return remoteDataBuilder
    }
    
}


public extension ZMTweet {
    @objc public static func tweet(withAuthor author: String?, username: String?) -> ZMTweet {
        let builder = ZMTweet.builder()!
        if let author = author {
            builder.setAuthor(author)
        }
        if let username = username {
            builder.setUsername(username)
        }
        return builder.build()
    }
}

public extension ZMAvailability {
    
    public static func availability(_ availability : Availability) -> ZMAvailability {
        let builder = ZMAvailability.builder()!
        
        switch availability {
        case .none:
            builder.setType(.NONE)
        case .available:
            builder.setType(.AVAILABLE)
        case .away:
            builder.setType(.AWAY)
        case .busy:
            builder.setType(.BUSY)
        }
        
        return builder.build()
    }
    
}

@objc
extension ZMMention {
    
    public static func mention(_ mention: Mention) -> ZMMention? {
        guard let userId = (mention.user as? ZMUser)?.remoteIdentifier else { return nil }
        
        let builder = ZMMentionBuilder()
        
        builder.setUserId(userId.transportString())
        builder.setStart(Int32(mention.range.lowerBound))
        builder.setEnd(Int32(mention.range.upperBound))
    
        return builder.build()
    }
    
}


