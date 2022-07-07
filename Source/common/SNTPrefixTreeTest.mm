/// Copyright 2018 Google Inc. All rights reserved.
///
/// Licensed under the Apache License, Version 2.0 (the "License");
/// you may not use this file except in compliance with the License.
/// You may obtain a copy of the License at
///
///    http://www.apache.org/licenses/LICENSE-2.0
///
///    Unless required by applicable law or agreed to in writing, software
///    distributed under the License is distributed on an "AS IS" BASIS,
///    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
///    See the License for the specific language governing permissions and
///    limitations under the License.

#include <uuid/uuid.h>
#import <XCTest/XCTest.h>

#include "Source/common/SNTPrefixTree.h"

@interface SNTPrefixTreeTest : XCTestCase
@end

@implementation SNTPrefixTreeTest

- (void)testAddAndHas {
  auto t = SNTPrefixTree();
  XCTAssertFalse(t.HasPrefix("/private/var/tmp/file1"));
  t.AddPrefix("/private/var/tmp/");
  XCTAssertTrue(t.HasPrefix("/private/var/tmp/file1"));
}

- (void)testReset {
  auto t = SNTPrefixTree();
  t.AddPrefix("/private/var/tmp/");
  XCTAssertTrue(t.HasPrefix("/private/var/tmp/file1"));
  t.Reset();
  XCTAssertFalse(t.HasPrefix("/private/var/tmp/file1"));
}

- (void)testThreading {
  uint32_t count = 4096;
  auto t = new SNTPrefixTree(count * (uint32_t)[NSUUID UUID].UUIDString.length);

  NSMutableArray *UUIDs = [NSMutableArray arrayWithCapacity:count];
  for (int i = 0; i < count; ++i) {
    [UUIDs addObject:[NSUUID UUID].UUIDString];
  }

  __block BOOL stop = NO;

  // Create a bunch of background noise.
  dispatch_async(dispatch_get_global_queue(0, 0), ^{
    for (uint64_t i = 0; i < UINT64_MAX; ++i) {
      dispatch_async(dispatch_get_global_queue(0, 0), ^{
        t->HasPrefix([UUIDs[i % count] UTF8String]);
      });
      if (stop) return;
    }
  });

  // Fill up the tree.
  dispatch_apply(count, dispatch_get_global_queue(0, 0), ^(size_t i) {
    XCTAssertEqual(t->AddPrefix([UUIDs[i] UTF8String]), kIOReturnSuccess);
  });

  // Make sure every leaf byte is found.
  dispatch_apply(count, dispatch_get_global_queue(0, 0), ^(size_t i) {
    XCTAssertTrue(t->HasPrefix([UUIDs[i] UTF8String]));
  });

  stop = YES;
}

// Test Add and Reset operations happening concurrently
- (void)testAddAndReset {
  auto tree = new SNTPrefixTree();

  dispatch_queue_t qAdd = dispatch_queue_create(NULL, NULL);
  dispatch_queue_t qReset = dispatch_queue_create(NULL, NULL);

  // Let the Add operation go faster than the reset operation to make
  // sure the tree has content
  // useconds_t sleepAdd = 1;
  useconds_t sleepReset = 300;

  // Cap Reset operations relative to the amount of time slept so that
  // they finish about the same time...
  // uint32_t addOps = 50000;
  // uint32_t resetOps = addOps * (sleepAdd / (double)sleepReset);
  uint32_t resetOps = 5000;

  // printf("Add ops: %u, reset ops: %u\n", addOps, resetOps);

  uint32_t maxAttempts = 10;
  dispatch_group_t group = dispatch_group_create();
  dispatch_semaphore_t sema = dispatch_semaphore_create(0);

  for (uint32_t attempts = 0; attempts < maxAttempts; attempts++) {
    dispatch_group_enter(group);
    dispatch_async(qAdd, ^{
      // char prefix[7] = "/A/A/A";
      uuid_t uuid;
      uuid_string_t uuidStr;

      // for (uint32_t i = 0; i < addOps; i++) {
      //   // [[NSProcessInfo processInfo] globallyUniqueString];
      //   // prefix[1] = ((i + 0) %  4) + 'A';
      //   // prefix[3] = ((i + 1) % 26) + 'A';
      //   // prefix[5] = ((i + 2) % 26) + 'A';

      //   // tree->AddPrefix(prefix);

      //   // tree->AddPrefix([[[NSProcessInfo processInfo] globallyUniqueString] UTF8String]);

      //   uuid_generate_random(uuid);
      //   uuid_unparse_lower(uuid, uuidStr);
      //   tree->AddPrefix(uuidStr);

      //   // usleep(sleepAdd);
      // }

      uint64_t addCount = 0;

      while (dispatch_semaphore_wait(sema, DISPATCH_TIME_NOW)) {
        uuid_generate_random(uuid);
        uuid_unparse_lower(uuid, uuidStr);
        uuidStr[10] = '\0'; // trunacate to spend less time in AddPrefix with lock held
        tree->AddPrefix(uuidStr);
        addCount++;
        if (addCount % 100 == 0) {
          // printf("Added %llu\n", addCount);
        }
      }

      dispatch_group_leave(group);
    });

    dispatch_group_enter(group);
    dispatch_async(qReset, ^{
      for (uint32_t i = 0; i < resetOps; i++) {
        tree->Reset();
        usleep(sleepReset);
        // printf("Reset\n");
      }

      dispatch_semaphore_signal(sema);
      dispatch_group_leave(group);
    });

    if (dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC))) {
      XCTFail("Times out waiting for Add/Reset operations to complete.");
      break;
    }
  }

  // If we get here, the test didn't crash and all was successful
  XCTAssertTrue(YES);
}

@end
