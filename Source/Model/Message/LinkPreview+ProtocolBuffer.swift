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
import ZMCLinkPreview

extension LinkPreview {
    
    public convenience init(protocolBuffer: ZMLinkPreview) {
        self.init(originalURLString: protocolBuffer.url, permamentURLString: protocolBuffer.permanentURLString, offset: Int(protocolBuffer.urlOffset))
    }
    
    public var protocolBuffer: ZMLinkPreview {
        let linkPreviewBuilder = ZMLinkPreview.builder()!
        linkPreviewBuilder.setUrl(originalURLString)
        linkPreviewBuilder.setPermanentUrl(permanentURL?.absoluteString ?? originalURLString)
        linkPreviewBuilder.setUrlOffset(Int32(characterOffsetInText))
        return linkPreviewBuilder.build()
    }
    
}

extension ZMLinkPreview {
    var permanentURLString: String {
        if hasPermanentUrl() {
            return permanentUrl
        }
        if hasArticle() {
            return article.permanentUrl
        }
        
        return ""
    }
}

extension Article {
    
    public convenience init(protocolBuffer: ZMLinkPreview) {
        self.init(originalURLString: protocolBuffer.url, permamentURLString: protocolBuffer.permanentURLString, offset: Int(protocolBuffer.urlOffset))
        let newTitle = protocolBuffer.hasArticle() ? protocolBuffer.article.title : protocolBuffer.title
        title = newTitle?.removingExtremeCombiningCharacters
        let newSummary = protocolBuffer.hasArticle() ? protocolBuffer.article.summary : protocolBuffer.summary
        summary = newSummary?.removingExtremeCombiningCharacters
    }

    override public var protocolBuffer: ZMLinkPreview {
        return ZMLinkPreview.linkPreview(
            withOriginalURL: originalURLString,
            permanentURL: permanentURL?.absoluteString ?? originalURLString,
            offset: Int32(characterOffsetInText),
            title: title,
            summary: summary,
            imageAsset: nil
        )
    }
}

extension TwitterStatus {
    
    public convenience init(protocolBuffer: ZMLinkPreview) {
        self.init(originalURLString: protocolBuffer.url, permamentURLString: protocolBuffer.permanentURLString, offset: Int(protocolBuffer.urlOffset))
        let newMessage = protocolBuffer.hasTweet() ? protocolBuffer.title : protocolBuffer.article.title
        message = newMessage?.removingExtremeCombiningCharacters
        let newAuthor = protocolBuffer.hasTweet() ? protocolBuffer.tweet.author : nil
        author = newAuthor?.removingExtremeCombiningCharacters
        let newUsername = protocolBuffer.hasTweet() ? protocolBuffer.tweet.username : nil
        username = newUsername?.removingExtremeCombiningCharacters
    }
    
    override public var protocolBuffer : ZMLinkPreview {
        return ZMLinkPreview.linkPreview(
            withOriginalURL: originalURLString,
            permanentURL: permanentURL?.absoluteString ?? originalURLString,
            offset: Int32(characterOffsetInText),
            title: message,
            summary: nil,
            imageAsset: nil,
            tweet: ZMTweet.tweet(withAuthor: author, username: username)
        )
    }
}
