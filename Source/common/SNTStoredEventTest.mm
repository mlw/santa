/// Copyright 2025 North Pole Security, Inc.
///
/// Licensed under the Apache License, Version 2.0 (the "License");
/// you may not use this file except in compliance with the License.
/// You may obtain a copy of the License at
///
///     http://www.apache.org/licenses/LICENSE-2.0
///
/// Unless required by applicable law or agreed to in writing, software
/// distributed under the License is distributed on an "AS IS" BASIS,
/// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
/// See the License for the specific language governing permissions and
/// limitations under the License.

#import "Source/common/SNTStoredEvent.h"
#import "Source/common/SNTStoredExecutionEvent.h"
#import "Source/common/SNTStoredFileAccessEvent.h"

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

@interface StoredEventTest : XCTestCase
@end

@implementation StoredEventTest

- (void)testHashForEvent {
  // The base class should throw
  SNTStoredEvent *baseEvent = [[SNTStoredEvent alloc] init];
  XCTAssertThrows([baseEvent hashForEvent]);

  // Derived classes should not throw
  SNTStoredExecutionEvent *execEvent = [[SNTStoredExecutionEvent alloc] init];
  execEvent.fileSHA256 = @"foo";
  XCTAssertEqualObjects([execEvent hashForEvent], @"foo");

  SNTStoredFileAccessEvent *faaEvent = [[SNTStoredFileAccessEvent alloc] init];
  faaEvent.process.fileSHA256 = @"bar";
  XCTAssertEqualObjects([faaEvent hashForEvent], @"bar");
}

@end
