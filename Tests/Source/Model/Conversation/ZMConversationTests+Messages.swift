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
import WireImages
@testable import WireDataModel

class ZMConversationMessagesTests: ZMConversationTestsBase {
    
    func testThatWeCanInsertATextMessage() {
        
        self.syncMOC.performGroupedBlockAndWait {
            
            // given
            let selfUser = ZMUser.selfUser(in: self.syncMOC)
            let conversation = ZMConversation.insertNewObject(in: self.syncMOC)
            conversation.remoteIdentifier = UUID()
    
            // when
            let messageText = "foo"
            let message = conversation.appendMessage(withText: messageText)!
    
            // then
            XCTAssertEqual(message.textMessageData?.messageText, messageText)
            XCTAssertEqual(message.conversation, conversation)
            XCTAssertTrue(conversation.messages.contains(message))
            XCTAssertEqual(selfUser, message.sender)
        }
    }

    
    func testThatItUpdatesTheLastModificationDateWhenInsertingMessagesIntoAnEmptyConversation()
    {
        // given
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        conversation.lastModifiedDate = Date(timeIntervalSinceNow: -90000)
        
        // when
        guard let msg = conversation.appendMessage(withText: "Foo") as? ZMMessage else {
            XCTFail()
            return
        }
    
        // then
        XCTAssertNotNil(msg.serverTimestamp)
        XCTAssertEqual(conversation.lastModifiedDate, msg.serverTimestamp)
    }
    
    func testThatItUpdatesTheLastModificationDateWhenInsertingMessages()
    {
        // given
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        guard let msg1 = conversation.appendMessage(withText: "Foo") as? ZMMessage else {
            XCTFail()
            return
        }
        msg1.serverTimestamp = Date(timeIntervalSinceNow: -90000)
        conversation.lastModifiedDate = msg1.serverTimestamp
    
        // when
        guard let msg2 = conversation.appendMessage(withImageData: self.verySmallJPEGData()) as? ZMAssetClientMessage else {
            XCTFail()
            return
        }
    
        // then
        XCTAssertNotNil(msg2.serverTimestamp)
        XCTAssertEqual(conversation.lastModifiedDate, msg2.serverTimestamp)
    }
    
    func testThatItDoesNotUpdateTheLastModifiedDateForRenameAndLeaveSystemMessages()
    {
        let types = [
            ZMSystemMessageType.teamMemberLeave,
            ZMSystemMessageType.conversationNameChanged
        ]
        for type in types {
            // given
            let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
            let lastModified = Date(timeIntervalSince1970: 10)
            conversation.lastModifiedDate = lastModified
    
            let systemMessage = ZMSystemMessage.insertNewObject(in: self.uiMOC)
            systemMessage.systemMessageType = type
            systemMessage.serverTimestamp = lastModified.addingTimeInterval(100)
    
            // when
            conversation.sortedAppendMessage(systemMessage)
    
            // then
            XCTAssertEqual(conversation.lastModifiedDate, lastModified)
        }
    }
    
    func testThatItIsSafeToPassInAMutableStringWhenCreatingATextMessage()
    {
        // given
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        conversation.remoteIdentifier = UUID()
    
        // when
        let originalText = "foo";
        var messageText = originalText
        let message = conversation.appendMessage(withText: messageText)!
    
        // then
        messageText.append("1234")
        XCTAssertEqual(message.textMessageData?.messageText, originalText)
    }
    
    func testThatInsertATextMessageWithNilTextDoesNotCreateANewMessage()
    {
        // given
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        conversation.remoteIdentifier = UUID()
        let start = self.uiMOC.insertedObjects
    
        // when
        var message: Any? = nil
        self.performIgnoringZMLogError {
            message = conversation.appendMessage(withText: nil)
        }
    
        // then
        XCTAssertNil(message)
        XCTAssertEqual(start, self.uiMOC.insertedObjects);
    }
    
    func testThatWeCanInsertAnImageMessageFromAFileURL()
    {
        // given
        let selfUser = ZMUser.selfUser(in: self.uiMOC)
        let imageFileURL = self.fileURL(forResource: "1900x1500", extension: "jpg")!
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        conversation.remoteIdentifier = UUID()
    
        // when
        let message = conversation.appendMessageWithImage(at: imageFileURL)! as! ZMAssetClientMessage
    
        // then
        XCTAssertNotNil(message)
        XCTAssertNotNil(message.nonce)
        XCTAssertTrue(message.imageMessageData!.originalSize.equalTo(CGSize(width: 1900, height: 1500)))
        XCTAssertEqual(message.conversation, conversation)
        XCTAssertTrue(conversation.messages.contains(message))
        XCTAssertNotNil(message.nonce)
        
        let expectedData = try! (try! Data(contentsOf: imageFileURL)).wr_removingImageMetadata()
        XCTAssertNotNil(expectedData)
        XCTAssertEqual(message.originalImageData(), expectedData)
        XCTAssertEqual(selfUser, message.sender)
    }
    
    func testThatNoMessageIsInsertedWhenTheImageFileURLIsPointingToSomethingThatIsNotAnImage()
    {
        // given
        let imageFileURL = self.fileURL(forResource: "1900x1500", extension: "jpg")!
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        conversation.remoteIdentifier = UUID()
    
        // when
        let message = conversation.appendMessageWithImage(at: imageFileURL)! as! ZMAssetClientMessage
    
        // then
        XCTAssertNotNil(message)
        XCTAssertNotNil(message.nonce)
        XCTAssertTrue(message.imageMessageData!.originalSize.equalTo(CGSize(width: 1900, height: 1500)))
        XCTAssertEqual(message.conversation, conversation)
        XCTAssertTrue(conversation.messages.contains(message))
        XCTAssertNotNil(message.nonce)
        
        let expectedData = try! (try! Data(contentsOf: imageFileURL)).wr_removingImageMetadata()
        XCTAssertNotNil(expectedData)
        XCTAssertEqual(message.originalImageData(), expectedData)
    }

    func testThatNoMessageIsInsertedWhenTheImageFileURLIsNotAFileURL()
    {
        // given
        let imageURL = URL(string:"http://www.placehold.it/350x150")!
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        conversation.remoteIdentifier = UUID()
        let start = self.uiMOC.insertedObjects
    
        // when
        var message: Any? = nil
        self.performIgnoringZMLogError {
            message = conversation.appendMessageWithImage(at: imageURL)
        }
    
        // then
        XCTAssertNil(message)
        XCTAssertEqual(start, self.uiMOC.insertedObjects)
    }

    func testThatNoMessageIsInsertedWhenTheImageFileURLIsNotPointingToAFile()
    {
        // given
        let textFileURL = self.fileURL(forResource: "Lorem Ipsum", extension: "txt")!
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        conversation.remoteIdentifier = UUID()
        let start = self.uiMOC.insertedObjects
    
        // when
        var message: Any? = nil
        self.performIgnoringZMLogError {
            message = conversation.appendMessageWithImage(at: textFileURL)
        }
    
        // then
        XCTAssertNil(message)
        XCTAssertEqual(start, self.uiMOC.insertedObjects);
    }

    func testThatWeCanInsertAnImageMessageFromImageData()
    {
        // given
        let imageData = try! self.data(forResource: "1900x1500", extension: "jpg").wr_removingImageMetadata()
        XCTAssertNotNil(imageData)
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        conversation.remoteIdentifier = UUID()
    
        // when
        guard let message = conversation.appendMessage(withImageData: imageData) as? ZMAssetClientMessage else {
            XCTFail()
            return
        }
    
        // then
        XCTAssertNotNil(message)
        XCTAssertNotNil(message.nonce)
        XCTAssertTrue(message.imageMessageData!.originalSize.equalTo(CGSize(width: 1900, height: 1500)))
        XCTAssertEqual(message.conversation, conversation)
        XCTAssertTrue(conversation.messages.contains(message))
        XCTAssertNotNil(message.nonce)
        XCTAssertEqual(message.originalImageData()!.count, imageData.count)
    }

    func testThatItIsSafeToPassInMutableDataWhenCreatingAnImageMessage()
    {
        // given
        let originalImageData = try! self.data(forResource: "1900x1500", extension: "jpg").wr_removingImageMetadata()
        var imageData = originalImageData
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        conversation.remoteIdentifier = UUID()
    
        // when
        guard let message = conversation.appendMessage(withImageData: imageData) as? ZMAssetClientMessage else {
            XCTFail()
            return
        }
        
        // then
        imageData.append(contentsOf: [1,2])
        XCTAssertEqual(message.originalImageData()!.count, originalImageData.count)
    }
    
    func testThatNoMessageIsInsertedWhenTheImageDataIsNotAnImage()
    {
        // given
        let textData = self.data(forResource: "Lorem Ipsum", extension: "txt")!
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        conversation.remoteIdentifier = UUID()
        let start = self.uiMOC.insertedObjects
    
        // when
        var message: ZMConversationMessage? = nil
        self.performIgnoringZMLogError {
            message = conversation.appendMessage(withImageData: textData)
        }

        // then
        XCTAssertNil(message)
        XCTAssertEqual(start, self.uiMOC.insertedObjects)
    }

    func testThatLastReadUpdatesInSelfConversationDontExpire()
    {
        self.syncMOC.performGroupedBlockAndWait {
            // given
            let conversation = ZMConversation.insertNewObject(in: self.syncMOC)
            conversation.remoteIdentifier = UUID()
            conversation.lastReadServerTimeStamp = Date()
            
            // when
            guard let message = ZMConversation.appendSelfConversation(withLastReadOf: conversation) else {
                XCTFail()
                return
            }
            
            // then
            XCTAssertNil(message.expirationDate)
        }
    }
    
    func testThatLastClearedUpdatesInSelfConversationDontExpire()
    {
        
        self.syncMOC.performGroupedBlockAndWait {
            // given
            let conversation = ZMConversation.insertNewObject(in: self.syncMOC)
            conversation.remoteIdentifier = UUID()
            conversation.clearedTimeStamp = Date()
            
            // when
            guard let message = ZMConversation.appendSelfConversation(withClearedOf: conversation) else {
                XCTFail()
                return
            }
            
            // then
            XCTAssertNil(message.expirationDate)
        }
    }

    func testThatWeCanInsertAFileMessage()
    {
        // given
        let documents = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        let fileURL = URL(fileURLWithPath: documents).appendingPathComponent("secret_file.txt")
        let data = Data.randomEncryptionKey()
        let size = data.count
        try! data.write(to: fileURL)
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        conversation.remoteIdentifier = UUID()

        // when
        let fileMetaData = ZMFileMetadata(fileURL: fileURL)
        let fileMessage = conversation.appendMessage(with: fileMetaData) as! ZMAssetClientMessage
    
        // then
        XCTAssertEqual(conversation.messages.count, 1)
        XCTAssertEqual(conversation.messages.firstObject as? ZMAssetClientMessage, fileMessage)
    
        XCTAssertTrue(fileMessage.isEncrypted)
        XCTAssertNotNil(fileMessage)
        XCTAssertNotNil(fileMessage.nonce)
        XCTAssertNotNil(fileMessage.fileMessageData)
        XCTAssertNotNil(fileMessage.genericAssetMessage)
        XCTAssertNil(fileMessage.assetId)
        XCTAssertNil(fileMessage.imageAssetStorage.previewGenericMessage)
        XCTAssertNil(fileMessage.imageAssetStorage.mediumGenericMessage)
        XCTAssertEqual(fileMessage.uploadState, .uploadingPlaceholder)
        XCTAssertFalse(fileMessage.delivered)
        XCTAssertTrue(fileMessage.hasDownloadedFile)
        XCTAssertEqual(fileMessage.size, UInt64(size))
        XCTAssertEqual(fileMessage.progress, 0)
        XCTAssertEqual(fileMessage.filename, "secret_file.txt")
        XCTAssertEqual(fileMessage.mimeType, "text/plain")
        XCTAssertFalse(fileMessage.fileMessageData!.isVideo)
        XCTAssertFalse(fileMessage.fileMessageData!.isAudio)
    }

    func testThatWeCanInsertALocationMessage()
    {
        // given
        let latitude = Float(48.53775)
        let longitude = Float(9.041169)
        let zoomLevel = Int32(16)
        let name = "天津市 နေပြည်တော် Test"
        let locationData = LocationData(latitude: latitude,
                                        longitude: longitude,
                                        name: name,
                                        zoomLevel: zoomLevel)
        
        // when
        self.syncMOC.performGroupedBlockAndWait {
            let conversation = ZMConversation.insertNewObject(in: self.syncMOC)
            conversation.remoteIdentifier = UUID()
            let message = conversation.appendMessage(with: locationData) as! ZMMessage
        
            XCTAssertEqual(conversation.messages.count, 1)
            XCTAssertEqual(conversation.messages.firstObject as? ZMMessage, message)
            XCTAssertTrue(message.isEncrypted)
    
            guard let locationMessageData = message.locationMessageData else {
                XCTFail()
                return
            }
            XCTAssertEqual(locationMessageData.longitude, longitude)
            XCTAssertEqual(locationMessageData.latitude, latitude)
            XCTAssertEqual(locationMessageData.zoomLevel, zoomLevel)
            XCTAssertEqual(locationMessageData.name, name)
        }
    }
    
    func testThatWeCanInsertAVideoMessage()
    {
        // given
        let fileName = "video.mp4"
        let documents = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        let fileURL = URL(fileURLWithPath: documents).appendingPathComponent(fileName)
        let videoData = Data.secureRandomData(length: 500)
        let thumbnailData = Data.secureRandomData(length: 250)
        let duration = 12333
        let dimensions = CGSize(width: 1900, height: 800)
        try! videoData.write(to: fileURL)
    
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        conversation.remoteIdentifier = UUID()

        // when
        let videoMetadata = ZMVideoMetadata(fileURL: fileURL,
                                            duration: TimeInterval(duration),
                                            dimensions: dimensions,
                                            thumbnail: thumbnailData)
        guard let fileMessage = conversation
            .appendMessage(with: videoMetadata) as? ZMAssetClientMessage
        else {
            XCTFail()
            return
        }
    
        // then
        XCTAssertEqual(conversation.messages.count, 1)
        XCTAssertEqual(conversation.messages.firstObject as? ZMAssetClientMessage, fileMessage)
    
        XCTAssertTrue(fileMessage.isEncrypted)
        XCTAssertNotNil(fileMessage)
        XCTAssertNotNil(fileMessage.nonce)
        XCTAssertNotNil(fileMessage.fileMessageData)
        XCTAssertNotNil(fileMessage.genericAssetMessage)
        XCTAssertNil(fileMessage.assetId)
        XCTAssertNil(fileMessage.imageAssetStorage.previewGenericMessage)
        XCTAssertNil(fileMessage.imageAssetStorage.mediumGenericMessage)
        XCTAssertEqual(fileMessage.uploadState, .uploadingPlaceholder)
        XCTAssertFalse(fileMessage.delivered)
        XCTAssertTrue(fileMessage.hasDownloadedFile)
        XCTAssertEqual(fileMessage.size, UInt64(videoData.count))
        XCTAssertEqual(fileMessage.progress, 0)
        XCTAssertEqual(fileMessage.filename, fileName)
        XCTAssertEqual(fileMessage.mimeType, "video/mp4")
        guard let fileMessageData = fileMessage.fileMessageData else {
            XCTFail()
            return
        }
        XCTAssertTrue(fileMessageData.isVideo)
        XCTAssertFalse(fileMessageData.isAudio)
        XCTAssertEqual(fileMessageData.durationMilliseconds, UInt64(duration * 1000))
        XCTAssertEqual(fileMessageData.videoDimensions.height, dimensions.height)
        XCTAssertEqual(fileMessageData.videoDimensions.width, dimensions.width)
    }
    
    func testThatWeCanInsertAnAudioMessage() {
        
        // given
        let fileName = "audio.m4a"
        let documents = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        let fileURL = URL(fileURLWithPath: documents).appendingPathComponent(fileName)
        let videoData = Data.secureRandomData(length: 500)
        let thumbnailData = Data.secureRandomData(length: 250)
        let duration = 12333
        try! videoData.write(to: fileURL)
        
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        conversation.remoteIdentifier = UUID()
        
        // when
        let audioMetadata = ZMAudioMetadata(fileURL: fileURL,
                                            duration: TimeInterval(duration),
                                            normalizedLoudness: [],
                                            thumbnail: thumbnailData)
        let fileMessage = conversation.appendMessage(with: audioMetadata) as! ZMAssetClientMessage
        
        // then
        XCTAssertEqual(conversation.messages.count, 1)
        XCTAssertEqual(conversation.messages.firstObject as? ZMAssetClientMessage, fileMessage)
        
        XCTAssertTrue(fileMessage.isEncrypted)
        XCTAssertNotNil(fileMessage)
        XCTAssertNotNil(fileMessage.nonce)
        XCTAssertNotNil(fileMessage.fileMessageData)
        XCTAssertNotNil(fileMessage.genericAssetMessage)
        XCTAssertNil(fileMessage.assetId)
        XCTAssertNil(fileMessage.imageAssetStorage.previewGenericMessage)
        XCTAssertNil(fileMessage.imageAssetStorage.mediumGenericMessage)
        XCTAssertEqual(fileMessage.uploadState, .uploadingPlaceholder)
        XCTAssertFalse(fileMessage.delivered)
        XCTAssertTrue(fileMessage.hasDownloadedFile)
        XCTAssertEqual(fileMessage.size, UInt64(videoData.count))
        XCTAssertEqual(fileMessage.progress, 0)
        XCTAssertEqual(fileMessage.filename, fileName)
        XCTAssertEqual(fileMessage.mimeType, "audio/x-m4a")
        guard let fileMessageData = fileMessage.fileMessageData else {
            XCTFail()
            return
        }
        XCTAssertFalse(fileMessageData.isVideo)
        XCTAssertTrue(fileMessageData.isAudio)
    }
}
