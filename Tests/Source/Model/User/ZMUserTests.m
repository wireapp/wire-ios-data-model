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

@import WireUtilities;

#import "ZMUserTests.h"
#import "ModelObjectsTests.h"

#import "ZMUser+Internal.h"
#import "ZMManagedObject+Internal.h"
#import "NSManagedObjectContext+zmessaging.h"
#import "ZMConnection+Internal.h"


static NSString * const InvitationToConnectBaseURL = @"https://www.wire.com/c/";

static NSString *const ValidPhoneNumber = @"+491234567890";
static NSString *const ShortPhoneNumber = @"+491";
static NSString *const LongPhoneNumber = @"+4912345678901234567890";
static NSString *const ValidPassword = @"pA$$W0Rd";
static NSString *const ShortPassword = @"pa";
static NSString *const LongPassword =
@"ppppppppppppaaaaaaaaaaassssssssswwwwwwwwwwoooooooooooorrrrrrrrrddddddddddddddd"
"ppppppppppppaaaaaaaaaaassssssssswwwwwwwwwwoooooooooooorrrrrrrrrddddddddddddddd"
"ppppppppppppaaaaaaaaaaassssssssswwwwwwwwwwoooooooooooorrrrrrrrrddddddddddddddd"
"ppppppppppppaaaaaaaaaaassssssssswwwwwwwwwwoooooooooooorrrrrrrrrddddddddddddddd";
static NSString *const ValidPhoneCode = @"123456";
static NSString *const ShortPhoneCode = @"1";
static NSString *const LongPhoneCode = @"123456789012345678901234567890";
static NSString *const ValidEmail = @"foo77@example.com";


static NSString *const MediumRemoteIdentifierDataKey = @"mediumRemoteIdentifier_data";
static NSString *const SmallProfileRemoteIdentifierDataKey = @"smallProfileRemoteIdentifier_data";
static NSString *const ImageMediumDataKey = @"imageMediumData";
static NSString *const ImageSmallProfileDataKey = @"imageSmallProfileData";

@interface ZMUserTests()

@property (nonatomic) NSArray *validPhoneNumbers;
@property (nonatomic) NSArray *shortPhoneNumbers;
@property (nonatomic) NSArray *longPhoneNumbers;

@end


@interface ZMUserTestsUseSQLLiteStore : ModelObjectsTests

@end


@implementation ZMUserTests

-(void)setUp
{
    [super setUp];
    self.validPhoneNumbers = @[@"+491621312533", @"+4901756698655", @"+49 152 22824948", @"+49 157 71898972", @"+49 176 35791100", @"+49 1721496444", @"+79263387698", @"+79160546401", @"+7(927)674-59-42", @"+71231234567", @"+491234567890123456", @"+49123456789012345678901", @"+49123456"];
    self.shortPhoneNumbers = @[@"+", @"4", @"+4", @"+49", @"+491", @"+4912", @"+49123", @"+491234", @"+491235"];
    self.longPhoneNumbers = @[@"+491234567890123456789015", @"+4912345678901234567890156"];
    
    UserImageLocalCache *userImageCache = [[UserImageLocalCache alloc] initWithLocation:nil];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        self.syncMOC.zm_userImageCache = userImageCache;
    }];
    
    self.uiMOC.zm_userImageCache = userImageCache;
}

- (void)tearDown
{
    self.validPhoneNumbers = nil;
    self.shortPhoneNumbers = nil;
    self.longPhoneNumbers = nil;
    [super tearDown];
}

- (void)testThatItHasLocallyModifiedDataFields
{
    XCTAssertTrue([ZMUser isTrackingLocalModifications]);
    NSEntityDescription *entity = self.uiMOC.persistentStoreCoordinator.managedObjectModel.entitiesByName[ZMUser.entityName];
    XCTAssertNotNil(entity.attributesByName[@"modifiedKeys"]);
}

- (void)testThatWeCanSetAttributesOnUser
{
    [self checkUserAttributeForKey:@"accentColorValue" value:@(ZMAccentColorVividRed)];
    [self checkUserAttributeForKey:@"emailAddress" value:@"foo@example.com"];

    [self checkUserAttributeForKey:@"name" value:@"Foo Bar"];
    [self checkUserAttributeForKey:@"handle" value:@"foo_bar"];
    [self checkUserAttributeForKey:@"phoneNumber" value:@"+123456789"];
    [self checkUserAttributeForKey:@"remoteIdentifier" value:[NSUUID createUUID]];
    [self checkUserAttributeForKey:@"mediumRemoteIdentifier" value:[NSUUID createUUID]];
    [self checkUserAttributeForKey:@"localMediumRemoteIdentifier" value:[NSUUID createUUID]];
    [self checkUserAttributeForKey:@"localSmallProfileRemoteIdentifier" value:[NSUUID createUUID]];
}

- (NSMutableDictionary *)samplePayloadForUserID:(NSUUID *)userID
{
    return [@{
              @"name" : @"Manuel Rodriguez",
              @"id" : userID.transportString,
              @"handle" : @"el_manu",
              @"email" : @"mannie@example.com",
              @"phone" : @"000-000-45789",
              @"accent_id" : @3,
              @"picture" : @[]
              } mutableCopy];
}

- (void)checkUserAttributeForKey:(NSString *)key value:(id)value;
{
    [self checkAttributeForClass:[ZMUser class] key:key value:value];
}

- (void)testThatItReturnsAnExistingUserByUUID
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    NSUUID *uuid = [NSUUID createUUID];
    user.remoteIdentifier = uuid;

    // when
    ZMUser *found = [ZMUser userWithRemoteID:uuid createIfNeeded:false inContext:self.uiMOC];

    // then
    XCTAssertEqualObjects(found.remoteIdentifier, uuid);
    XCTAssertEqualObjects(found.objectID, user.objectID);
}

- (void)testThatItDoesNotReturnANonExistingUserByUUID
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    NSUUID *uuid = [NSUUID createUUID];
    NSUUID *secondUUID = [NSUUID createUUID];

    user.remoteIdentifier = uuid;

    // when
    ZMUser *found = [ZMUser userWithRemoteID:secondUUID createIfNeeded:NO inContext:self.uiMOC];

    // then
    XCTAssertNil(found);
}

- (void)testThatItCreatesAUserForNonExistingUUID
{
    // given
    NSUUID *uuid = [NSUUID createUUID];

    [self.syncMOC performBlockAndWait:^{
        // when
        ZMUser *found = [ZMUser userWithRemoteID:uuid createIfNeeded:YES inContext:self.syncMOC];
        
        // then
        XCTAssertNotNil(found);
        XCTAssertEqualObjects(uuid, found.remoteIdentifier);
    }];
}


- (void)testThatItReturnsAnExistingUserByPhone
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    NSString *phoneNumber = @"+123456789";
    user.phoneNumber = phoneNumber;
    
    // when
    ZMUser *found = [ZMUser userWithPhoneNumber:phoneNumber inContext:self.uiMOC];
    
    // then
    XCTAssertEqualObjects(found.phoneNumber, phoneNumber);
    XCTAssertEqualObjects(found.objectID, user.objectID);
}

- (void)testThatItDoesNotReturnANonExistingUserByPhone
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    NSString *phoneNumber = @"+123456789";
    user.phoneNumber = phoneNumber;
    
    NSString *otherPhoneNumber = @"+987654321";
    
    // when
    ZMUser *found = [ZMUser userWithPhoneNumber:otherPhoneNumber inContext:self.uiMOC];
    
    // then
    XCTAssertNil(found);
}

- (void)testThatItReturnsAnExistingUserByEmail
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    NSString *emailAddress = @"test@test.com";
    user.emailAddress = emailAddress;
    
    // when
    ZMUser *found = [ZMUser userWithEmailAddress:emailAddress inContext:self.uiMOC];
    
    // then
    XCTAssertEqualObjects(found.emailAddress, emailAddress);
    XCTAssertEqualObjects(found.objectID, user.objectID);
}

- (void)testThatItDoesNotReturnANonExistingUserByEmail
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    NSString *emailAddress = @"east@test.com";
    user.emailAddress = emailAddress;
    
    NSString *otherEmailAddress = @"west@test.com";
    
    // when
    ZMUser *found = [ZMUser userWithEmailAddress:otherEmailAddress inContext:self.uiMOC];
    
    // then
    XCTAssertNil(found);
}

- (void)testThatItUpdatesBasicDataOnAnExistingUser
{
    // given
    NSUUID *uuid = [NSUUID createUUID];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = uuid;

    NSMutableDictionary *payload = [self samplePayloadForUserID:uuid];
    
    // when
    [user updateWithTransportData:payload authoritative:NO];

    // then
    XCTAssertEqualObjects(user.name, payload[@"name"]);
    XCTAssertEqualObjects(user.emailAddress, payload[@"email"]);
    XCTAssertEqualObjects(user.phoneNumber, payload[@"phone"]);
    XCTAssertEqualObjects(user.handle, payload[@"handle"]);
    XCTAssertEqual(user.accentColorValue, ZMAccentColorBrightYellow);
}

- (void)testThatItUpdatesBasicDataOnAnExistingUserWithoutAccentID
{
    // given
    NSUUID *uuid = [NSUUID createUUID];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = uuid;
    
    NSMutableDictionary *payload = [self samplePayloadForUserID:uuid];
    [payload removeObjectForKey:@"accent_id"];
    
    // when
    [user updateWithTransportData:payload authoritative:NO];
    
    // then
    XCTAssertEqualObjects(user.name, payload[@"name"]);
    XCTAssertEqualObjects(user.emailAddress, payload[@"email"]);
    XCTAssertEqualObjects(user.phoneNumber, payload[@"phone"]);
    XCTAssertEqualObjects(user.handle, payload[@"handle"]);
}


- (void)testThatItUpdatesBasicDataOnAnExistingUserWithoutPicture
{
    // given
    NSUUID *uuid = [NSUUID createUUID];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = uuid;
    
    NSMutableDictionary *payload = [self samplePayloadForUserID:uuid];
    [payload removeObjectForKey:@"picture"];
    
    // when
    [user updateWithTransportData:payload authoritative:NO];
    
    // then
    XCTAssertEqualObjects(user.name, payload[@"name"]);
    XCTAssertEqualObjects(user.emailAddress, payload[@"email"]);
    XCTAssertEqualObjects(user.phoneNumber, payload[@"phone"]);
    XCTAssertEqualObjects(user.handle, payload[@"handle"]);
}


- (void)testThatItLimitsAccentColorsToValidRangeForUdpateData_TooLarge;
{
    // given
    NSUUID *remoteID = [NSUUID createUUID];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = remoteID;
    
    NSMutableDictionary *payload = [self samplePayloadForUserID:remoteID];
    payload[@"accent_id"] = @(ZMAccentColorMax + 1);
    
    // when
    [user updateWithTransportData:payload authoritative:NO];
    
    // then
    XCTAssertGreaterThan(user.accentColorValue, ZMAccentColorUndefined);
    XCTAssertLessThanOrEqual(user.accentColorValue, ZMAccentColorMax);
}

- (void)testThatItLimitsAccentColorsToValidRangeForUdpateData_Undefined;
{
    // given
    NSUUID *remoteID = [NSUUID createUUID];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = remoteID;
    
    NSMutableDictionary *payload = [self samplePayloadForUserID:remoteID];
    payload[@"accent_id"] = @(ZMAccentColorUndefined);
    
    // when
    [user updateWithTransportData:payload authoritative:NO];
    
    // then
    XCTAssertGreaterThan(user.accentColorValue, ZMAccentColorUndefined);
    XCTAssertLessThanOrEqual(user.accentColorValue, ZMAccentColorMax);
}

- (void)testThatItUpdatesAUsersMediumImageData
{
    // given
    NSUUID *uuid = [NSUUID createUUID];
    NSUUID *mediumImageRemoteID = [NSUUID createUUID];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = uuid;

    NSDictionary *previewImage = @{
        @"content_length" : @3460,
        @"data" : @"image-data-asodijaslkdna987u3sdfjklknmqweosdiuflkqwneljoijldkjalsdjoaisudlkasndlkasjdoiau",
        @"content_type" : @"image/webp",
        @"id" : @"f287d599-7c89-5322-8a81-e7a7144584f2",
        @"info" : @{
            @"height" : @148,
            @"tag" : @"preview",
            @"original_width" : @600,
            @"width" : @114,
            @"correlation_id" : @"e6810025c-1bef-ee0f-8605e1ca-9511317",
            @"original_height" : @774,
            @"nonce" : @"89163ee37-dba5-0bfa-d7cc2b3c-dfe9abc",
            @"public" : @true
        }
    };

    NSDictionary *mediumImage = @{
                                  @"content_length" : @51128,
                                  @"data" : @"",
                                  @"content_type" : @"image/webp",
                                  @"id" : mediumImageRemoteID.transportString,
                                  @"info" : @{
                                          @"height" : @774,
                                          @"tag" : @"medium",
                                          @"original_width" : @600,
                                          @"width" : @600,
                                          @"correlation_id" : @"e6810025c-1bef-ee0f-8605e1ca-9511317",
                                          @"original_height" : @774,
                                          @"nonce" : @"8202b5ee6-04a3-8bb8-c83ce7a7-7fa8d79",
                                          @"public" : @true
                                          }
                                  };
    NSMutableDictionary *payload = [self samplePayloadForUserID:uuid];
    payload[@"picture"] = @[mediumImage, previewImage];

    // when
    [user updateWithTransportData:payload authoritative:NO];

    // then
    XCTAssertNil(user.imageMediumData); // Medium image will get downloaded by ZMUserImageTranscoder
    XCTAssertEqualObjects(user.mediumRemoteIdentifier, mediumImageRemoteID);
    XCTAssertNil(user.localMediumRemoteIdentifier, @"Must not be set");
    XCTAssertNil(user.localSmallProfileRemoteIdentifier, @"Must not be set");
}


- (void)testThatItUpdatesAUsersSmallProfileImageData
{
    // given
    NSUUID *uuid = [NSUUID createUUID];
    NSUUID *smallProfileImageRemoteID = [NSUUID createUUID];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = uuid;
    
    NSDictionary *smallProfileImage = @{
                                   @"content_length" : @3460,
                                   @"data" : @"image-data-asodijaslkdna987u3sdfjklknmqweosdiuflkqwneljoijldkjalsdjoaisudlkasndlkasjdoiau",
                                   @"content_type" : @"image/webp",
                                   @"id" : smallProfileImageRemoteID.transportString,
                                   @"info" : @{
                                           @"height" : @148,
                                           @"tag" : @"smallProfile",
                                           @"original_width" : @600,
                                           @"width" : @114,
                                           @"correlation_id" : @"e6810025c-1bef-ee0f-8605e1ca-9511317",
                                           @"original_height" : @774,
                                           @"nonce" : @"89163ee37-dba5-0bfa-d7cc2b3c-dfe9abc",
                                           @"public" : @true
                                           }
                                   };
    
    NSDictionary *mediumImage = @{
                                  @"content_length" : @51128,
                                  @"data" : @"",
                                  @"content_type" : @"image/webp",
                                  @"id" : @"f287d599-7c89-5322-8a81-e7a7144584f2",
                                  @"info" : @{
                                          @"height" : @774,
                                          @"tag" : @"medium",
                                          @"original_width" : @600,
                                          @"width" : @600,
                                          @"correlation_id" : @"e6810025c-1bef-ee0f-8605e1ca-9511317",
                                          @"original_height" : @774,
                                          @"nonce" : @"8202b5ee6-04a3-8bb8-c83ce7a7-7fa8d79",
                                          @"public" : @true
                                          }
                                  };
    NSMutableDictionary *payload = [self samplePayloadForUserID:uuid];
    payload[@"picture"] = @[mediumImage, smallProfileImage];
    
    // when
    [user updateWithTransportData:payload authoritative:NO];
    
    // then
    XCTAssertNil(user.imageSmallProfileData); // Small profile image will get downloaded by ZMUserImageTranscoder
    XCTAssertEqualObjects(user.smallProfileRemoteIdentifier, smallProfileImageRemoteID);
    XCTAssertNil(user.localSmallProfileRemoteIdentifier, @"Must not be set");
    XCTAssertNil(user.localMediumRemoteIdentifier, @"Must not be set");
}

- (void)testThatItDoesPersistMediumImageDataForNotSelfUserToCache
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = [NSUUID createUUID];
    user.mediumRemoteIdentifier = [NSUUID createUUID];
    NSData *imageData = [self verySmallJPEGData];
    user.imageMediumData = imageData;
    XCTAssertEqualObjects(user.imageMediumData, imageData);
    
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.syncMOC saveOrRollback];
    }];
    
    //when
    NSData* extractedData = [self.uiMOC.zm_userImageCache userImage:user size:ProfileImageSizeComplete];
    
    //then
    XCTAssertEqualObjects(imageData, extractedData);
}

- (void)testThatItDoesPersistSmallImageDataForNotSelfUserToCache
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = [NSUUID createUUID];
    user.smallProfileRemoteIdentifier = [NSUUID createUUID];
    NSData *imageData = [self verySmallJPEGData];
    user.imageSmallProfileData = imageData;
    XCTAssertEqualObjects(user.imageSmallProfileData, imageData);
    
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.syncMOC saveOrRollback];
    }];
    
    //when
    NSData* extractedData = [self.uiMOC.zm_userImageCache userImage:user size:ProfileImageSizePreview];
    
    //then
    XCTAssertEqualObjects(imageData, extractedData);
}

- (void)testThatItDoesNotStoreMediumImageDataInCacheForSelfUser
{
    // given
    ZMUser *user = [ZMUser selfUserInContext:self.uiMOC];
    user.remoteIdentifier = [NSUUID createUUID];
    user.mediumRemoteIdentifier = [NSUUID createUUID];
    NSData *imageData = [self verySmallJPEGData];
    user.imageMediumData = imageData;
    XCTAssertEqualObjects(user.imageMediumData, imageData);
    
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.syncMOC saveOrRollback];
    }];
    
    //when
    NSData* extractedData = [self.uiMOC.zm_userImageCache userImage:user size:ProfileImageSizeComplete];
    
    //then
    XCTAssertNil(extractedData);
}

- (void)testThatItHandlesRemovingPictures
{
    // given
    NSUUID *uuid = [NSUUID createUUID];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = uuid;
    user.smallProfileRemoteIdentifier = [NSUUID createUUID];
    user.mediumRemoteIdentifier = [NSUUID createUUID];
    user.imageSmallProfileData = [self dataForResource:@"tiny" extension:@"jpg"];
    user.imageMediumData = [self dataForResource:@"tiny" extension:@"jpg"];
    
    NSMutableDictionary *payload = [self samplePayloadForUserID:uuid];
    payload[@"picture"] = @[];
    
    // when
    [user updateWithTransportData:payload authoritative:NO];
    
    // then
    XCTAssertNil(user.imageSmallProfileData);
    XCTAssertEqualObjects(user.imageSmallProfileIdentifier, @"");
    XCTAssertNil(user.imageMediumData);
    XCTAssertNil(user.mediumRemoteIdentifier);
    XCTAssertNil(user.smallProfileRemoteIdentifier);
}

- (void)testThatItHandlesEmptyOptionalData
{
    // given
    NSUUID *uuid = [NSUUID createUUID];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = uuid;

    NSMutableDictionary *payload = [self samplePayloadForUserID:uuid];
    [payload removeObjectForKey:@"phone"];
    [payload removeObjectForKey:@"accent_id"];

    // when
    [self performIgnoringZMLogError:^{
        [user updateWithTransportData:payload authoritative:NO];
    }];
    
    // then
    XCTAssertNil(user.phoneNumber);
}


- (void)testThatItSetsNameToNilIfItIsMissing
{
    // given
    NSUUID *uuid = [NSUUID createUUID];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = uuid;
    user.name =  @"Mario";
    
    NSMutableDictionary *payload = [self samplePayloadForUserID:uuid];
    [payload removeObjectForKey:@"name"];

    // when
    [self performIgnoringZMLogError:^{
        [user updateWithTransportData:payload authoritative:YES];
    }];
    // then
    XCTAssertNil(user.name);
}

- (void)testThatTheEmailIsCopied
{
    // given
    NSString *originalValue = @"will@foo.co";
    NSMutableString *mutableValue = [originalValue mutableCopy];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    
    // when
    user.emailAddress = mutableValue;
    [mutableValue appendString:@".uk"];
    
    // then
    XCTAssertEqualObjects(user.emailAddress, originalValue);
}

- (void)testThatItSetsEmailToNilIfItIsNull
{
    // given
    NSUUID *uuid = [NSUUID createUUID];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = uuid;
    user.emailAddress =  @"gino@pino.it";
    
    NSMutableDictionary *payload = [self samplePayloadForUserID:uuid];
    [payload setObject:[NSNull null] forKey:@"email"];
    
    // when
    [user updateWithTransportData:payload authoritative:NO];
    
    // then
    XCTAssertNil(user.emailAddress);
}

- (void)testThatItSetsEmailToNilIfItIsMissing
{
    // given
    NSUUID *uuid = [NSUUID createUUID];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = uuid;
    user.emailAddress =  @"gino@pino.it";

    NSMutableDictionary *payload = [self samplePayloadForUserID:uuid];
    [payload removeObjectForKey:@"email"];
    
    // when
    [user updateWithTransportData:payload authoritative:YES];

    // then
    XCTAssertNil(user.emailAddress);
}

- (void)testThatItSetsPhoneToNilIfItIsNull
{
    // given
    NSUUID *uuid = [NSUUID createUUID];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = uuid;
    user.phoneNumber =  @"555-fake-number";
    
    NSMutableDictionary *payload = [self samplePayloadForUserID:uuid];
    [payload setObject:[NSNull null] forKey:@"phone"];
    
    // when
    [user updateWithTransportData:payload authoritative:NO];
    
    // then
    XCTAssertNil(user.phoneNumber);
}

- (void)testThatItSetsPhoneToNilIfItIsMissing
{
    // given
    NSUUID *uuid = [NSUUID createUUID];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = uuid;
    user.phoneNumber =  @"555-fake-number";
    
    NSMutableDictionary *payload = [self samplePayloadForUserID:uuid];
    [payload removeObjectForKey:@"phone"];
    
    // when
    [user updateWithTransportData:payload authoritative:YES];
    
    // then
    XCTAssertNil(user.phoneNumber);
}

- (void)testThatThePhoneNumberIsCopied
{
    // given
    NSString *originalValue = @"+1-555-324545";
    NSMutableString *mutableValue = [originalValue mutableCopy];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    
    // when
    user.phoneNumber = mutableValue;
    [mutableValue appendString:@"8"];
    
    // then
    XCTAssertEqualObjects(user.phoneNumber, originalValue);
}

- (void)testThatItAssignsRemoteIdentifierIfTheUserDoesNotHaveOne
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    NSDictionary *payload = [self samplePayloadForUserID:[NSUUID createUUID]];
    
    // when
    [user updateWithTransportData:payload authoritative:YES];

    // then
    XCTAssertEqualObjects(user.remoteIdentifier, [payload[@"id"] UUID]);
}

- (void)testThatItIsMarkedAsUpdatedFromBackendWhenUpdatingWithAuthoritativeData
{

    // given
    NSUUID *uuid = [NSUUID createUUID];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = uuid;

    NSDictionary *userData = [self samplePayloadForUserID:uuid];

    // when
    [user updateWithTransportData:userData authoritative:YES];

    // then
    XCTAssertFalse(user.needsToBeUpdatedFromBackend);
}


- (void)testThatIsNotMarkedAsUpdatedFromBackendWhenUpdatingWithNonAuthoritativeData
{
    // given
    NSUUID *uuid = [NSUUID createUUID];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = uuid;
    XCTAssertTrue(user.needsToBeUpdatedFromBackend);
    
    NSDictionary *userData = [self samplePayloadForUserID:uuid];

    // when
    [user updateWithTransportData:userData authoritative:NO];

    // then
    XCTAssertTrue(user.needsToBeUpdatedFromBackend);
}

- (void)testThatWhenNonAuthoritativeIsMissingDataFieldsThoseAreNotSetToNil
{
    
    //given
    NSString *name = @"Jean of Arc";
    NSString *email = @"jj@arc.example.com";
    NSString *phone = @"+33 11111111111";
    NSString *handle = @"st_jean";
    
    NSUUID *uuid = [NSUUID createUUID];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = uuid;
    user.emailAddress =  email;
    user.name = name;
    user.handle = handle;
    user.phoneNumber = phone;
    
    NSDictionary *payload = @{
                              @"id": [uuid transportString]
                              };
    
    // when
    [self performIgnoringZMLogError:^{
        [user updateWithTransportData:payload authoritative:NO];
    }];
    
    // then
    XCTAssertEqualObjects(name, user.name);
    XCTAssertEqualObjects(email, user.emailAddress);
    XCTAssertEqualObjects(phone, user.phoneNumber);
    XCTAssertEqualObjects(handle, user.handle);
}

- (void)testThatOnInvalidJSonDataTheUserIsMarkedAsComplete
{
    // given
    NSUUID *uuid = [NSUUID createUUID];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = uuid;
    XCTAssertTrue(user.needsToBeUpdatedFromBackend);

    NSDictionary *payload = @{@"id":[uuid transportString]};
    
    // when
    [self performIgnoringZMLogError:^{
        [user updateWithTransportData:payload authoritative:YES];
    }];
    
    // then
    XCTAssertFalse(user.needsToBeUpdatedFromBackend);
}


- (void)testThatOnInvalidJSonFormatItDoesNotCrash
{
    // given
    NSUUID *uuid = [NSUUID createUUID];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = uuid;
    XCTAssertTrue(user.needsToBeUpdatedFromBackend);
    
    NSDictionary *payload = @{
          @"name" : @6,
          @"id" : [uuid transportString],
          @"email" : @8,
          @"phone" : @5,
          @"accent" : @"boo",
          @"accent_id" : @"foo",
          @"picture" : @55
          };
    
    // when
    [self performIgnoringZMLogError:^{
        [user updateWithTransportData:payload authoritative:YES];
    }];
    
    // then
    XCTAssertFalse(user.needsToBeUpdatedFromBackend);
}

- (void)testPerformanceOfRetrievingSelfUser;
{
    [self measureBlock:^{
        for (size_t i = 0; i < 100000; ++i) {
            (void) [ZMUser selfUserInContext:self.uiMOC];
        }
    }];
}

- (void)testThatItCreatesSessionAndSelfUserCorrectly
{
    //make sure to clear store metadata
    [self.uiMOC setPersistentStoreMetadata:nil forKey:@"SelfUserObjectID"];
    [self.uiMOC setPersistentStoreMetadata:nil forKey:@"SessionObjectID"];
    
    //reset all contexts
    [self resetUIandSyncContextsAndResetPersistentStore:YES];
    WaitForAllGroupsToBeEmpty(0.5);

    [self checkSelfUserIsCreatedCorrectlyInContext:self.uiMOC];
    [self.syncMOC performGroupedBlockAndWait:^{
        [self checkSelfUserIsCreatedCorrectlyInContext:self.syncMOC];
    }];
    
    //when
    // request again
    ZMUser *uiUser = [ZMUser selfUserInContext:self.uiMOC];
    __block NSManagedObjectID *syncUserObjectID = nil;
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMUser *syncUser = [ZMUser selfUserInContext:self.syncMOC];
        syncUserObjectID = syncUser.objectID;
    }];
    
    //then
    //Check that the same object is returned
    XCTAssertEqualObjects(uiUser.objectID, syncUserObjectID);
}

- (void)checkSelfUserIsCreatedCorrectlyInContext:(NSManagedObjectContext *)moc
{
    [moc performGroupedBlockAndWait:^{

        //when
        //context is just created
        
        //then
        //check that self user is already created
        NSArray *users = [moc executeFetchRequestOrAssert:[ZMUser sortedFetchRequest]];

        //check that only one user created
        XCTAssertEqual(users.count, 1u);
        ZMUser *selfUser = users.firstObject;
        
        XCTAssertFalse(selfUser.objectID.isTemporaryID);
        
        //check that only one session is created
        NSArray *sessions = [moc executeFetchRequestOrAssert:[ZMSession sortedFetchRequest]];
        XCTAssertEqual(sessions.count, 1u);
        
        //check that session stores user
        ZMSession *session = sessions.firstObject;
        XCTAssertEqual(session.selfUser, selfUser);
        
        //check that we don't store id's by old keys
        XCTAssertNil(moc.userInfo[@"ZMSelfUserManagedObjectID"]);
        XCTAssertNil([moc persistentStoreMetadataForKey:@"SelfUserObjectID"]);
        
        //check that we store session id in user info and metadata
        NSString *moidString = [moc persistentStoreMetadataForKey:@"SessionObjectID"];
        NSURL *moidURL = [NSURL URLWithString:moidString];
        NSManagedObjectID *moid = [moc.persistentStoreCoordinator managedObjectIDForURIRepresentation:moidURL];
        
        //check that we store id's correctly
        XCTAssertEqualObjects(moc.userInfo[@"ZMSessionManagedObjectID"], session.objectID);
        XCTAssertEqualObjects(moid, session.objectID);
        XCTAssertFalse(session.objectID.isTemporaryID);
        
        //check that boxed user is stored in user info
        XCTAssertNotNil(moc.userInfo[@"ZMSelfUser"]);
        
        //when
        //request again
        ZMUser *user = [ZMUser selfUserInContext:moc];
        
        //then
        //check that the same user is returned
        XCTAssertEqualObjects(user, selfUser);
        
        //check that no new session and user is created
        sessions = [moc executeFetchRequestOrAssert:[ZMSession sortedFetchRequest]];
        XCTAssertEqual(sessions.count, 1u);
        users = [moc executeFetchRequestOrAssert:[ZMUser sortedFetchRequest]];
        XCTAssertEqual(users.count, 1u);
    }];
}

- (void)testThatItMatchesObjectsThatNeedToBeUpdatedUpstream
{
    // given
    ZMUser *user = [ZMUser selfUserInContext:self.uiMOC];
    NSPredicate *sut = [ZMUser predicateForObjectsThatNeedToBeUpdatedUpstream];
    
    // when
    [user resetLocallyModifiedKeys:[user keysThatHaveLocalModifications]];
    user.needsToBeUpdatedFromBackend = NO;
    
    // then
    XCTAssertFalse([sut evaluateWithObject:user]);
    
    // when
    [user setLocallyModifiedKeys:[NSSet setWithObject:@"name"]];
    // then
    XCTAssertTrue([sut evaluateWithObject:user]);
    
    // when
    [user resetLocallyModifiedKeys:[user keysThatHaveLocalModifications]];
    // then
    XCTAssertFalse([sut evaluateWithObject:user]);
}

- (void)testThatItMatchesObjectsThatNeedToBeInsertedUpstream
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    NSPredicate *sut = [ZMUser predicateForObjectsThatNeedToBeInsertedUpstream];
    
    // when
    user.remoteIdentifier = nil;
    // then
    XCTAssertTrue([sut evaluateWithObject:user]);
    
    // when
    user.remoteIdentifier = [NSUUID createUUID];
    // then
    XCTAssertFalse([sut evaluateWithObject:user]);
}


- (void)testThatItSetsNormalizedNameWhenSettingName
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.name = @"Øyvïnd Øtterssön";
    
    // when
    NSString *normalizedName = user.normalizedName;
    
    // then
    XCTAssertEqualObjects(normalizedName, @"oyvind ottersson");
}


- (void)testThatItSetsNormalizedEmailAddressWhenSettingTheEmailAddress
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.emailAddress = @"Øyvïnd.Øtterssön@example.com";
    
    // when
    NSString *normalizedEmailAddress = user.normalizedEmailAddress;
    
    // then
    XCTAssertEqualObjects(normalizedEmailAddress, @"oyvind.ottersson@example.com");
}


- (void)testThatModifiedDataFieldsCanNeverBeChangedForNormalUser
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.name = @"Test";

    // when
    XCTAssertTrue([self.uiMOC saveOrRollback]);
    
    // then
    XCTAssertEqualObjects(user.keysThatHaveLocalModifications, [NSSet set]);
}



- (void)testThatModifiedDataFieldsCanBeModifiedForSelfUser
{
    // given
    ZMUser<ZMEditableUser> *user = [ZMUser selfUserInContext:self.uiMOC];
    user.name = @"Test";
    user.accentColorValue = ZMAccentColorBrightOrange;
    
    // when
    XCTAssertTrue([self.uiMOC saveOrRollback]);
    
    // then
    NSSet *expectedChangedKeys = [NSSet setWithObjects:@"name", @"accentColorValue", nil];
    XCTAssertEqualObjects(user.keysThatHaveLocalModifications, expectedChangedKeys);
}

- (void)testThatSpecialKeysAreNotPartOfTheLocallyModifiedKeys
{
    // when
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    
    // then
    XCTAssertEqual(user.keysTrackedForLocalModifications.count, 0u);
}

- (void)testThatSpecialKeysAreNotPartOfTheLocallyModifiedKeysForSelfUser
{
    // given
    NSSet *expected = [NSSet setWithArray:@[@"accentColorValue",
                                            @"emailAddress",
                                            @"previewProfileAssetIdentifier",
                                            @"completeProfileAssetIdentifier",
                                            @"imageMediumData",
                                            @"imageSmallProfileData",
                                            @"smallProfileRemoteIdentifier_data",
                                            @"mediumRemoteIdentifier_data",
                                            @"name",
                                            @"phoneNumber"]];
    
    // when
    ZMUser *user = [ZMUser selfUserInContext:self.uiMOC];
    XCTAssertNotNil(user);
    
    // then
    XCTAssertEqualObjects(user.keysTrackedForLocalModifications, expected);
}

- (void)testThatClientsRequiringUserAttentionContainsUntrustedClientsWithNeedsToNotifyFlagSet
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMUser *user = [ZMUser selfUserInContext:self.syncMOC];
        UserClient *selfClient = [self createSelfClientOnMOC:self.syncMOC];
        
        UserClient *trustedClient1 = [self createClientForUser:user createSessionWithSelfUser:NO onMOC:self.syncMOC];
        [selfClient trustClient:trustedClient1];
        trustedClient1.needsToNotifyUser = YES;
        
        UserClient *trustedClient2 = [self createClientForUser:user createSessionWithSelfUser:NO onMOC:self.syncMOC];
        [selfClient trustClient:trustedClient2];
        trustedClient2.needsToNotifyUser = NO;
        
        UserClient *ignoredClient1 = [self createClientForUser:user createSessionWithSelfUser:NO onMOC:self.syncMOC];
        [selfClient ignoreClient:ignoredClient1];
        ignoredClient1.needsToNotifyUser = YES;
        
        UserClient *ignoredClient2 = [self createClientForUser:user createSessionWithSelfUser:NO onMOC:self.syncMOC];
        [selfClient ignoreClient:ignoredClient2];
        ignoredClient2.needsToNotifyUser = NO;
        
        // when
        NSSet<UserClient *> *result = user.clientsRequiringUserAttention;
        
        // then
        NSSet<UserClient *> *expected = [NSSet setWithObjects:ignoredClient1, nil];
        XCTAssertEqualObjects(result, expected);
    }];
}

- (void)testThatCallingRefreshDataMarksItAsToDownload {
    
    [self.syncMOC performBlockAndWait: ^{
        // GIVEN
        ZMUser *user = [ZMUser selfUserInContext:self.syncMOC];
        user.remoteIdentifier = [NSUUID UUID];
        user.needsToBeUpdatedFromBackend = false;
        XCTAssertFalse(user.needsToBeUpdatedFromBackend);
        
        // WHEN
        [user refreshData];
        
        // THEN
        XCTAssertTrue(user.needsToBeUpdatedFromBackend);
    }];
}

@end




@implementation ZMUserTests (Connections)

- (void)testThatIsConnectedIsTrueWhenThereIsAnAcceptedConnection
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    connection.status = ZMConnectionStatusAccepted;
    connection.to = user;
    
    // then
    XCTAssertTrue(user.isConnected);
    
    XCTAssertFalse(user.isBlocked);
    XCTAssertFalse(user.isIgnored);
    XCTAssertFalse(user.isPendingApprovalByOtherUser);
    XCTAssertFalse(user.isPendingApprovalBySelfUser);
    XCTAssertFalse(user.canBeConnected);
}

- (void)testThatIsIgnoreIsTrueWhenThereIsAnIgnoredConnection
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    connection.status = ZMConnectionStatusIgnored;
    connection.to = user;
    
    // then
    XCTAssertTrue(user.isIgnored);
    
    XCTAssertFalse(user.isConnected);
    XCTAssertFalse(user.isBlocked);
    XCTAssertFalse(user.isPendingApprovalByOtherUser);
    XCTAssertTrue(user.isPendingApprovalBySelfUser);
    XCTAssertTrue(user.canBeConnected);
}


- (void)testThatIsBlockedIsTrueWhenThereIsABlockedConnection
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    connection.status = ZMConnectionStatusBlocked;
    connection.to = user;
    
    // then
    XCTAssertTrue(user.isBlocked);
    
    XCTAssertFalse(user.isConnected);
    XCTAssertFalse(user.isIgnored);
    XCTAssertFalse(user.isPendingApprovalByOtherUser);
    XCTAssertFalse(user.isPendingApprovalBySelfUser);
    XCTAssertTrue(user.canBeConnected);
}


- (void)testThatIsPendingBySelfUserIsTrueWhenThereIsAPendingConnection
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    connection.status = ZMConnectionStatusPending;
    connection.to = user;
    
    // then
    XCTAssertTrue(user.isPendingApprovalBySelfUser);
    
    XCTAssertFalse(user.isConnected);
    XCTAssertFalse(user.isBlocked);
    XCTAssertFalse(user.isIgnored);
    XCTAssertFalse(user.isPendingApprovalByOtherUser);
    XCTAssertTrue(user.canBeConnected);
}


- (void)testThatIsPendingByOtherUserIsTrueWhenThereIsASentConnection
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    connection.status = ZMConnectionStatusSent;
    connection.to = user;
    
    // then
    XCTAssertTrue(user.isPendingApprovalByOtherUser);
    
    XCTAssertFalse(user.isConnected);
    XCTAssertFalse(user.isBlocked);
    XCTAssertFalse(user.isIgnored);
    XCTAssertFalse(user.isPendingApprovalBySelfUser);
    XCTAssertFalse(user.canBeConnected);
}

- (void)testThatConnectionsValuesAreFalseWhenThereIsNotAConnectionToTheSelfUser
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    
    // then
    XCTAssertFalse(user.isConnected);
    XCTAssertFalse(user.isBlocked);
    XCTAssertFalse(user.isIgnored);
    XCTAssertFalse(user.isPendingApprovalByOtherUser);
    XCTAssertFalse(user.isPendingApprovalBySelfUser);
    XCTAssertTrue(user.canBeConnected);
}

- (void)testThatItReturnsTheOneToOneConversationToAnUser
{
    // given
    ZMUser *connectedUser = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMUser *unconnectedUser = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMConversation *oneToOne = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    
    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    connection.status = ZMConnectionStatusIgnored;
    connection.conversation = oneToOne;
    connection.to = connectedUser;
    
    // then
    XCTAssertNil(unconnectedUser.oneToOneConversation);
    XCTAssertEqual(oneToOne, connectedUser.oneToOneConversation);
}


- (void)testThatBlockingAUserSetsTheConnectionStatusToBlocked
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    connection.status = ZMConnectionStatusAccepted;
    connection.to = user;
    [self.uiMOC saveOrRollback];
    
    // when
    [user block];
    
    // then
    XCTAssertTrue(self.uiMOC.hasChanges);
    XCTAssertEqual(connection.status, ZMConnectionStatusBlocked);
}

- (void)testThatBlockingABlockedUserDoesNotChangeAnything
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    connection.status = ZMConnectionStatusBlocked;
    connection.to = user;
    [self.uiMOC saveOrRollback];
    
    // when
    [user block];
    
    // then
    XCTAssertFalse(self.uiMOC.hasChanges);
    XCTAssertEqual(connection.status, ZMConnectionStatusBlocked);
}


- (void)testThatBlockingAnInvalidConnectionDoesNotChangeAnything
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    connection.status = ZMConnectionStatusInvalid;
    connection.to = user;
    [self.uiMOC saveOrRollback];
    
    // when
    [user block];
    
    // then
    XCTAssertFalse(self.uiMOC.hasChanges);
    XCTAssertEqual(connection.status, ZMConnectionStatusInvalid);
}


- (void)testThatBlockingASentConnectionSetsTheConnectionStatusToBlocked
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    connection.status = ZMConnectionStatusSent;
    connection.to = user;
    [self.uiMOC saveOrRollback];
    
    // when
    [user block];
    
    // then
    XCTAssertTrue(self.uiMOC.hasChanges);
    XCTAssertEqual(connection.status, ZMConnectionStatusBlocked);
}


- (void)testThatBlockingAnIgnoredUserSetsTheConnectionStatusToBlocked
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    connection.status = ZMConnectionStatusIgnored;
    connection.to = user;
    [self.uiMOC saveOrRollback];
    
    // when
    [user block];
    
    // then
    XCTAssertTrue(self.uiMOC.hasChanges);
    XCTAssertEqual(connection.status, ZMConnectionStatusBlocked);
}


- (void)testThatBlockingAPendingConnectionSetsTheConnectionStatusToBlocked
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    connection.status = ZMConnectionStatusPending;
    connection.to = user;
    [self.uiMOC saveOrRollback];
    
    // when
    [user block];
    
    // then
    XCTAssertTrue(self.uiMOC.hasChanges);
    XCTAssertEqual(connection.status, ZMConnectionStatusBlocked);
}



- (void)testThatConnectingToAnAlreadyConnectedUserDoesNotCreateAnyChanges;
{
    // given
    NSUUID *uuid = [NSUUID createUUID];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = uuid;
    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    connection.status = ZMConnectionStatusAccepted;
    connection.to = user;
    [self.uiMOC saveOrRollback];
    
    // when
    [user connectWithMessageText:@"Foo, bar, baz!" completionHandler:nil];
    
    // then
    XCTAssertFalse(self.uiMOC.hasChanges);
    XCTAssertEqual(connection.status, ZMConnectionStatusAccepted);
}


- (void)testThatItCallsTheCompletionHandlerAfterSendingAConnectionRequest
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];

    // when
    __block BOOL completionHandlerWasCalled = NO;
    [user connectWithMessageText:@"" completionHandler:^{
        completionHandlerWasCalled = YES;
    }];
    
    XCTAssertTrue([self waitOnMainLoopUntilBlock:^BOOL{
        return completionHandlerWasCalled == YES;
    } timeout:0.5]);
    
    // then
    XCTAssertTrue(completionHandlerWasCalled);
}


- (void)testThatItDoesNotTryToCallTheCompletionHandlerIfItIsNil
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    
    // then
    XCTAssertNoThrow([user connectWithMessageText:@"" completionHandler:nil]);
}


- (void)testThatConnectingToAUserThatHasNotAcceptedYetDoesNotCreateAnyChanges;
{
    // given
    NSUUID *uuid = [NSUUID createUUID];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = uuid;
    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    connection.status = ZMConnectionStatusSent;
    connection.to = user;
    [self.uiMOC saveOrRollback];
    
    // when
    [user connectWithMessageText:@"Foo, bar, baz!" completionHandler:nil];
    
    // then
    XCTAssertFalse(self.uiMOC.hasChanges);
    XCTAssertEqual(connection.status, ZMConnectionStatusSent);
}

- (void)testThatConnectingToAnIgnoredUserSetsTheConnectionStatusToAccepted;
{
    // given
    NSUUID *uuid = [NSUUID createUUID];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = uuid;
    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    connection.status = ZMConnectionStatusIgnored;
    connection.to = user;
    connection.message = @"Some old text";
    [self.uiMOC saveOrRollback];
    NSString *originalText = [connection.message copy];
    
    // when
    [user connectWithMessageText:@"Foo, bar, baz!" completionHandler:nil];
    
    // then
    XCTAssertEqual(connection.status, ZMConnectionStatusAccepted);
    XCTAssertEqualObjects(connection.message, originalText, @"This will stay whatever the other user set it to.");
}

- (void)testThatConnectingToABlockedUserSetsTheConnectionStatusToAccepted;
{
    // given
    NSUUID *uuid = [NSUUID createUUID];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = uuid;
    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    connection.status = ZMConnectionStatusBlocked;
    connection.to = user;
    connection.message = @"Some old text";
    [self.uiMOC saveOrRollback];
    NSString *originalText = [connection.message copy];
    
    // when
    [user connectWithMessageText:@"Foo, bar, baz!" completionHandler:nil];
    
    // then
    XCTAssertEqual(connection.status, ZMConnectionStatusAccepted);
    XCTAssertEqualObjects(connection.message, originalText, @"This will stay whatever the other user set it to.");
}

- (void)testThatConnectingToAPendingUserSetsTheConnectionStatusToAcceptedAndConversationTypeToOneToOneAndUpdatesModificationDate
{
    // given
    NSUUID *uuid = [NSUUID createUUID];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = uuid;
    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    connection.status = ZMConnectionStatusPending;
    connection.to = user;
    connection.message = @"Some old text";
    connection.conversation = conversation;
    conversation.conversationType = ZMConversationTypeConnection;
    
    [self.uiMOC saveOrRollback];
    NSString *originalText = [connection.message copy];
    
    // when
    [user connectWithMessageText:@"Foo, bar, baz!" completionHandler:nil];
    
    // then
    XCTAssertEqual(connection.status, ZMConnectionStatusAccepted);
    XCTAssertEqualObjects(connection.message, originalText, @"This will stay whatever the other user set it to.");
    XCTAssertEqual(conversation.conversationType, ZMConversationTypeOneOnOne);
    XCTAssertEqualWithAccuracy(conversation.lastModifiedDate.timeIntervalSince1970, [NSDate date].timeIntervalSince1970, 0.1);
}

- (void)testThatConnectingToAUserSetsTheConnectionStatusAsHavingLocalModifications
{
    // given
    NSUUID *uuid = [NSUUID createUUID];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = uuid;
    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    connection.status = ZMConnectionStatusPending;
    connection.to = user;
    connection.message = @"Some old text";
    [self.uiMOC saveOrRollback];
    [connection setValue:[NSSet set] forKey:@"modifiedKeys"]; // Simulate no local changes
    
    // when
    [user connectWithMessageText:@"Foo, bar, baz!" completionHandler:nil];
    [self.uiMOC saveOrRollback];
    
    // then
    XCTAssertTrue([connection hasLocalModificationsForKey:@"status"]);
    XCTAssertFalse([connection hasLocalModificationsForKey:@"message"]);
}

- (void)testThatConnectingToAUserThatIHaveNoConnectionWithCreatesANewConnectionWithConversation
{
    // given
    NSUUID *uuid = [NSUUID createUUID];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = uuid;
    [self.uiMOC saveOrRollback];
    XCTAssertEqual([ZMConnection connectionsInMangedObjectContext:self.uiMOC].count, 0u);
    
    
    // when
    XCTestExpectation *expectation = [self expectationWithDescription:@"Connection done"];
    [user connectWithMessageText:@"Bla bla bla" completionHandler:^{
        [expectation fulfill];
    }];
    [self.uiMOC saveOrRollback];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    NSArray *connections = [ZMConnection connectionsInMangedObjectContext:self.uiMOC];
    XCTAssertEqual(connections.count, 1u);
    ZMConnection *connection = connections[0];
    XCTAssertEqual(connection.to, user);
    XCTAssertEqual(connection.status, ZMConnectionStatusSent);
    XCTAssertNotNil(connection.conversation);
}

- (void)testThatConnectingToAUserThatIHavePreviouslyCancelledCreatesNewConnectionWithSameConversation
{
    ZMConnection *connection = [self createNewConnection:ZMConnectionStatusCancelled];
    ZMUser *user = connection.to;
    ZMConversation *conversation = connection.conversation;
    
    // when
    XCTestExpectation *expectation = [self expectationWithDescription:@"Connection done"];
    [connection.to connectWithMessageText:@"Bla bla bla" completionHandler:^{
        [expectation fulfill];
    }];
    [self.uiMOC saveOrRollback];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    NSArray *connections = [ZMConnection connectionsInMangedObjectContext:self.uiMOC];
    XCTAssertEqual(connections.count, 1u);
    XCTAssertNotEqual(connections.firstObject, connection);
    
    connection = connections.firstObject;
    XCTAssertEqual(connection.to, user);
    XCTAssertEqual(connection.conversation, conversation);
    XCTAssertEqual(connection.status, ZMConnectionStatusSent);
}

- (ZMConnection *)createNewConnection:(ZMConnectionStatus)status
{
    NSUUID *uuid = [NSUUID createUUID];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = uuid;
    ZMConnection *connection = [ZMConnection insertNewSentConnectionToUser:user];
    connection.status = status;
    connection.message = @"Some old text";
    [self.uiMOC saveOrRollback];
    [connection setValue:[NSSet set] forKey:@"modifiedKeys"]; // Simulate no local changes
    return connection;
}

- (void)testThatCancellingConnectionSetsConnectionStatusToCancelled
{
    // given
    ZMConnection *connection = [self createNewConnection:ZMConnectionStatusSent];
    // when
    [connection.to cancelConnectionRequest];
    [self.uiMOC saveOrRollback];
    
    // then
    XCTAssertTrue([connection hasLocalModificationsForKey:@"status"]);
    XCTAssertEqual(connection.status, ZMConnectionStatusCancelled);
}

- (void)testThatItCanNotCancelIncommingConnectionRequest
{
    // given
    ZMConnection *connection = [self createNewConnection:ZMConnectionStatusPending];
    
    // when
    [connection.to cancelConnectionRequest];
    [self.uiMOC saveOrRollback];
    
    // then
    XCTAssertFalse([connection hasLocalModificationsForKey:@"status"]);
    XCTAssertEqual(connection.status, ZMConnectionStatusPending);
}

- (void)testThatItCanNotCancelAcceptedConnectionRequest
{
    // given
    ZMConnection *connection = [self createNewConnection:ZMConnectionStatusAccepted];

    // and when
    [connection.to cancelConnectionRequest];
    [self.uiMOC saveOrRollback];
    
    // then
    XCTAssertFalse([connection hasLocalModificationsForKey:@"status"]);
    XCTAssertEqual(connection.status, ZMConnectionStatusAccepted);
}

- (void)testThatItCanNotCancelBlockedConnectionRequest
{
    // given
    ZMConnection *connection = [self createNewConnection:ZMConnectionStatusBlocked];
    
    // when
    [connection.to cancelConnectionRequest];
    [self.uiMOC saveOrRollback];
    
    // then
    XCTAssertFalse([connection hasLocalModificationsForKey:@"status"]);
    XCTAssertEqual(connection.status, ZMConnectionStatusBlocked);
}

- (void)testThatItCanNotCancelIgnoredConnectionRequest
{
    // given
    ZMConnection *connection = [self createNewConnection:ZMConnectionStatusIgnored];
    
    // when
    [connection.to cancelConnectionRequest];
    [self.uiMOC saveOrRollback];
    
    // then
    XCTAssertFalse([connection hasLocalModificationsForKey:@"status"]);
    XCTAssertEqual(connection.status, ZMConnectionStatusIgnored);
}

- (void)testThatItDetectsAnnaAsBot
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    
    // when
    user.handle = @"annathebot";
    
    // then
    XCTAssertTrue(user.isBot);
}


- (void)testThatItDetectsOttoAsBot
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    
    // when
    user.handle = @"ottothebot";
    
    // then
    XCTAssertTrue(user.isBot);
}

- (void)testThatItDoesNotDetectUserAsBot
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    
    // when
    user.handle = @"florence";
    
    // then
    XCTAssertFalse(user.isBot);
}

- (void)testThatItDoesNotDetectUserWithoutHandleAsBot
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    
    // then
    XCTAssertFalse(user.isBot);
}

@end



@implementation ZMUserTests (Validation)

- (void)testThatItRejectsANameThatIsOnly1CharacterLong
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.name = @"Original name";
    [self.uiMOC saveOrRollback];
    
    // when
    user.name = @" A";
    [self performIgnoringZMLogError:^{
        [self.uiMOC saveOrRollback];
    }];
    
    // then
    XCTAssertEqualObjects(user.name, @"Original name");
}

- (void)testThatItTrimmsTheNameForLeadingAndTrailingWhitespace;
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.name = @"Abe";
    [self.uiMOC saveOrRollback];
    
    // when
    user.name = @" \tasdfad \t";
    [self.uiMOC saveOrRollback];
    
    // then
    XCTAssertEqualObjects(user.name, @"asdfad");
}

- (void)testThatItRollsBackIfTheNameIsTooLong;
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.name = @"Short Name";
    [self.uiMOC saveOrRollback];
    
    // when
    user.name = [@"" stringByPaddingToLength:200 withString:@"Long " startingAtIndex:0];
    [self performIgnoringZMLogError:^{
        [self.uiMOC saveOrRollback];
    }];
    
    // then
    XCTAssertEqualObjects(user.name, @"Short Name");
}

- (void)testThatItReplacesNewlinesAndTabWithSpacesInTheName;
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.name = @"Name";
    [self.uiMOC saveOrRollback];
    
    // when
    user.name = @"\tA\tB \tC\t\rD\r \nE";
    [self.uiMOC saveOrRollback];
    
    // then
    XCTAssertEqualObjects(user.name, @"A B  C  D   E");
}

- (void)testThatItDoesNotValidateTheNameOnSyncContext_1;
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user.name = @"Name";
        [self.syncMOC saveOrRollback];
        
        // when
        user.name = @"\tA\tB \tC\t\rD\r \nE";
        [self.syncMOC saveOrRollback];
        
        // then
        XCTAssertEqualObjects(user.name, @"\tA\tB \tC\t\rD\r \nE");
    }];
}

- (void)testThatItDoesNotValidateTheNameOnSyncContext_2;
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user.name = @"Name";
        [self.syncMOC saveOrRollback];
        NSString *veryLongName = [@"" stringByPaddingToLength:300 withString:@"Long " startingAtIndex:0];
        
        // when
        user.name = veryLongName;
        [self.syncMOC saveOrRollback];
        
        // then
        XCTAssertEqualObjects(user.name, veryLongName);
    }];
}

- (void)testThatExtremeCombiningCharactersAreRemovedFromTheName
{
    // GIVEN
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    [self.uiMOC saveOrRollback];
    
    // WHEN
    user.name = @"ť̹̱͉̥̬̪̝ͭ͗͊̕e͇̺̳̦̫̣͕ͫͤ̅s͇͎̟͈̮͎̊̾̌͛ͭ́͜t̗̻̟̙͑ͮ͊ͫ̂";
    
    // THEN
    XCTAssertEqualObjects(user.name, @"test̻̟̙");
}

- (void)testThatItLimitsTheAccentColorToAValidRange;
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.accentColorValue = ZMAccentColorBrightYellow;
    [self.uiMOC saveOrRollback];
    XCTAssertEqual(user.accentColorValue, ZMAccentColorBrightYellow);
    
    // when
    user.accentColorValue = ZMAccentColorUndefined;
    [self.uiMOC saveOrRollback];
    
    // then
    XCTAssertGreaterThanOrEqual(user.accentColorValue, ZMAccentColorMin);
    XCTAssertLessThanOrEqual(user.accentColorValue, ZMAccentColorMax);
    
    // when
    user.accentColorValue = (ZMAccentColor) (ZMAccentColorMax + 1);
    [self.uiMOC saveOrRollback];
    
    // then
    XCTAssertGreaterThanOrEqual(user.accentColorValue, ZMAccentColorMin);
    XCTAssertLessThanOrEqual(user.accentColorValue, ZMAccentColorMax);
}

- (void)testThatItDoesNotLimitTheAccentColorOnTheSyncContext;
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user.accentColorValue = ZMAccentColorBrightYellow;
        [self.syncMOC saveOrRollback];
        XCTAssertEqual(user.accentColorValue, ZMAccentColorBrightYellow);
        
        // when
        user.accentColorValue = ZMAccentColorUndefined;
        [self.syncMOC saveOrRollback];
        
        // then
        XCTAssertEqual(user.accentColorValue, ZMAccentColorUndefined);
    }];
}

- (void)testThatItLimitsTheNameLength;
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.name = @"Tester Name";
    [self.uiMOC saveOrRollback];
    XCTAssertEqualObjects(user.name, @"Tester Name");
    NSString *veryLongName = [@"" stringByPaddingToLength:140 withString:@"zeta" startingAtIndex:0];
    
    // when
    user.name = veryLongName;
    [self performIgnoringZMLogError:^{
        [self.uiMOC saveOrRollback];
    }];
    
    // then
    XCTAssertEqualObjects(user.name, @"Tester Name");
}

- (void)testThatItLimitsTheEmailAddressLength;
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.emailAddress = @"tester@example.com";
    [self.uiMOC saveOrRollback];
    XCTAssertEqualObjects(user.emailAddress, @"tester@example.com");
    NSString *veryLongName = [@"" stringByPaddingToLength:120 withString:@"zeta" startingAtIndex:0];
    NSString *veryLongEmailAddress = [veryLongName stringByAppendingString:@"@example.com"];
    
    // when
    user.emailAddress = veryLongEmailAddress;
    [self performIgnoringZMLogError:^{
        [self.uiMOC saveOrRollback];
    }];
    
    // then
    XCTAssertEqualObjects(user.emailAddress, @"tester@example.com");
}

- (void)testThatItTrimsWhiteSpaceInTheEmailAddress;
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    NSString *original = @"tester@example.com";
    user.emailAddress = original;
    [self.uiMOC saveOrRollback];
    
    // when
    user.emailAddress = @"  tester@example.com\t\n";
    [self.uiMOC saveOrRollback];
    
    // then
    XCTAssertEqualObjects(user.emailAddress, original);
}

- (void)testThatItFailsOnAnEmailAddressWithWhiteSpace;
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    NSString *original = @"tester@example.com";
    user.emailAddress = original;
    [self.uiMOC saveOrRollback];
    XCTAssertEqualObjects(user.emailAddress, original);
    
    // when
    user.emailAddress = @"tes ter@example.com";
    [self performIgnoringZMLogError:^{
        [self.uiMOC saveOrRollback];
    }];
    
    // then
    XCTAssertEqualObjects(user.emailAddress, original);

    // when
    user.emailAddress = @"tester@exa\tmple.com";
    [self performIgnoringZMLogError:^{
        [self.uiMOC saveOrRollback];
    }];
    
    // then
    XCTAssertEqualObjects(user.emailAddress, original);
}

static NSString * const usernameValidCharacters = @"ABCDEFGHIJKLMNOPQRSTUVWXYZ!#$%&'*+-/=?^_`{|}~abcdefghijklmnopqrstuvwxyz0123456789";
static NSString * const usernameValidCharactersLowercased = @"abcdefghijklmnopqrstuvwxyz!#$%&'*+-/=?^_`{|}~abcdefghijklmnopqrstuvwxyz0123456789";

static NSString * const domainValidCharacters = @"abcdefghijklmnopqrstuvwxyz-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
static NSString * const domainValidCharactersLowercased = @"abcdefghijklmnopqrstuvwxyz-0123456789abcdefghijklmnopqrstuvwxyz";

- (void)testThatItAcceptsAValidEmailAddress
{
    // C.f. <https://en.wikipedia.org/wiki/Email_address#Valid_email_addresses>
    
    NSDictionary *validEmailAddresses =
    @{
      @"niceandsimple@example.com" : @"niceandsimple@example.com",
      @"very.common@example.com" : @"very.common@example.com",
      @"a.little.lengthy.but.fine@dept.example.com" : @"a.little.lengthy.but.fine@dept.example.com",
      @"disposable.style.email.with+symbol@example.com" : @"disposable.style.email.with+symbol@example.com",
      @"other.email-with-dash@example.com" : @"other.email-with-dash@example.com",
      //      @"user@localserver",
      @"abc.\"defghi\".xyz@example.com" : @"abc.\"defghi\".xyz@example.com",
      @"\"abcdefghixyz\"@example.com" : @"\"abcdefghixyz\"@example.com",
      @"a@b.c.example.com" : @"a@b.c.example.com",
      @"a@3b.c.example.com": @"a@3b.c.example.com",
      @"a@b-c.d.example.com" : @"a@b-c.d.example.com",
      @"a@b-c.d-c.example.com" : @"a@b-c.d-c.example.com",
      @"a@b3-c.d4.example.com" : @"a@b3-c.d4.example.com",
      @"a@b-4c.d-c4.example.com" : @"a@b-4c.d-c4.example.com",
      @"Meep Møøp <Meep.Moop@example.com>" : @"meep.moop@example.com",
      @"=?ISO-8859-1?Q?Keld_J=F8rn_Simonsen?= <keld@example.com>" : @"keld@example.com",
      @"=?ISO-8859-1?Q?Keld_J=F8rn_Simonsen?=@example.com" : @"=?iso-8859-1?q?keld_j=f8rn_simonsen?=@example.com",
      @"\"Meep Møøp\" <Meep.Moop@example.com>" : @"meep.moop@example.com",
      @"Meep   Møøp  <Meep.Moop@EXample.com>" : @"meep.moop@example.com",
      @"Meep \"_the_\" Møøp <Meep.Moop@ExAmple.com>" : @"meep.moop@example.com",
      @"   whitespace@example.com    " : @"whitespace@example.com",
      @"मानक \"हिन्दी\" <manaka.hindi@example.com>" : @"manaka.hindi@example.com",

//      these cases are also possible but are very unlikely to appear
//      currently they don't pass validation
//      @"\"very.unusual.@.unusual.com\"@example.com" : @"\"very.unusual.@.unusual.com\"@example.com",
//      @"Some Name <\"very.unusual.@.unusual.com\"@example.com>" : @"\"very.unusual.@.unusual.com\"@example.com"
      };
    
    for (NSString *valid in validEmailAddresses) {
        // given
        ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
        NSString *original = @"tester@example.com";
        user.emailAddress = original;
        [self.uiMOC saveOrRollback];
        XCTAssertEqualObjects(user.emailAddress, original);
        
        // when
        user.emailAddress = valid;
        [self.uiMOC saveOrRollback];
        
        // then
        XCTAssertEqualObjects(user.emailAddress, validEmailAddresses[valid]);
    }
}

- (void)testThatItFailsOnAnInvalidEmailAddress
{
    // C.f. <https://en.wikipedia.org/wiki/Email_address#Valid_email_addresses>
    
    NSArray *invalidEmailAddresses =
    @[@"Abc.example.com", // (an @ character must separate the local and domain parts)
      @"A@b@c@example.com", // (only one @ is allowed outside quotation marks)
      @"a\"b(c)d,e:f;g<h>i[j\\k]l@example.com", // (none of the special characters in this local part is allowed outside quotation marks)
      @"just\"not\"right@example.com", // (quoted strings must be dot separated or the only element making up the local-part)
      @"this is\"not\\allowed@example.com", // (spaces, quotes, and backslashes may only exist when within quoted strings and preceded by a backslash)
      @"this\\ still\\\"not\\\\allowed@example.com", // (even if escaped (preceded by a backslash), spaces, quotes, and backslashes must still be contained by quotes)
      @"tester@example..com", // double dot before @
      @"foo..tester@example.com", // double dot after @
      @"",
      usernameValidCharactersLowercased,
      @"a@b",
      @"a@b3",
      @"a@b.c-",
      //      @"a@3b.c", //unclear why this should be not valid
      @"two words@something.org",
      @"\"Meep Moop\" <\"The =^.^= Meeper\"@x.y",
      @"mailbox@[11.22.33.44]",
      @"some prefix with <two words@example.com>",
      @"x@something_odd.example.com",
      @"x@host.with?query=23&parameters=42",
      @"some.mail@host.with.port:12345",
      @"comments(inside the address)@are(actually).not(supported, but nobody uses them anyway)",
      @"\"you need to close quotes@proper.ly",
      @"\"you need\" <to.close@angle-brackets.too",
      @"\"you need\" >to.open@angle-brackets.first",
      @"\"you need\" <to.close@angle-brackets>.right",
      @"some<stran>ge@example.com",
      @"Mr. Stranger <some<stran>ge@example.com>",
      @"<Meep.Moop@EXample.com>"
      ];

    
    
    for (NSString *invalid in invalidEmailAddresses) {
        // given
        ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
        NSString *original = @"tester@example.com";
        user.emailAddress = original;
        [self.uiMOC saveOrRollback];
        XCTAssertEqualObjects(user.emailAddress, original);
        
        // when
        user.emailAddress = invalid;
        [self performIgnoringZMLogError:^{
            [self.uiMOC saveOrRollback];
        }];
    
        // then
        XCTAssertEqualObjects(user.emailAddress, original, @"Tried to set invalid \'%@\'", invalid);
    }
}

- (void)testThatItDoesNotValidateTheEmailAddressOnTheSyncContext;
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user.emailAddress = @"tester@example.com";
        [self.syncMOC saveOrRollback];
        
        // when
        user.emailAddress = @" tester\t  BLA \\\"";
        [self.syncMOC saveOrRollback];
        
        // then
        XCTAssertEqualObjects(user.emailAddress, @" tester\t  BLA \\\"");
    }];
}

- (void)testThatItAcceptsAValidPhoneNumber
{
    NSArray *validPhoneNumbers =
    @[@"123456", // short
      @"123456789012345678", // normal length
      @"+4915233336668",
      @"+49 152 3333 6668",
      @"+49 (0) 152 3333 6668",
      @"(152) 3333-6668",
      @"415.456.456",
      @"+1 415.456.456",
      @"00 1 415.456.456"];
    
    
    for (NSString *valid in validPhoneNumbers) {
        // given
        ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
        NSString *original = @"12345678";
        user.phoneNumber = original;
        [self.uiMOC saveOrRollback];
        XCTAssertEqualObjects(user.phoneNumber, original);
        
        // when
        user.phoneNumber = valid;
        [self.uiMOC saveOrRollback];
        
        // then
        XCTAssertEqualObjects(user.phoneNumber, valid, @"Tried to set valid \'%@\'", valid);
    }
}

- (void)testThatItDoesNotValidateThePhoneNumberOnTheSyncContext;
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user.phoneNumber = @"12345678";
        [self.syncMOC saveOrRollback];
        
        // when
        user.phoneNumber = @" tester\t  BLA \\\"";
        [self.syncMOC saveOrRollback];
        
        // then
        XCTAssertEqualObjects(user.phoneNumber, @" tester\t  BLA \\\"");
    }];
}

- (void)testThatItStaticallyDoesNotValidateAShortCode
{
    // given
    NSString *code = ShortPhoneCode;
    
    // when
    XCTAssertFalse([ZMUser validatePhoneVerificationCode:&code error:nil]);
}

- (void)testThatItStaticallyDoesNotValidateALongCode
{
    // given
    NSString *code = LongPhoneCode;
    
    // when
    XCTAssertFalse([ZMUser validatePhoneVerificationCode:&code error:nil]);
}

- (void)testThatItStaticallyValidatesACodeOfTheRightLength
{
    // given
    NSString *phone = ValidPhoneCode;
    
    // when
    XCTAssertTrue([ZMUser validatePhoneVerificationCode:&phone error:nil]);
}

- (void)testThatItStaticallyDoesNotValidateAnEmptyOrNilCode
{
    // given
    NSString *phone = @"";
    // when
    XCTAssertFalse([ZMUser validatePhoneVerificationCode:&phone error:nil]);
    
    phone = nil;
    XCTAssertFalse([ZMUser validatePhoneVerificationCode:&phone error:nil]);
}

- (void)testThatItStaticallyDoesNotValidateEmptyOrNilPhoneNumber
{
    //given
    NSString *phoneNumber = @"";
    
    //when
    XCTAssertFalse([ZMUser validatePhoneNumber:&phoneNumber error:nil]);
    
    phoneNumber = nil;
    XCTAssertFalse([ZMUser validatePhoneNumber:&phoneNumber error:nil]);
}

- (void)testThatItStaticallyDoesValidateValidPhoneNumbers
{
    //given
    for (NSString *number in self.validPhoneNumbers) {
        NSString *phoneNumber = number;
        XCTAssertTrue([ZMUser validatePhoneNumber:&phoneNumber error:nil], @"Phone number %@ should be valid", phoneNumber);
    }
}

- (void)testThatItStaticallyDoesNotValidatePhoneNumberWithInvalidChars
{
    NSArray *invalidCharactes = @[@"*", @";", @"#", @"[", @"]", @"~"];
    for (NSString *invalidChar in invalidCharactes) {
        NSString *phoneNumber = [ValidPhoneNumber stringByAppendingString:invalidChar];
        XCTAssertFalse([ZMUser validatePhoneNumber:&phoneNumber error:nil], @"Phone number %@ should be invalid", phoneNumber);
    }
}

- (void)testThatItStaticallyDoesNotValidateShortPhoneNumbers
{
    for (NSString *number in self.shortPhoneNumbers) {
        NSString *phoneNumber = number;
        XCTAssertFalse([ZMUser validatePhoneNumber:&phoneNumber error:nil], @"Phone number %@ should be invalid", phoneNumber);
    }
}

- (void)testThatItStaticallyDoesNotValidateLongPhoneNumbers
{
    for (NSString *number in self.longPhoneNumbers) {
        NSString *phoneNumber = number;
        XCTAssertFalse([ZMUser validatePhoneNumber:&phoneNumber error:nil], @"Phone number %@ should be invalid", phoneNumber);
    }
}

- (void)testThatItDoesNotValidateAShortPassword
{
    // given
    NSString *password = ShortPassword;
    
    // when
    XCTAssertFalse([ZMUser validatePassword:&password error:nil]);
}

- (void)testThatItDoesNotValidateLongPassword
{
    // given
    NSString *password = LongPassword;
    
    // when
    XCTAssertFalse([ZMUser validatePassword:&password error:nil]);
}

- (void)testThatItValidatesAValidPassword
{
    // given
    NSString *password = ValidPassword;
    
    // when
    XCTAssertTrue([ZMUser validatePassword:&password error:nil]);
}


@end



@implementation ZMUserTests (KeyValueObserving)

- (void)testThatItRecalculatesIsBlockedWhenConnectionChanges
{
    // given
    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    connection.status = ZMConnectionStatusAccepted;
    connection.to = user1;
    
    XCTAssertFalse(user1.isBlocked);
    // expect

    [self keyValueObservingExpectationForObject:user1 keyPath:@"isBlocked" expectedValue:nil];
    
    // when
    connection.status = ZMConnectionStatusBlocked;

    // then
    XCTAssertTrue(user1.isBlocked);
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
}

- (void)testThatItRecalculatesIsIgnoredWhenConnectionChanges
{
    // given
    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    connection.status = ZMConnectionStatusAccepted;
    connection.to = user1;
    
    XCTAssertFalse(user1.isIgnored);
    // expect
    
    [self keyValueObservingExpectationForObject:user1 keyPath:@"isIgnored" expectedValue:nil];
    
    // when
    connection.status = ZMConnectionStatusIgnored;
    
    // then
    XCTAssertTrue(user1.isIgnored);
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
}

- (void)testThatItRecalculatesIsPendingApprovalBySelfUserWhenConnectionChanges
{
    // given
    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    connection.status = ZMConnectionStatusPending;
    connection.to = user1;
    
    XCTAssertTrue(user1.isPendingApprovalBySelfUser);
    // expect
    
    [self keyValueObservingExpectationForObject:user1 keyPath:@"isPendingApprovalBySelfUser" expectedValue:nil];
    
    // when
    connection.status = ZMConnectionStatusAccepted;
    
    // then
    XCTAssertFalse(user1.isPendingApprovalBySelfUser);
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
}

- (void)testThatItRecalculatesIsPendingApprovalByOtherUsersWhenConnectionChanges
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    connection.status = ZMConnectionStatusSent;
    connection.to = user;
    
    XCTAssertTrue(user.isPendingApprovalByOtherUser);
    // expect
    
    [self keyValueObservingExpectationForObject:user keyPath:@"isPendingApprovalByOtherUser" expectedValue:nil];
    
    // when
    connection.status = ZMConnectionStatusAccepted;
    
    // then
    XCTAssertFalse(user.isPendingApprovalByOtherUser);
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
}

@end
    

@implementation ZMUserTests (DisplayName)

- (void)testThatItReturnsCorrectUserName
{
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.name = @"User Name";
    
    XCTAssertEqualObjects(user.displayName, @"User");
}

- (void)testThatItReturnsCorrectInitials
{
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.name = @"User Name";
    
    XCTAssertEqualObjects(user.initials, @"UN");
}

- (void)testThatTheUserNameIsCopied
{
    // given
    NSString *originalName = @"Will";
    NSMutableString *name = [originalName mutableCopy];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    
    // when
    user.name = name;
    [name appendString:@"iam"];
    
    // then
    XCTAssertEqualObjects(user.name, originalName);
}

@end




@implementation ZMUserTestsUseSQLLiteStore

- (BOOL)shouldUseInMemoryStore;
{
    return NO;
}

- (void)testThatItFetchesUsersWithOutLocalSmallProfileIdentifier
{
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.smallProfileRemoteIdentifier = NSUUID.createUUID;
    [self.uiMOC saveOrRollback];

    // when
    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"User"];
    fetchRequest.predicate = [ZMUser predicateForSmallImageNeedingToBeUpdatedFromBackend];
    NSArray *result = [self.uiMOC executeFetchRequestOrAssert:fetchRequest];
    
    // then
    XCTAssert(result.count > 0);
    XCTAssertEqualObjects(result.lastObject, user);
    
}

- (void)testThatItFetchesUsersWithOutMediumSmallProfileIdentifier
{
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.mediumRemoteIdentifier = NSUUID.createUUID;
    [self.uiMOC saveOrRollback];
    
    // when
    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"User"];
    fetchRequest.predicate = [ZMUser predicateForMediumImageNeedingToBeUpdatedFromBackend];
    NSArray *result = [self.uiMOC executeFetchRequestOrAssert:fetchRequest];
    
    // then
    XCTAssert(result.count > 0);
    XCTAssertEqualObjects(result.lastObject, user);
    
}

@end


@implementation ZMUserTests (Trust)

- (ZMUser *)userWithClients:(int)count trusted:(BOOL)trusted
{
    [self createSelfClient];
    [self.uiMOC refreshAllObjects];
    
    UserClient *selfClient = [ZMUser selfUserInContext:self.uiMOC].selfClient;
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    for (int i = 0; i < count; i++) {
        UserClient *client = [UserClient insertNewObjectInManagedObjectContext:self.uiMOC];
        client.user = user;
        if (trusted) {
            [selfClient trustClient:client];
        } else {
            [selfClient ignoreClient:client];
        }
    }
    return user;
}

- (void)testThatItReturns_Trusted_NO_WhenThereAreNoClients
{
    // given
    ZMUser *user = [self userWithClients:0 trusted:NO];
    
    // when
    BOOL isTrusted = user.trusted;
    
    //then
    XCTAssertFalse(isTrusted);
}


- (void)testThatItReturns_Trusted_YES_WhenThereAreTrustedClients
{
    // given
    ZMUser *user = [self userWithClients:1 trusted:YES];
    
    // when
    BOOL isTrusted = user.trusted;
    
    //then
    XCTAssertTrue(isTrusted);
}

- (void)testThatItReturns_Trusted_NO_WhenThereAreNoTrustedClients
{
    // given
    ZMUser *user = [self userWithClients:1 trusted:NO];
    
    // when
    BOOL isTrusted = user.trusted;
    
    //then
    XCTAssertFalse(isTrusted);
}


- (void)testThatItReturns_UnTrusted_NO_WhenThereAreNoClients
{
    // given
    ZMUser *user = [self userWithClients:0 trusted:YES];
    
    // when
    BOOL isTrusted = user.untrusted;
    
    //then
    XCTAssertFalse(isTrusted);
}


- (void)testThatItReturns_UnTrusted_YES_WhenThereAreUnTrustedClients
{
    // given
    ZMUser *user = [self userWithClients:1 trusted:NO];
    
    // when
    BOOL untrusted = user.untrusted;
    
    //then
    XCTAssertTrue(untrusted);
}

- (void)testThatItReturns_UnTrusted_NO_WhenThereAreNoUnTrustedClients
{
    // given
    ZMUser *user = [self userWithClients:1 trusted:YES];
    
    // when
    BOOL untrusted = user.untrusted;
    
    //then
    XCTAssertFalse(untrusted);
}

@end

