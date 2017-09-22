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


#import "ZMConversationTests.h"
#import "ZMConversation+Timestamps.h"
#import "ZMConversation+Internal.h"

@interface ZMConversationTests_Timestamp : ZMConversationTestsBase
@end

@implementation ZMConversationTests_Timestamp


- (void)testThatItSendsANotificationWhenSettingTheLastRead
{
    // given
    ZMConversation *sut = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    
    // when
    XCTestExpectation *expectation = [self expectationWithDescription:@"Notified"];
    id token = [NotificationInContext addObserverWithName:ZMConversation.lastReadDidChangeNotificationName
                                                  context:self.uiMOC
                                                   object:nil
                                                    queue:nil
                                                    using:^(NotificationInContext * notification) {
                                                        XCTAssertEqual(notification.object, sut);
                                                        [expectation fulfill];
                                                    }];
    
    [sut updateLastReadServerTimeStampIfNeededWithTimeStamp:[NSDate date] andSync:NO];
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    
    // then
    token = nil;
}


@end



