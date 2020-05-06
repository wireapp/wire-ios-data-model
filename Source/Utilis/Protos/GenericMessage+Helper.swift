//
// Wire
// Copyright (C) 2018 Wire Swiss GmbH
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
import WireProtos

public extension GenericMessage {
    init?(withBase64String base64String: String?) {
        guard
            let string = base64String,
            let data = Data(base64Encoded: string),
            let message = GenericMessage.with({ try? $0.merge(serializedData: data) }).validatingFields()
        else { return nil }
        self = message
    }
    
    init(content: EphemeralMessageCapable, nonce: UUID = UUID(), expiresAfter timeout: TimeInterval? = nil) {
        self = GenericMessage.with() {
            $0.messageID = nonce.transportString()
            let messageContent: MessageCapable
            if let timeout = timeout, timeout > 0 {
                messageContent = Ephemeral(content: content, expiresAfter: timeout)
            } else {
                messageContent = content
            }
            messageContent.setContent(on: &$0)
        }
    }
    
    init(content: MessageCapable, nonce: UUID = UUID()) {
        self = GenericMessage.with() {
            $0.messageID = nonce.transportString()
            let messageContent = content
            messageContent.setContent(on: &$0)
        }
    }
    
    init(clientAction action: ClientAction, nonce: UUID = UUID()) {
        self = GenericMessage.with {
            $0.messageID = nonce.transportString()
            $0.clientAction = action
        }
    }
}

public extension GenericMessage {
    var zmMessage: ZMGenericMessage? {
        let data = try? serializedData()
        return ZMGenericMessage.message(fromData: data)
    }
}

extension GenericMessage {
    var hasConfirmation: Bool {
        guard let content = content else { return false }
        switch content {
        case .confirmation:
            return true
        default:
            return false
        }
    }
}

extension GenericMessage {
    var locationData: Location? {
        guard let content = content else { return nil }
        switch content {
        case .location(let data):
            return data
        case .ephemeral(let data):
            switch data.content {
            case .location(let data)?:
                return data
            default:
                return nil
            }
        default:
            return nil
        }        
    }
    
    public var imageAssetData : ImageAsset? {
        guard let content = content else { return nil }
        switch content {
        case .image(let data):
            return data
        case .ephemeral(let data):
            switch data.content {
            case .image(let data)?:
                return data
            default:
                return nil
            }
        default:
            return nil
        }        
    }

    public var assetData: WireProtos.Asset? {
        guard let content = content else { return nil }
        switch content {
        case .asset(let data):
            return data
        case .ephemeral(let data):
            switch data.content {
            case .asset(let data)?:
                return data
            default:
                return nil
            }
        default:
            return nil
        }
    }
    
    public var knockData : Knock? {
        guard let content = content else { return nil }
        switch content {
        case .knock(let data):
            return data
        case .ephemeral(let data):
            switch data.content {
            case .knock(let data)?:
                return data
            default:
                return nil
            }
        default:
            return nil
        }
    }
    
    var textData: Text? {
        guard let content = content else { return nil }
        switch content {
        case .text(let data):
            return data
        case .edited(let messageEdit):
            if case .text(let data)? = messageEdit.content {
                return data
            }
        case .ephemeral(let ephemeral):
            if case .text(let data)? = ephemeral.content {
                return data
            }
        default:
            return nil
        }
        return nil
    }
}

extension GenericMessage {
    var linkPreviews: [LinkPreview] {
        guard let content = content else { return [] }
        switch content {
        case .text:
            return text.linkPreview.compactMap { $0 }
        case .edited:
            return edited.text.linkPreview.compactMap { $0 }
        case .ephemeral(let ephemeral):
            if case .text? = ephemeral.content {
                return ephemeral.text.linkPreview.compactMap { $0 }
            } else {
                return []
            }
        default:
            return []
        }
    }
}

extension Ephemeral {
    public init(content: EphemeralMessageCapable, expiresAfter timeout: TimeInterval) {
        self = Ephemeral.with() {
            $0.expireAfterMillis = Int64(timeout * 1000)
            content.setEphemeralContent(on: &$0)
        }
    }
}

public extension ClientEntry {
    init(withClient client: UserClient, data: Data) {
        self = ClientEntry.with {
            $0.client = client.clientId
            $0.text = data
        }
    }
}

public extension UserEntry {
    init(withUser user: ZMUser, clientEntries: [ClientEntry]) {
        self = UserEntry.with {
            $0.user = user.userId
            $0.clients = clientEntries
        }
    }
}

public extension NewOtrMessage {
    init(withSender sender: UserClient, nativePush: Bool, recipients: [UserEntry], blob: Data? = nil) {
        self = NewOtrMessage.with {
            $0.nativePush = nativePush
            $0.sender = sender.clientId
            $0.recipients = recipients
            if blob != nil {
                $0.blob = blob!
            }
        }
    }
}

extension ButtonAction {
    init(buttonId: String, referenceMessageId: UUID) {
        self = ButtonAction.with {
            $0.buttonID = buttonId
            $0.referenceMessageID = referenceMessageId.transportString()
        }
    }
}

extension Location {
    init(latitude: Float, longitude: Float) {
        self = WireProtos.Location.with({
            $0.latitude = latitude
            $0.longitude = longitude
        })
    }
}

extension Text {
    
    public init(content: String, mentions: [Mention] = [], linkPreviews: [LinkMetadata] = [], replyingTo: ZMOTRMessage? = nil) {
        self = Text.with {
            $0.content = content
            $0.mentions = mentions.compactMap { WireProtos.Mention($0) }
            $0.linkPreview = linkPreviews.map { WireProtos.LinkPreview($0) }
            
            if let quotedMessage = replyingTo,
               let quotedMessageNonce = quotedMessage.nonce,
               let quotedMessageHash = quotedMessage.hashOfContent {
                $0.quote = Quote.with({
                    $0.quotedMessageID = quotedMessageNonce.transportString()
                    $0.quotedMessageSha256 = quotedMessageHash
                })
            }
        }
    }
    
    public func applyEdit(from text: Text) -> Text {
        var updatedText = text
        // Transfer read receipt expectation
        updatedText.expectsReadConfirmation = expectsReadConfirmation
        
        // We always keep the quote from the original message
        hasQuote
            ? updatedText.quote = quote
            : updatedText.clearQuote()
        return updatedText
    }
    
    public func updateLinkPreview(from text: Text) -> Text {
        guard !text.linkPreview.isEmpty else {
            return self
        }
        do {
            let data = try serializedData()
            var updatedText = try Text(serializedData: data)
            updatedText.linkPreview = text.linkPreview
            return updatedText
        } catch {
            return self
        }
    }
}

extension WireProtos.Reaction {
    
    init(emoji: String, messageID: UUID) {
        self = WireProtos.Reaction.with({
            $0.emoji = emoji
            $0.messageID = messageID.transportString()
        })
    }
}

extension LastRead {
    
    public init(conversationID: UUID, lastReadTimestamp: Date) {
        self = LastRead.with {
            $0.conversationID = conversationID.transportString()
            $0.lastReadTimestamp = Int64(lastReadTimestamp.timeIntervalSince1970 * 1000)
        }
    }
}

extension Calling {
    
    public init(content: String) {
        self = Calling.with {
            $0.content = content
        }
    }
}

extension WireProtos.MessageEdit {
    
    public init(replacingMessageID: UUID, text: Text) {
        self = MessageEdit.with {
            $0.replacingMessageID = replacingMessageID.transportString()
            $0.text = text
        }
    }
}

extension Cleared {
    public init(timestamp: Date, conversationID: UUID) {
        self = Cleared.with {
            $0.clearedTimestamp = Int64(timestamp.timeIntervalSince1970 * 1000)
            $0.conversationID = conversationID.transportString()
        }
    }
}

extension MessageHide {
    public init(conversationId: UUID, messageId: UUID) {
        self = MessageHide.with {
            $0.conversationID = conversationId.transportString()
            $0.messageID = messageId.transportString()
        }
    }
}

extension MessageDelete {
    public init(messageId: UUID) {
        self = MessageDelete.with {
         $0.messageID = messageId.transportString()
        }
    }
}

extension WireProtos.Confirmation {
    
    init?(messageIds: [UUID], type: Confirmation.TypeEnum) {
        guard let firstMessageID = messageIds.first else {
            return nil
        }
        let moreMessageIds = Array(messageIds.dropFirst())
        self = WireProtos.Confirmation.with({
            $0.firstMessageID = firstMessageID.transportString()
            $0.moreMessageIds = moreMessageIds.map { $0.transportString() }
            $0.type = type
        })
    }
    
    public init(messageId: UUID, type: Confirmation.TypeEnum) {
        self = WireProtos.Confirmation.with {
            $0.firstMessageID = messageId.transportString()
            $0.type = type
        }
    }
}

extension External {
    init(withOTRKey otrKey: Data, sha256: Data) {
        self = External.with {
            $0.otrKey = otrKey
            $0.sha256 = sha256
        }
    }
    
    init(withKeyWithChecksum key: ZMEncryptionKeyWithChecksum) {
        self = External(withOTRKey: key.aesKey, sha256: key.sha256)
    }
}

extension WireProtos.Mention {
    
    init?(_ mention: WireDataModel.Mention) {
        guard let userID = (mention.user as? ZMUser)?.remoteIdentifier.transportString() else { return nil }
        
        self = WireProtos.Mention.with {
            $0.start = Int32(mention.range.location)
            $0.length = Int32(mention.range.length)
            $0.userID = userID
        }
    }
}

public extension LinkPreview {

    init(_ linkMetadata: LinkMetadata) {
        if let articleMetadata = linkMetadata as? ArticleMetadata {
            self = LinkPreview(articleMetadata: articleMetadata)
        } else if let twitterMetadata = linkMetadata as? TwitterStatusMetadata {
            self = LinkPreview(twitterMetadata: twitterMetadata)
        } else {
            self = LinkPreview.with {
                $0.url = linkMetadata.originalURLString
                $0.permanentURL = linkMetadata.permanentURL?.absoluteString ?? linkMetadata.resolvedURL?.absoluteString ?? linkMetadata.originalURLString
                $0.urlOffset = Int32(linkMetadata.characterOffsetInText)
            }
        }
    }
    
    init(articleMetadata: ArticleMetadata) {
        self = LinkPreview.with {
            $0.url = articleMetadata.originalURLString
            $0.permanentURL = articleMetadata.permanentURL?.absoluteString ?? articleMetadata.resolvedURL?.absoluteString ?? articleMetadata.originalURLString
            $0.urlOffset = Int32(articleMetadata.characterOffsetInText)
            $0.title = articleMetadata.title ?? ""
            $0.summary = articleMetadata.summary ?? ""
            if let imageData = articleMetadata.imageData.first {
                $0.image = WireProtos.Asset(imageSize: CGSize(width: 0, height: 0), mimeType: "image/jpeg", size: UInt64(imageData.count))
            }
        }
    }
    
    init(twitterMetadata: TwitterStatusMetadata) {
        self = LinkPreview.with {
            $0.url = twitterMetadata.originalURLString
            $0.permanentURL = twitterMetadata.permanentURL?.absoluteString ?? twitterMetadata.resolvedURL?.absoluteString ?? twitterMetadata.originalURLString
            $0.urlOffset = Int32(twitterMetadata.characterOffsetInText)
            $0.title = twitterMetadata.message ?? ""
            if let imageData = twitterMetadata.imageData.first {
                $0.image = WireProtos.Asset(imageSize: CGSize(width: 0, height: 0), mimeType: "image/jpeg", size: UInt64(imageData.count))
            }
            
            guard let author = twitterMetadata.author,
                let username = twitterMetadata.username else { return }
            
            $0.tweet = WireProtos.Tweet.with({
                $0.author = author
                $0.username = username
            })
        }
    }
    
    mutating func update(withOtrKey otrKey: Data, sha256: Data, original: WireProtos.Asset.Original?) {
        image.uploaded = WireProtos.Asset.RemoteData(withOTRKey: otrKey, sha256: sha256)
        if let original = original {
            image.original = original
        }
    }
}

// MARK:- Update assets

extension GenericMessage {
    
    public mutating func updatePreview(assetId: String, token: String?) {
        guard let content = content else {
            return
        }
        switch content {
        case .asset:
            self.asset.preview.remote.assetID = assetId
            if let token = token {
                self.asset.preview.remote.assetToken = token
            }
        case .ephemeral(let data):
            switch data.content {
            case .asset?:
                self.ephemeral.asset.preview.remote.assetID = assetId
                if let token = token {
                    self.ephemeral.asset.preview.remote.assetToken = token
                }
            default:
                return
            }
        default:
            return
        }
    }
    
    public mutating func updateUploaded(assetId: String, token: String?) {
        guard let content = content else {
            return
        }
        switch content {
        case .asset:
            self.asset.uploaded.assetID = assetId
            if let token = token {
                self.asset.uploaded.assetToken = token
            }
        case .ephemeral(let data):
            switch data.content {
            case .asset?:
                self.ephemeral.asset.uploaded.assetID = assetId
                if let token = token {
                    self.ephemeral.asset.uploaded.assetToken = token
                }
            default:
                return
            }
        default:
            return
        }
    }
    
    public mutating func update(asset: WireProtos.Asset) {
        guard let content = content else { return }
        switch content {
        case .asset:
            self.asset = asset
        case .ephemeral(let data):
            switch data.content {
            case .asset?:
                self.ephemeral.asset = asset
            default:
                return
            }
        default:
            return
        }
    }

}

// MARK:- Set message flags

extension GenericMessage {
    
    public mutating func setLegalHoldStatus(_ status: LegalHoldStatus) {
        guard let content = content else { return }
        switch content {
        case .ephemeral:
            self.ephemeral.updateLegalHoldStatus(status)
        case .reaction:
            self.reaction.legalHoldStatus = status
        case .knock:
            self.knock.legalHoldStatus = status
        case .text:
            self.text.legalHoldStatus = status
        case .location:
            self.location.legalHoldStatus = status
        case .asset:
            self.asset.legalHoldStatus = status
        default:
            return
        }
    }
    
    public mutating func setExpectsReadConfirmation(_ value: Bool) {
        guard let content = content else { return }
        switch content {
        case .ephemeral:
            self.ephemeral.updateExpectsReadConfirmation(value)
        case .knock:
            self.knock.expectsReadConfirmation = value
        case .text:
            self.text.expectsReadConfirmation = value
        case .location:
            self.location.expectsReadConfirmation = value
        case .asset:
            self.asset.expectsReadConfirmation = value
        default:
            return
        }
    }
}

extension ImageAsset {
    public func imageFormat() -> ZMImageFormat {
        return ImageFormatFromString(self.tag)
    }
}
