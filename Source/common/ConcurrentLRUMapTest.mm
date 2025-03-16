/// Copyright 2025 North Pole Security, Inc.
///
/// Licensed under the Apache License, Version 2.0 (the "License");
/// you may not use this file except in compliance with the License.
/// You may obtain a copy of the License at
///
///     https://www.apache.org/licenses/LICENSE-2.0
///
/// Unless required by applicable law or agreed to in writing, software
/// distributed under the License is distributed on an "AS IS" BASIS,
/// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
/// See the License for the specific language governing permissions and
/// limitations under the License.

#include "Source/common/ConcurrentLRUMap.h"

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#include <string>

#include "Source/common/SantaCache.h"
#include "absl/hash/hash.h"

@interface ConcurrentLRUCacheTest : XCTestCase
@end

@implementation ConcurrentLRUCacheTest

- (void)testFoundationTypes {
  ConcurrentLRUMapObjC<NSString *, int> cache(8, 4);
  cache.Put([NSString stringWithFormat:@"foo"], 12);
  XCTAssertEqual(cache.Get(@"foo").value_or(0), 12);

  // absl::flat_hash_map<NSString*, int> myMap;
  // myMap[[NSString stringWithFormat:@"foo"]] = 12;
  // int val = myMap[@"foo"];
  // NSLog(@"Got val...: %d", val);
}

- (void)testBasic {
  ConcurrentLRUMap<std::string, int> cache(3, 1);

  cache.Put("k1", 1);
  cache.Put("k2", 2);
  cache.Put("k3", 3);

  XCTAssertEqual(cache.Size(), 3);
  XCTAssertTrue(cache.Contains("k1"));
  XCTAssertTrue(cache.Contains("k2"));
  XCTAssertTrue(cache.Contains("k3"));
  XCTAssertFalse(cache.Contains("k4"));

  cache.Put("k4", 4);

  XCTAssertEqual(cache.Size(), 3);
  XCTAssertFalse(cache.Contains("k1"));
  XCTAssertTrue(cache.Contains("k2"));
  XCTAssertTrue(cache.Contains("k3"));
  XCTAssertTrue(cache.Contains("k4"));

  XCTAssertEqual(cache.Get("k2").value_or(0), 2);

  cache.Put("k5", 5);

  XCTAssertEqual(cache.Size(), 3);
  XCTAssertFalse(cache.Contains("k1"));
  XCTAssertTrue(cache.Contains("k2"));
  XCTAssertFalse(cache.Contains("k3"));
  XCTAssertTrue(cache.Contains("k4"));
  XCTAssertTrue(cache.Contains("k5"));

  cache.Clear();

  XCTAssertEqual(cache.Size(), 0);
}

- (void)testLarge {
  ConcurrentLRUMap<std::string, int> cache(100, 8);

  for (int i = 0; i < 80; ++i) {
    cache.Put("key" + std::to_string(i), i);
  }

  XCTAssertEqual(cache.Size(), 80);

  // Access some items to make them recently used
  for (int i = 10; i < 30; ++i) {
    if (auto val = cache.Get("key" + std::to_string(i))) {
      XCTAssertEqual(val, i);
    }
  }

  // Add more items to test eviction
  for (int i = 80; i < 120; ++i) {
    cache.Put("key" + std::to_string(i), i);
  }

  XCTAssertEqual(cache.Size(), 100);

  // Check which items were evicted (should be items 30-69 that weren't accessed)
  int present = 0;
  int evicted = 0;
  for (int i = 0; i < 120; ++i) {
    bool exists = cache.Contains("key" + std::to_string(i));
    if (i < 10 || (i >= 30 && i < 40)) {
      XCTAssertFalse(exists, "Key exists but should've been evicted: %s",
                     ("key" + std::to_string(i)).c_str());
      evicted++;
    } else {
      XCTAssertTrue(exists, "Key doesn't exist but should be present: %s",
                    ("key" + std::to_string(i)).c_str());
      present++;
    }
  }

  XCTAssertEqual(present, 100);
  XCTAssertEqual(evicted, 20);
}

// - (void)testConcurrentLRUMapPerformance {
//   size_t maxSize = 100000;
//   size_t perBucket = 100;
//   size_t bucketCount = (1 << (32 - __builtin_clz((((uint32_t)maxSize / perBucket) - 1) ?: 1)));

//   NSLog(@"ConcurrentLRUMap...");
//   NSLog(@"Map Size: %zu, Per Bucket: %zu, Bucket count: %zu", maxSize, perBucket, bucketCount);

//   [self measureBlock:^{
//     // ConcurrentLRUMap<uint64_t, uint64_t> cache(1000, 16);
//     auto cache = std::make_unique<ConcurrentLRUMap<uint64_t, uint64_t>>(maxSize, 2048);
//     dispatch_queue_t concurrentQueue =
//         dispatch_queue_create("com.test.performance", DISPATCH_QUEUE_CONCURRENT);
//     dispatch_group_t group = dispatch_group_create();

//     uint64_t operationCount = maxSize;

//     auto cachePtr = cache.get();

//     for (uint64_t i = 0; i < operationCount; i++) {
//       dispatch_group_async(group, concurrentQueue, ^{
//         // NSString *key = [NSString stringWithFormat:@"key%lu", (unsigned long)i];
//         cachePtr->Put(i, i);
//         XCTAssertEqual(cachePtr->Get(i).value(), i);
//         // [map putKey:key value:@(i)];
//         // [map getValueForKey:key];
//       });
//     }

//     dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
//   }];
// }

// - (void)testImprovedConcurrentLRUMapPerformance {
//   size_t maxSize = 100000;
//   size_t perBucket = 100;
//   size_t bucketCount = (1 << (32 - __builtin_clz((((uint32_t)maxSize / perBucket) - 1) ?: 1)));

//   NSLog(@"ImprovedConcurrentLRUMap...");
//   NSLog(@"Map Size: %zu, Per Bucket: %zu, Bucket count: %zu", maxSize, perBucket, bucketCount);

//   [self measureBlock:^{
//     // ConcurrentLRUMap<uint64_t, uint64_t> cache(1000, 16);
//     auto cache = std::make_unique<ImprovedConcurrentLRUMap<uint64_t, uint64_t>>(maxSize, 2048);
//     dispatch_queue_t concurrentQueue =
//         dispatch_queue_create("com.test.performance", DISPATCH_QUEUE_CONCURRENT);
//     dispatch_group_t group = dispatch_group_create();

//     uint64_t operationCount = maxSize;

//     auto cachePtr = cache.get();

//     for (uint64_t i = 0; i < operationCount; i++) {
//       dispatch_group_async(group, concurrentQueue, ^{
//         // NSString *key = [NSString stringWithFormat:@"key%lu", (unsigned long)i];
//         cachePtr->Put(i, i);
//         XCTAssertEqual(cachePtr->Get(i).value(), i);
//         // [map putKey:key value:@(i)];
//         // [map getValueForKey:key];
//       });
//     }

//     dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
//   }];
// }

// - (void)testSantaCachePerformance {
//   size_t maxSize = 100000;
//   size_t perBucket = 100;
//   size_t bucketCount = (1 << (32 - __builtin_clz((((uint32_t)maxSize / perBucket) - 1) ?: 1)));
//   NSLog(@"SantaCache...");
//   NSLog(@"Map Size: %zu, Per Bucket: %zu, Bucket count: %zu", maxSize, perBucket, bucketCount);

//   [self measureBlock:^{
//     // ConcurrentLRUMap<uint64_t, uint64_t> cache(1000, 16);
//     auto cache = std::make_unique<SantaCache<uint64_t, uint64_t>>(maxSize, perBucket);
//     dispatch_queue_t concurrentQueue =
//         dispatch_queue_create("com.test.performance", DISPATCH_QUEUE_CONCURRENT);
//     dispatch_group_t group = dispatch_group_create();

//     uint64_t operationCount = maxSize;

//     auto cachePtr = cache.get();

//     for (uint64_t i = 0; i < operationCount; i++) {
//       dispatch_group_async(group, concurrentQueue, ^{
//         cachePtr->set(i, i);
//         XCTAssertEqual(cachePtr->get(i), i);
//         // [map putKey:key value:@(i)];
//         // [map getValueForKey:key];
//       });
//     }

//     dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
//   }];
// }

@end
