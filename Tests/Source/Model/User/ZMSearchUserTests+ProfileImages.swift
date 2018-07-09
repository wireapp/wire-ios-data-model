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

import XCTest

extension ZMSearchUserTests_ProfileImages: ZMManagedObjectContextProvider {
    
    var managedObjectContext: NSManagedObjectContext! {
        return uiMOC
    }
    
    var syncManagedObjectContext: NSManagedObjectContext! {
        return syncMOC
    }
    
}

class ZMSearchUserTests_ProfileImages: ZMBaseManagedObjectTest {
    
    func testThatItReturnsPreviewsProfileImageIfItWasPreviouslyUpdated() {
        // given
        let imageData = verySmallJPEGData()
        let searchUser = ZMSearchUser(contextProvider: self, name: "John", handle: "john", accentColor: .brightOrange, remoteIdentifier: UUID())
        
        // when
        searchUser.updateImageData(for: .preview, imageData: imageData)
        
        // then
        XCTAssertEqual(searchUser.previewImageData, imageData)
    }
    
    func testThatItReturnsCompleteProfileImageIfItWasPreviouslyUpdated() {
        // given
        let imageData = verySmallJPEGData()
        let searchUser = ZMSearchUser(contextProvider: self, name: "John", handle: "john", accentColor: .brightOrange, remoteIdentifier: UUID())
        
        // when
        searchUser.updateImageData(for: .complete, imageData: imageData)
        
        // then
        XCTAssertEqual(searchUser.completeImageData, imageData)
    }
    
    func testThatItReturnsPreviewsProfileImageFromAssociatedUserIfPossible() {
        // given
        let imageData = verySmallJPEGData()
        let user = ZMUser.insertNewObject(in: uiMOC)
        user.remoteIdentifier = UUID.create()
        user.smallProfileRemoteIdentifier = UUID.create()
        user.imageSmallProfileData = imageData
        uiMOC.saveOrRollback()
        
        // when
        let searchUser = ZMSearchUser(contextProvider: self, user: user)
        
        // then
        XCTAssertEqual(searchUser.previewImageData, imageData)
    }
    
    func testThatItReturnsPreviewsCompleteImageFromAssociatedUserIfPossible() {
        // given
        let imageData = verySmallJPEGData()
        let user = ZMUser.insertNewObject(in: uiMOC)
        user.remoteIdentifier = UUID.create()
        user.mediumRemoteIdentifier = UUID.create()
        user.imageMediumData = imageData
        uiMOC.saveOrRollback()
        
        // when
        let searchUser = ZMSearchUser(contextProvider: self, user: user)
        
        // then
        XCTAssertEqual(searchUser.completeImageData, imageData)
    }
    
    func testThatItReturnsPreviewImageProfileCacheKey() {
        // given
        let searchUser = ZMSearchUser(contextProvider: self, name: "John", handle: "john", accentColor: .brightOrange, remoteIdentifier: UUID.create())
        
        // then
        XCTAssertNotNil(searchUser.smallProfileImageCacheKey)
    }
    
    func testThatItReturnsCompleteImageProfileCacheKey() {
        // given
        let searchUser = ZMSearchUser(contextProvider: self, name: "John", handle: "john", accentColor: .brightOrange, remoteIdentifier: UUID.create())
        
        // then
        XCTAssertNotNil(searchUser.mediumProfileImageCacheKey)
    }
    
    func testThatItPreviewAndCompleteImageProfileCacheKeyIsDifferent() {
        // given
        let searchUser = ZMSearchUser(contextProvider: self, name: "John", handle: "john", accentColor: .brightOrange, remoteIdentifier: UUID.create())
        
        // then
        XCTAssertNotEqual(searchUser.smallProfileImageCacheKey, searchUser.mediumProfileImageCacheKey)
    }
    
    func testThatItReturnsPreviewImageProfileCacheKeyFromUserIfPossible() {
        // given
        let imageData = verySmallJPEGData()
        let user = ZMUser.insertNewObject(in: uiMOC)
        user.remoteIdentifier = UUID.create()
        user.smallProfileRemoteIdentifier = UUID.create()
        user.imageSmallProfileData = imageData
        uiMOC.saveOrRollback()
        
        // given
        let searchUser = ZMSearchUser(contextProvider: self, user: user)
        
        // then
        XCTAssertNotNil(searchUser.smallProfileImageCacheKey)
        XCTAssertEqual(user.smallProfileImageCacheKey, searchUser.smallProfileImageCacheKey)
    }
    
    func testThatItReturnsCompleteImageProfileCacheKeyFromUserIfPossible() {
        // given
        let imageData = verySmallJPEGData()
        let user = ZMUser.insertNewObject(in: uiMOC)
        user.remoteIdentifier = UUID.create()
        user.mediumRemoteIdentifier = UUID.create()
        user.imageMediumData = imageData
        uiMOC.saveOrRollback()
        
        // given
        let searchUser = ZMSearchUser(contextProvider: self, user: user)
        
        // then
        XCTAssertNotNil(searchUser.mediumProfileImageCacheKey)
        XCTAssertEqual(user.mediumProfileImageCacheKey, searchUser.mediumProfileImageCacheKey)
    }
    
    func testThatItCanFetchPreviewProfileImageOnAQueue() {
        // given
        let imageData = verySmallJPEGData()
        let searchUser = ZMSearchUser(contextProvider: self, name: "John", handle: "john", accentColor: .brightOrange, remoteIdentifier: UUID())
        
        // when
        searchUser.updateImageData(for: .preview, imageData: imageData)
        
        // then
        let imageDataArrived = expectation(description: "completion handler called")
        searchUser.imageData(for: .preview, queue: .global()) { (imageDataResult) in
            XCTAssertEqual(imageData, imageDataResult)
            imageDataArrived.fulfill()
        }
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
        
    }
    func testThatItCanFetchCompleteProfileImageOnAQueue() {
        // given
        let imageData = verySmallJPEGData()
        let searchUser = ZMSearchUser(contextProvider: self, name: "John", handle: "john", accentColor: .brightOrange, remoteIdentifier: UUID())
        
        // when
        searchUser.updateImageData(for: .complete, imageData: imageData)
        
        // then
        let imageDataArrived = expectation(description: "completion handler called")
        searchUser.imageData(for: .complete, queue: .global()) { (imageDataResult) in
            XCTAssertEqual(imageData, imageDataResult)
            imageDataArrived.fulfill()
        }
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
    }
    
}
