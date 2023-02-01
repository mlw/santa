/// Copyright 2022 Google Inc. All rights reserved.
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

#import <Foundation/Foundation.h>
#import <OCMock/OCMock.h>
#import <XCTest/XCTest.h>

#import "Source/common/SNTCommonEnums.h"
#import "Source/common/SNTRule.h"
#include "Source/common/TestUtils.h"
#import "Source/santad/DataLayer/SNTRuleTable.h"
#include "Source/santad/DecisionCache.h"
#import "Source/santad/SNTDatabaseController.h"

using santa::santad::DecisionCache;

SNTCachedDecision *MakeCachedDecision(struct stat sb, SNTEventState decision) {
  SNTCachedDecision *cd = [[SNTCachedDecision alloc] init];

  cd.decision = decision;
  cd.sha256 = @"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
  cd.vnodeId = {
    .fsid = sb.st_dev,
    .fileid = sb.st_ino,
  };

  return cd;
}

@interface DecisionCacheTest : XCTestCase
@property id mockDatabaseController;
@property id mockRuleDatabase;
@end

@implementation DecisionCacheTest

- (void)setUp {
  self.mockDatabaseController = OCMClassMock([SNTDatabaseController class]);
  self.mockRuleDatabase = OCMStrictClassMock([SNTRuleTable class]);
}

- (void)testBasicOperation {
  DecisionCache dc;
  struct stat sb = MakeStat();

  // First make sure the item isn't in the cache
  XCTAssertNil(dc.CachedDecisionForFile(sb));

  // Add the item to the cache
  SNTCachedDecision *cd = MakeCachedDecision(sb, SNTEventStateAllowTeamID);
  dc.CacheDecision(cd);

  // Ensure the item exists in the cache
  SNTCachedDecision *cachedCD = dc.CachedDecisionForFile(sb);
  XCTAssertNotNil(cachedCD);
  XCTAssertEqual(cachedCD.decision, cd.decision);
  XCTAssertEqual(cachedCD.vnodeId.fileid, cd.vnodeId.fileid);

  // Delete the item from the cache and ensure it no longer exists
  dc.ForgetCachedDecisionForFile(sb);
  XCTAssertNil(dc.CachedDecisionForFile(sb));
}

- (void)testResetTimestampForCachedDecision {
  DecisionCache dc;
  struct stat sb = MakeStat();
  SNTCachedDecision *cd = MakeCachedDecision(sb, SNTEventStateAllowTransitive);

  dc.CacheDecision(cd);

  OCMStub([self.mockDatabaseController ruleTable]).andReturn(self.mockRuleDatabase);

  OCMExpect([self.mockRuleDatabase
    resetTimestampForRule:[OCMArg checkWithBlock:^BOOL(SNTRule *rule) {
      return rule.identifier == cd.sha256 && rule.state == SNTRuleStateAllowTransitive &&
             rule.type == SNTRuleTypeBinary;
    }]]);

  SNTCachedDecision *cachedCD1 = dc.ResetTimestampForCachedDecision(sb);

  // Timestamps should not be reset so frequently. Call a second time quickly
  // but do not register a second expectation so that the test will fail if
  // timestamps are actually reset a second time.
  SNTCachedDecision *cachedCD2 = dc.ResetTimestampForCachedDecision(sb);

  // Verify the contents of SNTCachcedDecision objects returned
  XCTAssertNotNil(cachedCD1);
  XCTAssertNotNil(cachedCD2);
  XCTAssertEqual(cachedCD1.decision, cd.decision);
  XCTAssertEqual(cachedCD2.decision, cd.decision);
  XCTAssertEqual(cachedCD1.vnodeId, cd.vnodeId);
  XCTAssertEqual(cachedCD2.vnodeId, cd.vnodeId);

  XCTAssertTrue(OCMVerifyAll(self.mockRuleDatabase));
}

@end
