/// Copyright 2023 Google LLC
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

#include "Source/common/PeriodicTimer.h"

#include <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

using santa::common::PeriodicTimer;

void TestPeriodicFunc(std::any ctx) {
  printf("In my test periodic func...\n");
  dispatch_semaphore_t sema = std::any_cast<dispatch_semaphore_t>(ctx);
  dispatch_semaphore_signal(sema);
}

@interface PeriodicTimerTest : XCTestCase
@end

@implementation PeriodicTimerTest

- (void)testBasic {
  dispatch_semaphore_t sema = dispatch_semaphore_create(0);
  auto pt = PeriodicTimer::Create(1000, 0, TestPeriodicFunc);

  pt.Start(sema);

  dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
}

@end
