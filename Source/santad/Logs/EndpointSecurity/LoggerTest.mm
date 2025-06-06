/// Copyright 2022 Google Inc. All rights reserved.
/// Copyright 2024 North Pole Security, Inc.
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

#import <Foundation/Foundation.h>
#import <OCMock/OCMock.h>
#import <XCTest/XCTest.h>
#include <gmock/gmock.h>
#include <gtest/gtest.h>

#include <memory>
#include <optional>
#include <string_view>
#include <vector>

#import "Source/common/SNTCommonEnums.h"
#include "Source/common/TelemetryEventMap.h"
#include "Source/common/TestUtils.h"
#include "Source/santad/EventProviders/EndpointSecurity/EnrichedTypes.h"
#include "Source/santad/EventProviders/EndpointSecurity/Message.h"
#include "Source/santad/EventProviders/EndpointSecurity/MockEndpointSecurityAPI.h"
#include "Source/santad/Logs/EndpointSecurity/Logger.h"
#include "Source/santad/Logs/EndpointSecurity/Serializers/BasicString.h"
#include "Source/santad/Logs/EndpointSecurity/Serializers/Empty.h"
#include "Source/santad/Logs/EndpointSecurity/Serializers/Protobuf.h"
#include "Source/santad/Logs/EndpointSecurity/Serializers/Serializer.h"
#include "Source/santad/Logs/EndpointSecurity/Writers/File.h"
#include "Source/santad/Logs/EndpointSecurity/Writers/Null.h"
#include "Source/santad/Logs/EndpointSecurity/Writers/Spool.h"
#include "Source/santad/Logs/EndpointSecurity/Writers/Syslog.h"
#include "Source/santad/Logs/EndpointSecurity/Writers/Writer.h"

using santa::BasicString;
using santa::Empty;
using santa::EnrichedClose;
using santa::EnrichedFile;
using santa::EnrichedMessage;
using santa::EnrichedProcess;
using santa::File;
using santa::Logger;
using santa::Message;
using santa::Null;
using santa::Protobuf;
using santa::Spool;
using santa::Syslog;
using santa::TelemetryEvent;

namespace santa {

class LoggerPeer : public Logger {
 public:
  // Make base class constructors visible
  using Logger::Logger;

  LoggerPeer(std::unique_ptr<Logger> l)
      : Logger(nil, nil, TelemetryEvent::kEverything, l->serializer_, l->writer_) {}

  std::shared_ptr<santa::Serializer> Serializer() { return serializer_; }

  std::shared_ptr<santa::Writer> Writer() { return writer_; }
};

}  // namespace santa

using santa::LoggerPeer;

class MockSerializer : public Empty {
 public:
  MOCK_METHOD(std::vector<uint8_t>, SerializeMessage, (const EnrichedClose &msg));

  MOCK_METHOD(std::vector<uint8_t>, SerializeAllowlist, (const Message &, const std::string_view));

  MOCK_METHOD(std::vector<uint8_t>, SerializeBundleHashingEvent, (SNTStoredEvent *));
  MOCK_METHOD(std::vector<uint8_t>, SerializeDiskAppeared, (NSDictionary *));
  MOCK_METHOD(std::vector<uint8_t>, SerializeDiskDisappeared, (NSDictionary *));

  MOCK_METHOD(std::vector<uint8_t>, SerializeFileAccess,
              (const std::string &policy_version, const std::string &policy_name,
               const santa::Message &msg, const santa::EnrichedProcess &enriched_process,
               const std::string &target, FileAccessPolicyDecision decision,
               std::string_view operation_id),
              (override));

  MOCK_METHOD(std::vector<uint8_t>, SerializeFileAccess,
              (const std::string &policy_version, const std::string &policy_name,
               const santa::Message &msg, const santa::EnrichedProcess &enriched_process,
               const std::string &target, FileAccessPolicyDecision decision),
              (override));
};

class MockWriter : public Null {
 public:
  MOCK_METHOD(void, Write, (std::vector<uint8_t> && bytes));
};

@interface LoggerTest : XCTestCase
@end

@implementation LoggerTest

- (void)testCreate {
  // Ensure that the factory method creates expected serializers/writers pairs
  auto mockESApi = std::make_shared<MockEndpointSecurityAPI>();

  XCTAssertEqual(nullptr, Logger::Create(mockESApi, nil, nil, TelemetryEvent::kEverything,
                                         (SNTEventLogType)123, nil, @"/tmp/temppy", @"/tmp/spool",
                                         1, 1, 1, 1));

  LoggerPeer logger(Logger::Create(mockESApi, nil, nil, TelemetryEvent::kEverything,
                                   SNTEventLogTypeFilelog, nil, @"/tmp/temppy", @"/tmp/spool", 1, 1,
                                   1, 1));
  XCTAssertNotEqual(nullptr, std::dynamic_pointer_cast<BasicString>(logger.Serializer()));
  XCTAssertNotEqual(nullptr, std::dynamic_pointer_cast<File>(logger.Writer()));

  logger = LoggerPeer(Logger::Create(mockESApi, nil, nil, TelemetryEvent::kEverything,
                                     SNTEventLogTypeSyslog, nil, @"/tmp/temppy", @"/tmp/spool", 1,
                                     1, 1, 1));
  XCTAssertNotEqual(nullptr, std::dynamic_pointer_cast<BasicString>(logger.Serializer()));
  XCTAssertNotEqual(nullptr, std::dynamic_pointer_cast<Syslog>(logger.Writer()));

  logger = LoggerPeer(Logger::Create(mockESApi, nil, nil, TelemetryEvent::kEverything,
                                     SNTEventLogTypeNull, nil, @"/tmp/temppy", @"/tmp/spool", 1, 1,
                                     1, 1));
  XCTAssertNotEqual(nullptr, std::dynamic_pointer_cast<Empty>(logger.Serializer()));
  XCTAssertNotEqual(nullptr, std::dynamic_pointer_cast<Null>(logger.Writer()));

  logger = LoggerPeer(Logger::Create(mockESApi, nil, nil, TelemetryEvent::kEverything,
                                     SNTEventLogTypeProtobuf, nil, @"/tmp/temppy", @"/tmp/spool", 1,
                                     1, 1, 1));
  XCTAssertNotEqual(nullptr, std::dynamic_pointer_cast<Protobuf>(logger.Serializer()));
  XCTAssertNotEqual(nullptr, std::dynamic_pointer_cast<Spool>(logger.Writer()));

  logger = LoggerPeer(Logger::Create(mockESApi, nil, nil, TelemetryEvent::kEverything,
                                     SNTEventLogTypeJSON, nil, @"/tmp/temppy", @"/tmp/spool", 1, 1,
                                     1, 1));
  XCTAssertNotEqual(nullptr, std::dynamic_pointer_cast<Protobuf>(logger.Serializer()));
  XCTAssertNotEqual(nullptr, std::dynamic_pointer_cast<File>(logger.Writer()));
}

- (void)testLog {
  auto mockESApi = std::make_shared<MockEndpointSecurityAPI>();
  auto mockSerializer = std::make_shared<MockSerializer>();
  auto mockWriter = std::make_shared<MockWriter>();

  // Ensure all Logger::Log* methods call the serializer followed by the writer
  es_message_t msg;

  mockESApi->SetExpectationsRetainReleaseMessage();

  {
    auto enrichedMsg = std::make_unique<EnrichedMessage>(EnrichedClose(
        Message(mockESApi, &msg),
        EnrichedProcess(std::nullopt, std::nullopt, std::nullopt, std::nullopt,
                        EnrichedFile(std::nullopt, std::nullopt, std::nullopt), std::nullopt),
        EnrichedFile(std::nullopt, std::nullopt, std::nullopt)));

    EXPECT_CALL(*mockSerializer, SerializeMessage(testing::A<const EnrichedClose &>())).Times(1);
    EXPECT_CALL(*mockWriter, Write).Times(1);

    Logger(nil, nil, TelemetryEvent::kEverything, mockSerializer, mockWriter)
        .Log(std::move(enrichedMsg));
  }

  XCTBubbleMockVerifyAndClearExpectations(mockESApi.get());
  XCTBubbleMockVerifyAndClearExpectations(mockSerializer.get());
  XCTBubbleMockVerifyAndClearExpectations(mockWriter.get());
}

- (void)testLogAllowList {
  auto mockESApi = std::make_shared<MockEndpointSecurityAPI>();
  auto mockSerializer = std::make_shared<MockSerializer>();
  auto mockWriter = std::make_shared<MockWriter>();
  es_message_t msg;
  std::string_view hash = "this_is_my_test_hash";

  mockESApi->SetExpectationsRetainReleaseMessage();
  EXPECT_CALL(*mockSerializer, SerializeAllowlist(testing::_, hash));
  EXPECT_CALL(*mockWriter, Write);

  Logger(nil, nil, TelemetryEvent::kEverything, mockSerializer, mockWriter)
      .LogAllowlist(Message(mockESApi, &msg), hash);

  XCTBubbleMockVerifyAndClearExpectations(mockESApi.get());
  XCTBubbleMockVerifyAndClearExpectations(mockSerializer.get());
  XCTBubbleMockVerifyAndClearExpectations(mockWriter.get());
}

- (void)testLogBundleHashingEvents {
  auto mockSerializer = std::make_shared<MockSerializer>();
  auto mockWriter = std::make_shared<MockWriter>();
  NSArray<id> *events = @[ @"event1", @"event2", @"event3" ];

  EXPECT_CALL(*mockSerializer, SerializeBundleHashingEvent).Times((int)[events count]);
  EXPECT_CALL(*mockWriter, Write).Times((int)[events count]);

  Logger(nil, nil, TelemetryEvent::kEverything, mockSerializer, mockWriter)
      .LogBundleHashingEvents(events);

  XCTBubbleMockVerifyAndClearExpectations(mockSerializer.get());
  XCTBubbleMockVerifyAndClearExpectations(mockWriter.get());
}

- (void)testLogDiskAppeared {
  auto mockSerializer = std::make_shared<MockSerializer>();
  auto mockWriter = std::make_shared<MockWriter>();

  EXPECT_CALL(*mockSerializer, SerializeDiskAppeared);
  EXPECT_CALL(*mockWriter, Write);

  Logger(nil, nil, TelemetryEvent::kEverything, mockSerializer, mockWriter).LogDiskAppeared(@{
    @"key" : @"value"
  });

  XCTBubbleMockVerifyAndClearExpectations(mockSerializer.get());
  XCTBubbleMockVerifyAndClearExpectations(mockWriter.get());
}

- (void)testLogDiskDisappeared {
  auto mockSerializer = std::make_shared<MockSerializer>();
  auto mockWriter = std::make_shared<MockWriter>();

  EXPECT_CALL(*mockSerializer, SerializeDiskDisappeared);
  EXPECT_CALL(*mockWriter, Write);

  Logger(nil, nil, TelemetryEvent::kEverything, mockSerializer, mockWriter).LogDiskDisappeared(@{
    @"key" : @"value"
  });

  XCTBubbleMockVerifyAndClearExpectations(mockSerializer.get());
  XCTBubbleMockVerifyAndClearExpectations(mockWriter.get());
}

- (void)testLogFileAccess {
  auto mockESApi = std::make_shared<MockEndpointSecurityAPI>();
  auto mockSerializer = std::make_shared<MockSerializer>();
  auto mockWriter = std::make_shared<MockWriter>();
  es_message_t msg;

  mockESApi->SetExpectationsRetainReleaseMessage();
  using testing::_;
  EXPECT_CALL(*mockSerializer, SerializeFileAccess(_, _, _, _, _, _));
  EXPECT_CALL(*mockWriter, Write);

  Logger(nil, nil, TelemetryEvent::kEverything, mockSerializer, mockWriter)
      .LogFileAccess(
          "v1", "name", Message(mockESApi, &msg),
          EnrichedProcess(std::nullopt, std::nullopt, std::nullopt, std::nullopt,
                          EnrichedFile(std::nullopt, std::nullopt, std::nullopt), std::nullopt),
          "tgt", FileAccessPolicyDecision::kDenied);

  XCTBubbleMockVerifyAndClearExpectations(mockSerializer.get());
  XCTBubbleMockVerifyAndClearExpectations(mockWriter.get());
}

@end
