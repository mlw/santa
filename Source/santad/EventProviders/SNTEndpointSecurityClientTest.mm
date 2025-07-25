/// Copyright 2022 Google Inc. All rights reserved.
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

#include <EndpointSecurity/EndpointSecurity.h>
#import <OCMock/OCMock.h>
#import <XCTest/XCTest.h>
#include <bsm/libbsm.h>
#include <gmock/gmock.h>
#include <gtest/gtest.h>
#include <mach/mach_time.h>

#include <memory>

#include "Source/common/AuditUtilities.h"
#import "Source/common/SNTCommonEnums.h"
#import "Source/common/SNTConfigurator.h"
#import "Source/common/SystemResources.h"
#include "Source/common/TestUtils.h"
#include "Source/santad/DataLayer/WatchItemPolicy.h"
#include "Source/santad/EventProviders/EndpointSecurity/Client.h"
#include "Source/santad/EventProviders/EndpointSecurity/EnrichedTypes.h"
#include "Source/santad/EventProviders/EndpointSecurity/Message.h"
#include "Source/santad/EventProviders/EndpointSecurity/MockEndpointSecurityAPI.h"
#import "Source/santad/EventProviders/SNTEndpointSecurityClient.h"
#include "Source/santad/Metrics.h"

using santa::Client;
using santa::EnrichedClose;
using santa::EnrichedFile;
using santa::EnrichedMessage;
using santa::EnrichedProcess;
using santa::Message;
using santa::Processor;
using santa::SetPairPathAndType;
using santa::WatchItemPathType;

@interface SNTEndpointSecurityClient (Testing)
- (void)establishClientOrDie;
- (bool)muteSelf;
- (NSString *)errorMessageForNewClientResult:(es_new_client_result_t)result;
- (void)handleMessage:(Message &&)esMsg
    recordEventMetrics:(void (^)(santa::EventDisposition disposition))recordEventMetrics;
- (BOOL)shouldHandleMessage:(const Message &)esMsg;
- (int64_t)computeBudgetForDeadline:(uint64_t)deadline currentTime:(uint64_t)currentTime;

@property(nonatomic) double defaultBudget;
@property(nonatomic) int64_t minAllowedHeadroom;
@property(nonatomic) int64_t maxAllowedHeadroom;
@end

@interface SNTEndpointSecurityClientTest : XCTestCase
@end

@implementation SNTEndpointSecurityClientTest

- (void)testEstablishClientOrDie {
  auto mockESApi = std::make_shared<MockEndpointSecurityAPI>();

  EXPECT_CALL(*mockESApi, MuteProcess).WillOnce(testing::Return(true));

  EXPECT_CALL(*mockESApi, NewClient)
      .WillOnce(testing::Return(Client()))
      .WillOnce(testing::Return(Client(nullptr, ES_NEW_CLIENT_RESULT_SUCCESS)));

  SNTEndpointSecurityClient *client =
      [[SNTEndpointSecurityClient alloc] initWithESAPI:mockESApi
                                               metrics:nullptr
                                             processor:Processor::kUnknown];

  // First time throws because mock triggers failed connection
  // Second time succeeds
  XCTAssertThrows([client establishClientOrDie]);
  XCTAssertNoThrow([client establishClientOrDie]);

  XCTBubbleMockVerifyAndClearExpectations(mockESApi.get());
}

- (void)testErrorMessageForNewClientResult {
  std::map<es_new_client_result_t, std::string> resultMessagePairs{
      {ES_NEW_CLIENT_RESULT_SUCCESS, ""},
      {ES_NEW_CLIENT_RESULT_ERR_NOT_PERMITTED, "Full-disk access not granted"},
      {ES_NEW_CLIENT_RESULT_ERR_NOT_ENTITLED, "Not entitled"},
      {ES_NEW_CLIENT_RESULT_ERR_NOT_PRIVILEGED, "Not running as root"},
      {ES_NEW_CLIENT_RESULT_ERR_INVALID_ARGUMENT, "Invalid argument"},
      {ES_NEW_CLIENT_RESULT_ERR_INTERNAL, "Internal error"},
      {ES_NEW_CLIENT_RESULT_ERR_TOO_MANY_CLIENTS, "Too many simultaneous clients"},
      {(es_new_client_result_t)123, "Unknown error"},
  };

  SNTEndpointSecurityClient *client =
      [[SNTEndpointSecurityClient alloc] initWithESAPI:nullptr
                                               metrics:nullptr
                                             processor:Processor::kUnknown];

  for (const auto &kv : resultMessagePairs) {
    NSString *message = [client errorMessageForNewClientResult:kv.first];
    XCTAssertEqual(0, strcmp([(message ?: @"") UTF8String], kv.second.c_str()));
  }
}

- (void)testHandleMessage {
  es_message_t esMsg;

  auto mockESApi = std::make_shared<MockEndpointSecurityAPI>();
  mockESApi->SetExpectationsRetainReleaseMessage();

  SNTEndpointSecurityClient *client =
      [[SNTEndpointSecurityClient alloc] initWithESAPI:mockESApi
                                               metrics:nullptr
                                             processor:Processor::kUnknown];

  {
    XCTAssertThrows([client handleMessage:Message(mockESApi, &esMsg) recordEventMetrics:nil]);
  }

  XCTBubbleMockVerifyAndClearExpectations(mockESApi.get());
}

- (void)testHandleMessageWithClient {
  es_file_t file = MakeESFile("foo");
  es_process_t proc = MakeESProcess(&file);
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_FORK, &proc);

  auto mockESApi = std::make_shared<MockEndpointSecurityAPI>();
  mockESApi->SetExpectationsRetainReleaseMessage();

  // Have subscribe fail the first time, meaning clear cache only called once.
  EXPECT_CALL(*mockESApi, RespondAuthResult(testing::_, testing::_, ES_AUTH_RESULT_ALLOW, true))
      .WillOnce(testing::Return(true));

  id mockConfigurator = OCMStrictClassMock([SNTConfigurator class]);
  OCMStub([mockConfigurator configurator]).andReturn(mockConfigurator);

  SNTEndpointSecurityClient *client =
      [[SNTEndpointSecurityClient alloc] initWithESAPI:mockESApi
                                               metrics:nullptr
                                             processor:Processor::kUnknown];

  {
    Message msg(mockESApi, &esMsg);

    // Is ES client, but don't ignore others == Should Handle
    OCMExpect([mockConfigurator ignoreOtherEndpointSecurityClients]).andReturn(NO);
    esMsg.process->is_es_client = true;
    XCTAssertTrue([client shouldHandleMessage:msg]);

    // Not ES client, but ignore others == Should Handle
    // Don't setup configurator mock since it won't be called when `is_es_client` is false
    esMsg.process->is_es_client = false;
    XCTAssertTrue([client shouldHandleMessage:msg]);

    // Is ES client, don't ignore others, and non-AUTH == Don't Handle
    OCMExpect([mockConfigurator ignoreOtherEndpointSecurityClients]).andReturn(YES);
    esMsg.process->is_es_client = true;
    XCTAssertFalse([client shouldHandleMessage:msg]);

    // Is ES client, don't ignore others, and AUTH == Respond and Don't Handle
    OCMExpect([mockConfigurator ignoreOtherEndpointSecurityClients]).andReturn(YES);
    esMsg.process->is_es_client = true;
    esMsg.action_type = ES_ACTION_TYPE_AUTH;
    XCTAssertFalse([client shouldHandleMessage:msg]);
  }

  XCTAssertTrue(OCMVerifyAll(mockConfigurator));
  XCTBubbleMockVerifyAndClearExpectations(mockESApi.get());

  [mockConfigurator stopMocking];
}

- (void)testPopulateAuditTokenSelf {
  std::optional<audit_token_t> myAuditToken = santa::GetMyAuditToken();
  if (!myAuditToken.has_value()) {
    XCTFail(@"Failed to fetch this client's audit token.");
    return;
  }

  XCTAssertEqual(santa::Pid(*myAuditToken), getpid());
  XCTAssertNotEqual(santa::Pidversion(*myAuditToken), 0);
}

- (void)testMuteSelf {
  auto mockESApi = std::make_shared<MockEndpointSecurityAPI>();
  SNTEndpointSecurityClient *client =
      [[SNTEndpointSecurityClient alloc] initWithESAPI:mockESApi
                                               metrics:nullptr
                                             processor:Processor::kUnknown];

  EXPECT_CALL(*mockESApi, MuteProcess)
      .WillOnce(testing::Return(true))
      .WillOnce(testing::Return(false));

  XCTAssertTrue([client muteSelf]);
  XCTAssertFalse([client muteSelf]);

  XCTBubbleMockVerifyAndClearExpectations(mockESApi.get());
}

- (void)testClearCache {
  auto mockESApi = std::make_shared<MockEndpointSecurityAPI>();
  SNTEndpointSecurityClient *client =
      [[SNTEndpointSecurityClient alloc] initWithESAPI:mockESApi
                                               metrics:nullptr
                                             processor:Processor::kUnknown];

  // Test the underlying clear cache impl returning both true and false
  EXPECT_CALL(*mockESApi, ClearCache)
      .WillOnce(testing::Return(true))
      .WillOnce(testing::Return(false));

  XCTAssertTrue([client clearCache]);
  XCTAssertFalse([client clearCache]);

  XCTBubbleMockVerifyAndClearExpectations(mockESApi.get());
}

- (void)testSubscribe {
  auto mockESApi = std::make_shared<MockEndpointSecurityAPI>();
  SNTEndpointSecurityClient *client =
      [[SNTEndpointSecurityClient alloc] initWithESAPI:mockESApi
                                               metrics:nullptr
                                             processor:Processor::kUnknown];

  std::set<es_event_type_t> events = {
      ES_EVENT_TYPE_NOTIFY_CLOSE,
      ES_EVENT_TYPE_NOTIFY_EXIT,
  };

  // Test the underlying subscribe impl returning both true and false
  EXPECT_CALL(*mockESApi, Subscribe(testing::_, events))
      .WillOnce(testing::Return(true))
      .WillOnce(testing::Return(false));

  XCTAssertTrue([client subscribe:events]);
  XCTAssertFalse([client subscribe:events]);

  XCTBubbleMockVerifyAndClearExpectations(mockESApi.get());
}

- (void)testSubscribeAndClearCache {
  auto mockESApi = std::make_shared<MockEndpointSecurityAPI>();
  SNTEndpointSecurityClient *client =
      [[SNTEndpointSecurityClient alloc] initWithESAPI:mockESApi
                                               metrics:nullptr
                                             processor:Processor::kUnknown];

  // Have subscribe fail the first time, meaning clear cache only called once.
  EXPECT_CALL(*mockESApi, ClearCache)
      .After(EXPECT_CALL(*mockESApi, Subscribe)
                 .WillOnce(testing::Return(false))
                 .WillOnce(testing::Return(true)))
      .WillOnce(testing::Return(true));

  XCTAssertFalse([client subscribeAndClearCache:{}]);
  XCTAssertTrue([client subscribeAndClearCache:{}]);

  XCTBubbleMockVerifyAndClearExpectations(mockESApi.get());
}

- (void)testUnsubscribeAll {
  auto mockESApi = std::make_shared<MockEndpointSecurityAPI>();
  SNTEndpointSecurityClient *client =
      [[SNTEndpointSecurityClient alloc] initWithESAPI:mockESApi
                                               metrics:nullptr
                                             processor:Processor::kUnknown];

  // Test the underlying unsubscribe all impl returning both true and false
  EXPECT_CALL(*mockESApi, UnsubscribeAll)
      .WillOnce(testing::Return(true))
      .WillOnce(testing::Return(false));

  XCTAssertTrue([client unsubscribeAll]);
  XCTAssertFalse([client unsubscribeAll]);

  XCTBubbleMockVerifyAndClearExpectations(mockESApi.get());
}

- (void)testUnmuteAllTargetPaths {
  auto mockESApi = std::make_shared<MockEndpointSecurityAPI>();
  SNTEndpointSecurityClient *client =
      [[SNTEndpointSecurityClient alloc] initWithESAPI:mockESApi
                                               metrics:nullptr
                                             processor:Processor::kUnknown];

  // Test the underlying unmute impl returning both true and false
  EXPECT_CALL(*mockESApi, UnmuteAllTargetPaths)
      .WillOnce(testing::Return(true))
      .WillOnce(testing::Return(false));

  XCTAssertTrue([client unmuteAllTargetPaths]);
  XCTAssertFalse([client unmuteAllTargetPaths]);

  XCTBubbleMockVerifyAndClearExpectations(mockESApi.get());
}

- (void)testEnableTargetPathWatching {
  auto mockESApi = std::make_shared<MockEndpointSecurityAPI>();
  SNTEndpointSecurityClient *client =
      [[SNTEndpointSecurityClient alloc] initWithESAPI:mockESApi
                                               metrics:nullptr
                                             processor:Processor::kUnknown];

  // UnmuteAllTargetPaths is always attempted.
  EXPECT_CALL(*mockESApi, UnmuteAllTargetPaths).Times(2).WillRepeatedly(testing::Return(true));

  // Test the underlying invert nute impl returning both true and false
  EXPECT_CALL(*mockESApi, InvertTargetPathMuting)
      .WillOnce(testing::Return(true))
      .WillOnce(testing::Return(false));

  XCTAssertTrue([client enableTargetPathWatching]);
  XCTAssertFalse([client enableTargetPathWatching]);

  XCTBubbleMockVerifyAndClearExpectations(mockESApi.get());
}

- (void)testMuteTargetPaths {
  auto mockESApi = std::make_shared<MockEndpointSecurityAPI>();
  SNTEndpointSecurityClient *client =
      [[SNTEndpointSecurityClient alloc] initWithESAPI:mockESApi
                                               metrics:nullptr
                                             processor:Processor::kUnknown];

  // Ensure all paths are attempted to be muted even if some fail.
  // Ensure if any paths fail the overall result is false.
  EXPECT_CALL(*mockESApi,
              MuteTargetPath(testing::_, std::string_view("a"), WatchItemPathType::kLiteral))
      .WillOnce(testing::Return(true));
  EXPECT_CALL(*mockESApi,
              MuteTargetPath(testing::_, std::string_view("b"), WatchItemPathType::kLiteral))
      .WillOnce(testing::Return(false));
  EXPECT_CALL(*mockESApi,
              MuteTargetPath(testing::_, std::string_view("c"), WatchItemPathType::kPrefix))
      .WillOnce(testing::Return(true));

  SetPairPathAndType paths = {
      {"a", WatchItemPathType::kLiteral},
      {"b", WatchItemPathType::kLiteral},
      {"c", WatchItemPathType::kPrefix},
  };

  XCTAssertFalse([client muteTargetPaths:paths]);

  XCTBubbleMockVerifyAndClearExpectations(mockESApi.get());
}

- (void)testUnmuteTargetPaths {
  auto mockESApi = std::make_shared<MockEndpointSecurityAPI>();
  SNTEndpointSecurityClient *client =
      [[SNTEndpointSecurityClient alloc] initWithESAPI:mockESApi
                                               metrics:nullptr
                                             processor:Processor::kUnknown];

  // Ensure all paths are attempted to be unmuted even if some fail.
  // Ensure if any paths fail the overall result is false.
  EXPECT_CALL(*mockESApi,
              UnmuteTargetPath(testing::_, std::string_view("a"), WatchItemPathType::kLiteral))
      .WillOnce(testing::Return(true));
  EXPECT_CALL(*mockESApi,
              UnmuteTargetPath(testing::_, std::string_view("b"), WatchItemPathType::kLiteral))
      .WillOnce(testing::Return(false));
  EXPECT_CALL(*mockESApi,
              UnmuteTargetPath(testing::_, std::string_view("c"), WatchItemPathType::kPrefix))
      .WillOnce(testing::Return(true));

  SetPairPathAndType paths = {
      {"a", WatchItemPathType::kLiteral},
      {"b", WatchItemPathType::kLiteral},
      {"c", WatchItemPathType::kPrefix},
  };

  XCTAssertFalse([client unmuteTargetPaths:paths]);

  XCTBubbleMockVerifyAndClearExpectations(mockESApi.get());
}

- (void)testRespondToMessageWithAuthResultCacheable {
  es_file_t file = MakeESFile("foo");
  es_process_t proc = MakeESProcess(&file);
  es_file_t fileExec = MakeESFile("target");
  es_process_t procExec = MakeESProcess(&fileExec);
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_AUTH_EXEC, &proc);
  esMsg.event.exec.target = &procExec;

  auto mockESApi = std::make_shared<MockEndpointSecurityAPI>();
  mockESApi->SetExpectationsRetainReleaseMessage();

  es_auth_result_t result = ES_AUTH_RESULT_DENY;
  bool cacheable = true;

  // Have subscribe fail the first time, meaning clear cache only called once.
  EXPECT_CALL(*mockESApi, RespondAuthResult(testing::_, testing::_, result, cacheable))
      .WillOnce(testing::Return(true));

  SNTEndpointSecurityClient *client =
      [[SNTEndpointSecurityClient alloc] initWithESAPI:mockESApi
                                               metrics:nullptr
                                             processor:Processor::kUnknown];

  {
    Message msg(mockESApi, &esMsg);
    XCTAssertTrue([client respondToMessage:msg withAuthResult:result cacheable:cacheable]);
  }

  XCTBubbleMockVerifyAndClearExpectations(mockESApi.get());
}

- (void)testProcessEnrichedMessageHandler {
  es_file_t file = MakeESFile("foo");
  es_process_t proc = MakeESProcess(&file);
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_EXEC, &proc);
  dispatch_semaphore_t sema = dispatch_semaphore_create(0);
  auto mockESApi = std::make_shared<MockEndpointSecurityAPI>();

  mockESApi->SetExpectationsRetainReleaseMessage();

  SNTEndpointSecurityClient *client =
      [[SNTEndpointSecurityClient alloc] initWithESAPI:mockESApi
                                               metrics:nullptr
                                             processor:Processor::kUnknown];
  {
    auto enrichedMsg = std::make_unique<EnrichedMessage>(EnrichedClose(
        Message(mockESApi, &esMsg),
        EnrichedProcess(std::nullopt, std::nullopt, std::nullopt, std::nullopt,
                        EnrichedFile(std::nullopt, std::nullopt, std::nullopt), std::nullopt),
        EnrichedFile(std::nullopt, std::nullopt, std::nullopt)));

    [client processEnrichedMessage:std::move(enrichedMsg)
                           handler:^(std::unique_ptr<EnrichedMessage> msg) {
                             // reset the shared_ptr to drop the held message.
                             // This is a workaround for a TSAN only false positive
                             // which happens if we switch back to the sem wait
                             // after signaling, but _before_ the implicit release
                             // of msg. In that case, the mock verify and the
                             // call of the mock's Release method can data race.
                             msg.reset();
                             dispatch_semaphore_signal(sema);
                           }];

    XCTAssertEqual(
        0, dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)),
        "Handler block not called within expected time window");
  }

  XCTBubbleMockVerifyAndClearExpectations(mockESApi.get());
}

- (void)testProcessMessageHandlerBadEventType {
  es_file_t proc_file = MakeESFile("foo");
  es_process_t proc = MakeESProcess(&proc_file);
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_EXIT, &proc);

  auto mockESApi = std::make_shared<MockEndpointSecurityAPI>();
  mockESApi->SetExpectationsRetainReleaseMessage();

  SNTEndpointSecurityClient *client =
      [[SNTEndpointSecurityClient alloc] initWithESAPI:mockESApi
                                               metrics:nullptr
                                             processor:Processor::kUnknown];

  {
    XCTAssertThrows([client processMessage:Message(mockESApi, &esMsg)
                                   handler:^(Message msg){
                                   }]);
  }

  XCTBubbleMockVerifyAndClearExpectations(mockESApi.get());
}

- (void)testProcessMessageHandler {
  es_file_t proc_file = MakeESFile("foo");
  es_process_t proc = MakeESProcess(&proc_file);
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_AUTH_OPEN, &proc, ActionType::Auth,
                                     5 * MSEC_PER_SEC);  // Long deadline to not hit first

  auto mockESApi = std::make_shared<MockEndpointSecurityAPI>();
  dispatch_semaphore_t semaRetainCount = dispatch_semaphore_create(0);
  mockESApi->SetExpectationsRetainCountTracking(semaRetainCount);

  dispatch_semaphore_t sema = dispatch_semaphore_create(0);

  SNTEndpointSecurityClient *client =
      [[SNTEndpointSecurityClient alloc] initWithESAPI:mockESApi
                                               metrics:nullptr
                                             processor:Processor::kUnknown];

  {
    XCTAssertNoThrow([client processMessage:Message(mockESApi, &esMsg)
                                    handler:^(Message msg) {
                                      dispatch_semaphore_signal(sema);
                                    }]);

    XCTAssertEqual(
        0, dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)),
        "Handler block not called within expected time window");
  }

  // The timeout here must be longer than the deadline time set in the ES message
  XCTAssertSemaTrue(semaRetainCount, 8, "Retain count never dropped to 0");

  XCTBubbleMockVerifyAndClearExpectations(mockESApi.get());
}

- (void)testComputeBudgetForDeadlineCurrentTime {
  auto mockESApi = std::make_shared<MockEndpointSecurityAPI>();

  SNTEndpointSecurityClient *client =
      [[SNTEndpointSecurityClient alloc] initWithESAPI:mockESApi
                                               metrics:nullptr
                                             processor:Processor::kUnknown];

  // The test uses crafted values to make even numbers. Ensure the client has
  // expected values for these properties so the test can fail early if not.
  XCTAssertEqual(client.defaultBudget, 0.8);
  XCTAssertEqual(client.minAllowedHeadroom, 1 * NSEC_PER_SEC);
  XCTAssertEqual(client.maxAllowedHeadroom, 5 * NSEC_PER_SEC);

  std::map<uint64_t, int64_t> deadlineMillisToBudgetMillis{
      // Further out deadlines clamp processing budget to maxAllowedHeadroom
      {45000, 40000},

      // Closer deadlines allow a set percentage processing budget
      {15000, 12000},

      // Near deadlines clamp processing budget to minAllowedHeadroom
      {3500, 2500}};

  uint64_t curTime = mach_absolute_time();

  for (const auto [deadlineMS, budgetMS] : deadlineMillisToBudgetMillis) {
    int64_t got = [client
        computeBudgetForDeadline:AddNanosecondsToMachTime(deadlineMS * NSEC_PER_MSEC, curTime)
                     currentTime:curTime];

    // Add 100us, then clip to ms to account for non-exact values due to timebase division
    got = (int64_t)((double)(got + (100 * NSEC_PER_USEC)) / (double)NSEC_PER_MSEC);

    XCTAssertEqual(got, budgetMS);
  }

  XCTBubbleMockVerifyAndClearExpectations(mockESApi.get());
}

- (void)checkDeadlineExpiredFailClosed:(BOOL)shouldFailClosed {
  // Set a es_message_t deadline of 750ms
  // Set a deadline leeway in the `SNTEndpointSecurityClient` of 500ms
  // Mock `RespondFlagsResult` which is called from the deadline handler
  // Signal the semaphore from the mock
  // Wait a few seconds for the semaphore (should take ~250ms)
  //
  // Two semaphotes are used:
  // 1. deadlineSema - used to wait in the handler block until the deadline
  //    block has a chance to execute
  // 2. controlSema - used to block control flow in the test until the
  //    deadlineSema is signaled (or a timeout waiting on deadlineSema)
  es_file_t proc_file = MakeESFile("foo");
  es_process_t proc = MakeESProcess(&proc_file);
  es_file_t fileExec = MakeESFile("target");
  es_process_t procExec = MakeESProcess(&fileExec);
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_AUTH_EXEC, &proc, ActionType::Auth,
                                     750);  // 750ms timeout
  esMsg.event.exec.target = &procExec;

  auto mockESApi = std::make_shared<MockEndpointSecurityAPI>();
  mockESApi->SetExpectationsRetainReleaseMessage();

  dispatch_semaphore_t deadlineSema = dispatch_semaphore_create(0);
  dispatch_semaphore_t controlSema = dispatch_semaphore_create(0);

  es_auth_result_t wantAuthResult = shouldFailClosed ? ES_AUTH_RESULT_DENY : ES_AUTH_RESULT_ALLOW;
  EXPECT_CALL(*mockESApi, RespondAuthResult(testing::_, testing::_, wantAuthResult, false))
      .WillOnce(testing::InvokeWithoutArgs(^() {
        // Signal deadlineSema to let the handler block continue execution
        dispatch_semaphore_signal(deadlineSema);
        return true;
      }));

  id mockConfigurator = OCMClassMock([SNTConfigurator class]);
  OCMStub([mockConfigurator configurator]).andReturn(mockConfigurator);

  OCMExpect([mockConfigurator failClosed]).andReturn(shouldFailClosed);

  SNTEndpointSecurityClient *client =
      [[SNTEndpointSecurityClient alloc] initWithESAPI:mockESApi
                                               metrics:nullptr
                                             processor:Processor::kUnknown];

  // Set min/max headroom the same to clamp the value for this test
  client.minAllowedHeadroom = 500 * NSEC_PER_MSEC;
  client.maxAllowedHeadroom = 500 * NSEC_PER_MSEC;

  {
    __block long result;
    XCTAssertNoThrow([client processMessage:Message(mockESApi, &esMsg)
                                    handler:^(Message msg) {
                                      result = dispatch_semaphore_wait(
                                          deadlineSema,
                                          dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC));

                                      // Once done waiting on deadlineSema, trigger controlSema to
                                      // continue test
                                      dispatch_semaphore_signal(controlSema);
                                    }]);

    XCTAssertEqual(
        0,
        dispatch_semaphore_wait(controlSema, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)),
        "Control sema not signaled within expected time window");

    XCTAssertEqual(result, 0);
  }

  // Allow some time for the threads in `processMessage:handler:` to finish.
  // It isn't critical that they do, but if the dispatch blocks don't complete
  // we may get warnings from GMock about calls to ReleaseMessage after
  // verifying and clearing. Sleep a little bit here to reduce chances of
  // seeing the warning (but still possible)
  SleepMS(100);

  XCTAssertTrue(OCMVerifyAll(mockConfigurator));
  XCTBubbleMockVerifyAndClearExpectations(mockESApi.get());

  [mockConfigurator stopMocking];
}

- (void)testDeadlineExpiredFailClosed {
  [self checkDeadlineExpiredFailClosed:YES];
}

- (void)testDeadlineExpiredFailOpen {
  [self checkDeadlineExpiredFailClosed:NO];
}

@end
