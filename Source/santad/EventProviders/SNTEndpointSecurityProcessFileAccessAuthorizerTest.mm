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

#include "Source/santad/EventProviders/FAAPolicyProcessor.h"
#include "Source/santad/EventProviders/SNTEndpointSecurityEventHandler.h"
#import "Source/santad/EventProviders/SNTEndpointSecurityProcessFileAccessAuthorizer.h"

#include <EndpointSecurity/EndpointSecurity.h>
#import <OCMock/OCMock.h>
#import <XCTest/XCTest.h>

#include <memory>
#include <set>

#include "Source/common/TestUtils.h"
#include "Source/santad/DataLayer/WatchItemPolicy.h"
#include "Source/santad/EventProviders/EndpointSecurity/Message.h"
#include "Source/santad/EventProviders/EndpointSecurity/MockEndpointSecurityAPI.h"
#include "Source/santad/EventProviders/MockFAAPolicyProcessor.h"

using santa::CheckPolicyBlock;
using santa::IterateProcessPoliciesBlock;
using santa::MockFAAPolicyProcessor;
using santa::PairPathAndType;
using santa::ProcessWatchItemPolicy;
using santa::SetPairPathAndType;
using santa::WatchItemPathType;
using santa::WatchItemProcess;

void SetExpectationsForProcessFileAccessAuthorizerInit(
    std::shared_ptr<MockEndpointSecurityAPI> mockESApi) {
  EXPECT_CALL(*mockESApi, UnmuteAllPaths).WillOnce(testing::Return(true));
  EXPECT_CALL(*mockESApi, UnmuteAllTargetPaths).WillOnce(testing::Return(true));
  EXPECT_CALL(*mockESApi, InvertProcessMuting).WillOnce(testing::Return(true));
}

@interface SNTEndpointSecurityProcessFileAccessAuthorizer (Testing)
@property bool isSubscribed;
@end

@interface SNTEndpointSecurityProcessFileAccessAuthorizerTest : XCTestCase
@end

@implementation SNTEndpointSecurityProcessFileAccessAuthorizerTest

- (void)testEnable {
  std::set<es_event_type_t> expectedEventSubs = {
      ES_EVENT_TYPE_AUTH_CLONE,        ES_EVENT_TYPE_AUTH_COPYFILE, ES_EVENT_TYPE_AUTH_CREATE,
      ES_EVENT_TYPE_AUTH_EXCHANGEDATA, ES_EVENT_TYPE_AUTH_LINK,     ES_EVENT_TYPE_AUTH_OPEN,
      ES_EVENT_TYPE_AUTH_RENAME,       ES_EVENT_TYPE_AUTH_TRUNCATE, ES_EVENT_TYPE_AUTH_UNLINK,
      ES_EVENT_TYPE_NOTIFY_EXEC,       ES_EVENT_TYPE_NOTIFY_EXIT,   ES_EVENT_TYPE_NOTIFY_FORK,
  };

  auto mockESApi = std::make_shared<MockEndpointSecurityAPI>();
  EXPECT_CALL(*mockESApi, ClearCache)
      .After(EXPECT_CALL(*mockESApi, Subscribe(testing::_, expectedEventSubs))
                 .WillOnce(testing::Return(true)))
      .WillOnce(testing::Return(true));

  id procFAAClient = [[SNTEndpointSecurityProcessFileAccessAuthorizer alloc]
      initWithESAPI:mockESApi
            metrics:nullptr
          processor:santa::Processor::kProcessFileAccessAuthorizer];

  [procFAAClient enable];

  for (const auto &event : expectedEventSubs) {
    XCTAssertNoThrow(santa::EventTypeToString(event));
  }

  XCTBubbleMockVerifyAndClearExpectations(mockESApi.get());
}

- (void)testProbeInterest {
  es_file_t esFile = MakeESFile("foo");
  es_process_t esProc = MakeESProcess(&esFile);
  es_file_t execFile = MakeESFile("bar");
  es_process_t execProc = MakeESProcess(&execFile, MakeAuditToken(12, 23), MakeAuditToken(34, 45));
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_AUTH_EXEC, &esProc);
  esMsg.event.exec.target = &execProc;

  auto mockESApi = std::make_shared<MockEndpointSecurityAPI>();
  mockESApi->SetExpectationsESNewClient();
  mockESApi->SetExpectationsRetainReleaseMessage();
  SetExpectationsForProcessFileAccessAuthorizerInit(mockESApi);

  NSLog(@"~~~~~ About to create shared MockFAAPolicyProcessor");
  // First call will not match, second call will match
  auto mockFAA = std::make_shared<MockFAAPolicyProcessor>(nil, nullptr, nullptr, nullptr, nil);
  NSLog(@"~~~~~ About to set MockFAAPolicyProcessor expectations");
  EXPECT_CALL(*mockFAA, PolicyMatchesProcess)
      .WillOnce(testing::Return(false))
      .WillOnce(testing::Return(true));
  NSLog(@"~~~~~ About to create shared FAAPP Proxy");
  auto mockFAAProxy = std::make_shared<santa::ProcessFAAPolicyProcessorProxy>(mockFAA);

  // Test object to provide to the CheckPolicyBlock
  NSLog(@"~~~~~ About to create watch item");
  WatchItemProcess proc{"proc_path_1", "com.example.proc", "PROCTEAMID", {}, "", std::nullopt};
  auto pwip = std::make_shared<ProcessWatchItemPolicy>(
      "name", "ver", SetPairPathAndType{PairPathAndType{"path1", WatchItemPathType::kLiteral}},
      true, true, santa::WatchItemRuleType::kProcessesWithAllowedPaths, false, false, "", nil, nil,
      santa::SetWatchItemProcess{proc});

  // Test iter block will call the given CheckPolicyBlock and capture the return
  __block bool checkPolicyBlockResult;
  IterateProcessPoliciesBlock iterPoliciesBlock = ^(CheckPolicyBlock block) {
    checkPolicyBlockResult = block(pwip);
  };

  NSLog(@"~~~~~ About to create proc FAA client");
  SNTEndpointSecurityProcessFileAccessAuthorizer *procFAAClient =
      [[SNTEndpointSecurityProcessFileAccessAuthorizer alloc] initWithESAPI:mockESApi
                                                                    metrics:nullptr
                                                         faaPolicyProcessor:mockFAAProxy
                                                iterateProcessPoliciesBlock:iterPoliciesBlock];
  NSLog(@"~~~~~ About to create partial mock of proc FAA client");
  id mockProcFAAClient = OCMPartialMock(procFAAClient);

  // Fake being conected so the probe runs
  procFAAClient.isSubscribed = true;

  {
    NSLog(@"~~~~~ About to create message");
    santa::Message msg(mockESApi, &esMsg);

    // First test a non-matching policy. The probe should return uninterested
    // and the CheckPolicyBlock should not return true;
    NSLog(@"~~~~~ About to call probeInterest");
    XCTAssertEqual([procFAAClient probeInterest:msg], santa::ProbeInterest::kUninterested);
    XCTAssertFalse(checkPolicyBlockResult);

    // Next check a mtching policy. The probe should return interested, the
    // process should be muted, and CheckPolicyBlock should return true.
    NSLog(@"~~~~~ About to mute a thing");
    OCMExpect([mockProcFAAClient muteProcess:&execProc.audit_token]).andReturn(true);

    NSLog(@"~~~~~ About to probe interest again");
    XCTAssertEqual([procFAAClient probeInterest:msg], santa::ProbeInterest::kInterested);
    XCTAssertTrue(checkPolicyBlockResult);

    NSLog(@"~~~~~ About to verify stuff");
    XCTFail("Force fail");
    XCTAssertTrue(OCMVerifyAll(mockProcFAAClient));
  }
}

@end
