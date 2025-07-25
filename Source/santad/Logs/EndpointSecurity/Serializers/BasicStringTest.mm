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

#include <EndpointSecurity/EndpointSecurity.h>
#import <Foundation/Foundation.h>
#import <OCMock/OCMock.h>
#import <XCTest/XCTest.h>
#include <bsm/libbsm.h>
#include <gmock/gmock.h>
#include <gtest/gtest.h>

#include <map>
#include <string>

#include "Source/common/Platform.h"
#import "Source/common/SNTCachedDecision.h"
#import "Source/common/SNTCommonEnums.h"
#import "Source/common/SNTConfigurator.h"
#import "Source/common/SNTStoredExecutionEvent.h"
#include "Source/common/TestUtils.h"
#include "Source/santad/EventProviders/EndpointSecurity/EnrichedTypes.h"
#include "Source/santad/EventProviders/EndpointSecurity/Enricher.h"
#include "Source/santad/EventProviders/EndpointSecurity/Message.h"
#include "Source/santad/EventProviders/EndpointSecurity/MockEndpointSecurityAPI.h"
#include "Source/santad/Logs/EndpointSecurity/Serializers/BasicString.h"
#include "Source/santad/Logs/EndpointSecurity/Serializers/Serializer.h"
#import "Source/santad/SNTDecisionCache.h"

using santa::BasicString;
using santa::Enricher;
using santa::Message;
using santa::Serializer;

namespace santa {
extern std::string GetDecisionString(SNTEventState event_state);
extern std::string GetReasonString(SNTEventState event_state);
extern std::string GetModeString(SNTClientMode mode);
extern std::string GetAccessTypeString(es_event_type_t event_type);
extern std::string GetFileAccessPolicyDecisionString(FileAccessPolicyDecision decision);
extern std::string GetAuthenticationTouchIDModeString(es_touchid_mode_t mode);
extern std::string GetAuthenticationAutoUnlockTypeString(es_auto_unlock_type_t mode);
extern std::string GetBTMLaunchItemTypeString(es_btm_item_type_t item_type);
#if HAVE_MACOS_15_4
extern std::string GetTCCIdentityTypeString(es_tcc_identity_type_t id_type);
extern std::string GetTCCEventTypeString(es_tcc_event_type_t event_type);
extern std::string GetTCCAuthorizationRightString(es_tcc_authorization_right_t auth_right);
extern std::string GetTCCAuthorizationReasonString(es_tcc_authorization_reason_t auth_reason);
#endif  // HAVE_MACOS_15_4
}  // namespace santa

std::string BasicStringSerializeMessage(std::shared_ptr<MockEndpointSecurityAPI> mockESApi,
                                        es_message_t *esMsg, SNTDecisionCache *decisionCache) {
  mockESApi->SetExpectationsRetainReleaseMessage();

  std::shared_ptr<Serializer> bs = BasicString::Create(mockESApi, decisionCache, false);
  std::vector<uint8_t> ret = bs->SerializeMessage(Enricher().Enrich(Message(mockESApi, esMsg)));

  XCTBubbleMockVerifyAndClearExpectations(mockESApi.get());

  return std::string(ret.begin(), ret.end());
}

std::string BasicStringSerializeMessage(es_message_t *esMsg) {
  auto mockESApi = std::make_shared<MockEndpointSecurityAPI>();
  return BasicStringSerializeMessage(mockESApi, esMsg, nil);
}

@interface BasicStringTest : XCTestCase
@property id mockConfigurator;
@property id mockDecisionCache;

@property SNTCachedDecision *testCachedDecision;
@end

@implementation BasicStringTest

- (void)setUp {
  self.mockConfigurator = OCMClassMock([SNTConfigurator class]);
  OCMStub([self.mockConfigurator configurator]).andReturn(self.mockConfigurator);
  OCMStub([self.mockConfigurator clientMode]).andReturn(SNTClientModeLockdown);
  OCMStub([self.mockConfigurator enableMachineIDDecoration]).andReturn(YES);
  OCMStub([self.mockConfigurator machineID]).andReturn(@"my_id");

  self.testCachedDecision = [[SNTCachedDecision alloc] init];
  self.testCachedDecision.decision = SNTEventStateAllowBinary;
  self.testCachedDecision.decisionExtra = @"extra!";
  self.testCachedDecision.sha256 = @"1234_hash";
  self.testCachedDecision.quarantineURL = @"google.com";
  self.testCachedDecision.certSHA256 = @"5678_hash";
  self.testCachedDecision.decisionClientMode = SNTClientModeLockdown;

  self.mockDecisionCache = OCMClassMock([SNTDecisionCache class]);
  OCMStub([self.mockDecisionCache sharedCache]).andReturn(self.mockDecisionCache);
  OCMStub([self.mockDecisionCache resetTimestampForCachedDecision:{}])
      .ignoringNonObjectArgs()
      .andReturn(self.testCachedDecision);
}

- (void)tearDown {
  [self.mockConfigurator stopMocking];
  [self.mockDecisionCache stopMocking];
}

- (void)testSerializeMessageClose {
  es_file_t procFile = MakeESFile("foo");
  es_process_t proc = MakeESProcess(&procFile, MakeAuditToken(12, 34), MakeAuditToken(56, 78));
  es_file_t file = MakeESFile("close_file");
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_CLOSE, &proc);
  esMsg.event.close.modified = true;
  esMsg.event.close.target = &file;

  std::string got = BasicStringSerializeMessage(&esMsg);
  std::string want = "action=WRITE|path=close_file"
                     "|pid=12|ppid=56|process=foo|processpath=foo"
                     "|uid=-2|user=nobody|gid=-1|group=nogroup|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);
}

- (void)testSerializeMessageExchange {
  es_file_t procFile = MakeESFile("foo");
  es_process_t proc = MakeESProcess(&procFile, MakeAuditToken(12, 34), MakeAuditToken(56, 78));
  es_file_t file1 = MakeESFile("exchange_1");
  es_file_t file2 = MakeESFile("exchange_2");
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_EXCHANGEDATA, &proc);
  esMsg.event.exchangedata.file1 = &file1;
  esMsg.event.exchangedata.file2 = &file2;

  // Arbitrarily overwriting mock to test not adding machine id in this event
  self.mockConfigurator = OCMClassMock([SNTConfigurator class]);
  OCMStub([self.mockConfigurator configurator]).andReturn(self.mockConfigurator);
  OCMStub([self.mockConfigurator enableMachineIDDecoration]).andReturn(NO);

  std::string got = BasicStringSerializeMessage(&esMsg);
  std::string want = "action=EXCHANGE|path=exchange_1|newpath=exchange_2"
                     "|pid=12|ppid=56|process=foo|processpath=foo"
                     "|uid=-2|user=nobody|gid=-1|group=nogroup\n";

  XCTAssertCppStringEqual(got, want);
}

- (void)testSerializeMessageExec {
  es_file_t procFile = MakeESFile("foo");
  es_process_t proc = MakeESProcess(&procFile, MakeAuditToken(12, 34), MakeAuditToken(56, 78));

  es_file_t execFile = MakeESFile("execpath|");
  es_process_t procExec = MakeESProcess(&execFile, MakeAuditToken(12, 89), MakeAuditToken(56, 78));

  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_EXEC, &proc);
  esMsg.event.exec.target = &procExec;

  auto mockESApi = std::make_shared<MockEndpointSecurityAPI>();
  EXPECT_CALL(*mockESApi, ExecArgCount).WillOnce(testing::Return(3));

  EXPECT_CALL(*mockESApi, ExecArg)
      .WillOnce(testing::Return(es_string_token_t{9, "exec|path"}))
      .WillOnce(testing::Return(es_string_token_t{5, "-l\n-t"}))
      .WillOnce(testing::Return(es_string_token_t{8, "-v\r--foo"}));

  std::string got = BasicStringSerializeMessage(mockESApi, &esMsg, self.mockDecisionCache);
  std::string want =
      "action=EXEC|decision=ALLOW|reason=BINARY|explain=extra!|sha256=1234_hash|"
      "cert_sha256=5678_hash|cert_cn=|quarantine_url=google.com|pid=12|pidversion="
      "89|ppid=56|uid=-2|user=nobody|gid=-1|group=nogroup|mode=L|path=execpath<pipe>|"
      "args=exec<pipe>path -l\\n-t -v\\r--foo|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);
}

- (void)testSerializeMessageExit {
  es_file_t procFile = MakeESFile("foo");
  es_process_t proc = MakeESProcess(&procFile, MakeAuditToken(12, 34), MakeAuditToken(56, 78));
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_EXIT, &proc);

  std::string got = BasicStringSerializeMessage(&esMsg);
  std::string want = "action=EXIT|pid=12|pidversion=34|ppid=56|uid=-2|gid=-1|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);
}

- (void)testSerializeMessageFork {
  es_file_t procFile = MakeESFile("foo");
  es_file_t procChildFile = MakeESFile("foo_child");
  es_process_t proc = MakeESProcess(&procFile, MakeAuditToken(12, 34), MakeAuditToken(56, 78));
  es_process_t procChild =
      MakeESProcess(&procChildFile, MakeAuditToken(67, 89), MakeAuditToken(12, 34));
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_FORK, &proc);
  esMsg.event.fork.child = &procChild;

  std::string got = BasicStringSerializeMessage(&esMsg);
  std::string want = "action=FORK|pid=67|pidversion=89|ppid=12|uid=-2|gid=-1|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);
}

- (void)testSerializeMessageLink {
  es_file_t procFile = MakeESFile("foo");
  es_file_t srcFile = MakeESFile("link_src");
  es_file_t dstDir = MakeESFile("link_dst");
  es_process_t proc = MakeESProcess(&procFile, MakeAuditToken(12, 34), MakeAuditToken(56, 78));
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_LINK, &proc);
  esMsg.event.link.source = &srcFile;
  esMsg.event.link.target_dir = &dstDir;
  esMsg.event.link.target_filename = MakeESStringToken("link_name");

  std::string got = BasicStringSerializeMessage(&esMsg);
  std::string want = "action=LINK|path=link_src|newpath=link_dst/link_name"
                     "|pid=12|ppid=56|process=foo|processpath=foo"
                     "|uid=-2|user=nobody|gid=-1|group=nogroup|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);
}

- (void)testSerializeMessageRename {
  es_file_t procFile = MakeESFile("foo");
  es_file_t srcFile = MakeESFile("rename_src");
  es_file_t dstFile = MakeESFile("rename_dst");
  es_process_t proc = MakeESProcess(&procFile, MakeAuditToken(12, 34), MakeAuditToken(56, 78));
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_RENAME, &proc);
  esMsg.event.rename.source = &srcFile;
  esMsg.event.rename.destination_type = ES_DESTINATION_TYPE_EXISTING_FILE;
  esMsg.event.rename.destination.existing_file = &dstFile;

  std::string got = BasicStringSerializeMessage(&esMsg);
  std::string want = "action=RENAME|path=rename_src|newpath=rename_dst"
                     "|pid=12|ppid=56|process=foo|processpath=foo"
                     "|uid=-2|user=nobody|gid=-1|group=nogroup|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);
}

- (void)testSerializeMessageUnlink {
  es_file_t procFile = MakeESFile("foo");
  es_file_t targetFile = MakeESFile("deleted_file");
  es_process_t proc = MakeESProcess(&procFile, MakeAuditToken(12, 34), MakeAuditToken(56, 78));
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_UNLINK, &proc);
  esMsg.event.unlink.target = &targetFile;

  std::string got = BasicStringSerializeMessage(&esMsg);
  std::string want = "action=DELETE|path=deleted_file"
                     "|pid=12|ppid=56|process=foo|processpath=foo"
                     "|uid=-2|user=nobody|gid=-1|group=nogroup|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);
}

- (void)testSerializeMessageCSInvalidated {
  es_file_t procFile = MakeESFile("foo");
  es_process_t proc = MakeESProcess(&procFile, MakeAuditToken(12, 34), MakeAuditToken(56, 78));
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_CS_INVALIDATED, &proc);

  std::string got = BasicStringSerializeMessage(&esMsg);
  std::string want =
      "action=CODESIGNING_INVALIDATED"
      "|pid=12|ppid=56|process=foo|processpath=foo"
      "|uid=-2|user=nobody|gid=-1|group=nogroup|codesigning_flags=0x00000000|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);
}

- (void)testSerializeMessageClone {
  es_file_t procFile = MakeESFile("foo");
  es_file_t srcFile = MakeESFile("clone_src");
  es_file_t targetDirFile = MakeESFile("target_dir");
  es_process_t proc = MakeESProcess(&procFile, MakeAuditToken(12, 34), MakeAuditToken(56, 78));
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_CLONE, &proc);
  esMsg.event.clone.source = &srcFile;
  esMsg.event.clone.target_dir = &targetDirFile;
  esMsg.event.clone.target_name = MakeESStringToken("target_name");

  std::string got = BasicStringSerializeMessage(&esMsg);
  std::string want = "action=CLONE|source=clone_src|target=target_dir/target_name"
                     "|pid=12|ppid=56|process=foo|processpath=foo"
                     "|uid=-2|user=nobody|gid=-1|group=nogroup|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);
}

- (void)testSerializeMessageCopyfile {
  es_file_t procFile = MakeESFile("foo");
  es_file_t srcFile = MakeESFile("copyfile_src");
  es_file_t targetDirFile = MakeESFile("target_dir");
  es_process_t proc = MakeESProcess(&procFile, MakeAuditToken(12, 34), MakeAuditToken(56, 78));
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_COPYFILE, &proc);
  esMsg.event.copyfile.source = &srcFile;
  esMsg.event.copyfile.target_dir = &targetDirFile;
  esMsg.event.copyfile.target_name = MakeESStringToken("target_name");

  std::string got = BasicStringSerializeMessage(&esMsg);
  std::string want = "action=COPYFILE|source=copyfile_src|target=target_dir/target_name"
                     "|pid=12|ppid=56|process=foo|processpath=foo"
                     "|uid=-2|user=nobody|gid=-1|group=nogroup|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);
}

- (void)testSerializeMessageLoginWindowSessionLogin {
  es_file_t procFile = MakeESFile("foo");
  es_process_t proc = MakeESProcess(&procFile, MakeAuditToken(12, 34), MakeAuditToken(56, 78));
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_LW_SESSION_LOGIN, &proc);
  es_event_lw_session_login_t lwLogin = {
      .username = MakeESStringToken("daemon"),
      .graphical_session_id = 123,
  };

  esMsg.event.lw_session_login = &lwLogin;

  std::string got = BasicStringSerializeMessage(&esMsg);
  std::string want = "action=LOGIN_WINDOW_SESSION_LOGIN|pid=12|ppid=56|process=foo|processpath=foo|"
                     "uid=-2|user=nobody|gid=-1|group=nogroup|event_user=daemon|event_uid=1|"
                     "graphical_session_id=123|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);
}

- (void)testSerializeMessageLoginWindowSessionLogout {
  es_file_t procFile = MakeESFile("foo");
  es_process_t proc = MakeESProcess(&procFile, MakeAuditToken(12, 34), MakeAuditToken(56, 78));
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_LW_SESSION_LOGOUT, &proc);
  es_event_lw_session_logout_t lwLogout = {
      .username = MakeESStringToken("daemon"),
      .graphical_session_id = 123,
  };

  esMsg.event.lw_session_logout = &lwLogout;

  std::string got = BasicStringSerializeMessage(&esMsg);
  std::string want = "action=LOGIN_WINDOW_SESSION_LOGOUT|pid=12|ppid=56|process=foo|processpath="
                     "foo|uid=-2|user=nobody|gid=-1|group=nogroup|event_user=daemon|event_uid=1|"
                     "graphical_session_id=123|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);
}

- (void)testSerializeMessageLoginWindowSessionLock {
  es_file_t procFile = MakeESFile("foo");
  es_process_t proc = MakeESProcess(&procFile, MakeAuditToken(12, 34), MakeAuditToken(56, 78));
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_LW_SESSION_LOCK, &proc);
  es_event_lw_session_lock_t lwLock = {
      .username = MakeESStringToken("daemon"),
      .graphical_session_id = 123,
  };

  esMsg.event.lw_session_lock = &lwLock;

  std::string got = BasicStringSerializeMessage(&esMsg);
  std::string want = "action=LOGIN_WINDOW_SESSION_LOCK|pid=12|ppid=56|process=foo|processpath=foo|"
                     "uid=-2|user=nobody|gid=-1|group=nogroup|event_user=daemon|event_uid=1|"
                     "graphical_session_id=123|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);
}

- (void)testSerializeMessageLoginWindowSessionUnlock {
  es_file_t procFile = MakeESFile("foo");
  es_process_t proc = MakeESProcess(&procFile, MakeAuditToken(12, 34), MakeAuditToken(56, 78));
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_LW_SESSION_UNLOCK, &proc);
  es_event_lw_session_unlock_t lwUnlock = {
      .username = MakeESStringToken("daemon"),
      .graphical_session_id = 123,
  };

  esMsg.event.lw_session_unlock = &lwUnlock;

  std::string got = BasicStringSerializeMessage(&esMsg);
  std::string want = "action=LOGIN_WINDOW_SESSION_UNLOCK|pid=12|ppid=56|process=foo|processpath="
                     "foo|uid=-2|user=nobody|gid=-1|group=nogroup|event_user=daemon|event_uid=1|"
                     "graphical_session_id=123|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);
}

- (void)testSerializeMessageLoginLogin {
  es_file_t procFile = MakeESFile("foo");
  es_process_t proc = MakeESProcess(&procFile, MakeAuditToken(12, 34), MakeAuditToken(56, 78));
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_LOGIN_LOGIN, &proc);
  es_event_login_login_t login = {
      .success = false,
      .failure_message = MakeESStringToken("my|failure"),
      .username = MakeESStringToken("asdf"),
      .has_uid = false,
  };
  esMsg.event.login_login = &login;

  std::string got = BasicStringSerializeMessage(&esMsg);
  std::string want = "action=LOGIN|success=false|failure=my<pipe>failure|pid=12|ppid=56|process="
                     "foo|processpath=foo|"
                     "uid=-2|user=nobody|gid=-1|group=nogroup|event_user=asdf|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);

  login.success = true;
  login.has_uid = true;
  login.uid.uid = 123;

  got = BasicStringSerializeMessage(&esMsg);
  want = "action=LOGIN|success=true|pid=12|ppid=56|process=foo|processpath=foo|uid=-2|user=nobody|"
         "gid=-1|group=nogroup|event_user=asdf|event_uid=123|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);
}

- (void)testSerializeMessageLoginLogout {
  es_file_t procFile = MakeESFile("foo");
  es_process_t proc = MakeESProcess(&procFile, MakeAuditToken(12, 34), MakeAuditToken(56, 78));
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_LOGIN_LOGOUT, &proc);
  es_event_login_logout_t logout{
      .username = MakeESStringToken("asdf"),
      .uid = 123,
  };
  esMsg.event.login_logout = &logout;

  std::string got = BasicStringSerializeMessage(&esMsg);
  std::string want = "action=LOGOUT|pid=12|ppid=56|process=foo|processpath=foo|uid=-2|user=nobody|"
                     "gid=-1|group=nogroup|event_user=asdf|event_uid=123|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);
}

- (void)testSerializeMessageScreenSharingAttach {
  es_file_t procFile = MakeESFile("foo");
  es_process_t proc = MakeESProcess(&procFile, MakeAuditToken(12, 34), MakeAuditToken(56, 78));
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_SCREENSHARING_ATTACH, &proc);
  es_event_screensharing_attach_t attach{
      .success = true,
      .source_address_type = ES_ADDRESS_TYPE_IPV6,
      .source_address = MakeESStringToken("::1"),
      .viewer_appleid = MakeESStringToken("foo@example.com"),
      .authentication_type = MakeESStringToken("idk"),
      .authentication_username = MakeESStringToken("my_auth_user"),
      .session_username = MakeESStringToken("my_session_user"),
      .existing_session = true,
      .graphical_session_id = 123,
  };
  esMsg.event.screensharing_attach = &attach;

  std::string got = BasicStringSerializeMessage(&esMsg);
  std::string want =
      "action=SCREEN_SHARING_ATTACH|success=true|address_type=ipv6|address=::1|viewer=foo@example."
      "com|auth_type=idk|auth_user=my_auth_user|session_user=my_session_user|existing_session=true|"
      "pid=12|ppid=56|process=foo|processpath=foo|uid=-2|user=nobody|gid=-1|group=nogroup|"
      "graphical_"
      "session_id=123|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);

  attach.source_address_type = (es_address_type_t)1234;  // Intentionally bad
  attach.source_address = MakeESStringToken(NULL);
  attach.viewer_appleid = MakeESStringToken(NULL);
  attach.authentication_type = MakeESStringToken(NULL);
  attach.authentication_username = MakeESStringToken(NULL);
  attach.session_username = MakeESStringToken(NULL);

  got = BasicStringSerializeMessage(&esMsg);
  want = "action=SCREEN_SHARING_ATTACH|success=true|address_type=unknown|existing_session=true|pid="
         "12|ppid=56|process=foo|processpath=foo|uid=-2|user=nobody|gid=-1|group=nogroup|graphical_"
         "session_id=123|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);
}

- (void)testSerializeMessageScreenSharingDetach {
  es_file_t procFile = MakeESFile("foo");
  es_process_t proc = MakeESProcess(&procFile, MakeAuditToken(12, 34), MakeAuditToken(56, 78));
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_SCREENSHARING_DETACH, &proc);
  es_event_screensharing_detach_t detach{
      .source_address_type = ES_ADDRESS_TYPE_IPV4,
      .source_address = MakeESStringToken("1.2.3.4"),
      .viewer_appleid = MakeESStringToken("foo@example.com"),
      .graphical_session_id = 123,
  };
  esMsg.event.screensharing_detach = &detach;

  std::string got = BasicStringSerializeMessage(&esMsg);
  std::string want = "action=SCREEN_SHARING_DETACH|address_type=ipv4|address=1.2.3.4|viewer=foo@"
                     "example.com|pid=12|ppid=56|process=foo|processpath=foo|uid=-2|user=nobody|"
                     "gid=-1|group=nogroup|graphical_session_id=123|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);
}

- (void)testSerializeMessageOpenSSHLogin {
  es_file_t procFile = MakeESFile("foo");
  es_process_t proc = MakeESProcess(&procFile, MakeAuditToken(12, 34), MakeAuditToken(56, 78));
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_OPENSSH_LOGIN, &proc);
  es_event_openssh_login_t login{
      .success = false,
      .result_type = ES_OPENSSH_AUTH_FAIL_PASSWD,
      .source_address_type = ES_ADDRESS_TYPE_NAMED_SOCKET,
      .source_address = MakeESStringToken("foo"),
      .username = MakeESStringToken("my_user"),
      .has_uid = false,
  };
  esMsg.event.openssh_login = &login;

  std::string got = BasicStringSerializeMessage(&esMsg);
  std::string want = "action=OPENSSH_LOGIN|success=false|result_type=AUTH_FAIL_PASSWD|address_type="
                     "named_socket|address=foo|pid=12|ppid=56|process=foo|processpath=foo|uid=-2|"
                     "user=nobody|gid=-1|group=nogroup|event_user=my_user|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);

  login.success = true;
  login.result_type = ES_OPENSSH_AUTH_SUCCESS;
  login.has_uid = true;
  login.uid.uid = 456;

  got = BasicStringSerializeMessage(&esMsg);
  want = "action=OPENSSH_LOGIN|success=true|result_type=AUTH_SUCCESS|address_type=named_socket|"
         "address=foo|pid=12|ppid=56|process=foo|processpath=foo|uid=-2|user=nobody|gid=-1|group="
         "nogroup|event_user=my_user|event_uid=456|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);
}

- (void)testSerializeMessageOpenSSHLogout {
  es_file_t procFile = MakeESFile("foo");
  es_process_t proc = MakeESProcess(&procFile, MakeAuditToken(12, 34), MakeAuditToken(56, 78));
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_OPENSSH_LOGOUT, &proc);
  es_event_openssh_logout_t logout{
      .source_address_type = ES_ADDRESS_TYPE_IPV4,
      .source_address = MakeESStringToken("5.6.7.8"),
      .username = MakeESStringToken("my_user"),
      .uid = 321,
  };
  esMsg.event.openssh_logout = &logout;

  std::string got = BasicStringSerializeMessage(&esMsg);
  std::string want = "action=OPENSSH_LOGOUT|address_type=ipv4|address=5.6.7.8|pid=12|ppid=56|"
                     "process=foo|processpath=foo|uid=-2|user=nobody|gid=-1|group=nogroup|event_"
                     "user=my_user|event_uid=321|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);
}

- (void)testGetAuthenticationTouchIDModeString {
  std::map<es_touchid_mode_t, std::string> touchIDModeToString{
      {ES_TOUCHID_MODE_VERIFICATION, "VERIFICATION"},
      {ES_TOUCHID_MODE_IDENTIFICATION, "IDENTIFICATION"},
      {(es_touchid_mode_t)1234, "UNKNOWN"},
  };

  for (const auto &kv : touchIDModeToString) {
    XCTAssertCppStringEqual(santa::GetAuthenticationTouchIDModeString(kv.first), kv.second);
  }
}

- (void)testSerializeMessageAuthenticationOD {
  es_file_t procFile = MakeESFile("foo");
  es_process_t proc = MakeESProcess(&procFile, MakeAuditToken(12, 34), MakeAuditToken(56, 78));
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_AUTHENTICATION, &proc);

  es_file_t instigatorProcFile = MakeESFile("foo");
  es_process_t instigatorProc =
      MakeESProcess(&instigatorProcFile, MakeAuditToken(21, 43), MakeAuditToken(65, 87));

  es_event_authentication_od_t od = {
      .instigator = &instigatorProc,
      .record_type = MakeESStringToken("my_rec_type"),
      .record_name = MakeESStringToken("my_rec_name"),
      .node_name = MakeESStringToken("my_node_name"),
      .db_path = MakeESStringToken("my_db_path"),
#if HAVE_MACOS_15
      .instigator_token = MakeAuditToken(654, 321),
#endif
  };

  es_event_authentication_t auth = {
      .success = true,
      .type = ES_AUTHENTICATION_TYPE_OD,
      .data = {.od = &od},
  };

  esMsg.event.authentication = &auth;
  esMsg.version = 8;

  std::string got = BasicStringSerializeMessage(&esMsg);
  std::string want =
      "action=AUTHENTICATION_OD|success=true|pid=12|ppid=56|process=foo|processpath=foo"
      "|uid=-2|user=nobody|gid=-1|group=nogroup|auth_pid=21|auth_ppid=65|auth_process=foo"
      "|auth_processpath=foo|auth_uid=-2|auth_user=nobody|auth_gid=-1|auth_group=nogroup"
      "|record_type=my_rec_type|record_name=my_rec_name|node_name=my_node_name"
      "|db_path=my_db_path|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);

  // Simulate the auth instigator process exiting and only the fallback token exists
  od.instigator = NULL;

  got = BasicStringSerializeMessage(&esMsg);
#if HAVE_MACOS_15
  want = "action=AUTHENTICATION_OD|success=true|pid=12|ppid=56|process=foo|processpath=foo|uid=-2"
         "|user=nobody|gid=-1|group=nogroup|auth_pid=654|auth_pidver=321|record_type=my_rec_type"
         "|record_name=my_rec_name|node_name=my_node_name|db_path=my_db_path|machineid=my_id\n";
#else
  want = "action=AUTHENTICATION_OD|success=true|pid=12|ppid=56|process=foo|processpath=foo|uid=-2"
         "|user=nobody|gid=-1|group=nogroup|record_type=my_rec_type|record_name=my_rec_name"
         "|node_name=my_node_name|db_path=my_db_path|machineid=my_id\n";
#endif

  XCTAssertCppStringEqual(got, want);

  // This state shouldn't be possible to exist in older macOS versions where if the instigator
  // process was null, the message was dropped by the kernel and not sent to the client. However
  // testing this here as a preventative measure as this behavior isn't documented by ES.
  esMsg.version = 7;
  // db path is listed as optional. Ensure that is handled.
  od.db_path = MakeESStringToken(NULL);

  got = BasicStringSerializeMessage(&esMsg);
  want = "action=AUTHENTICATION_OD|success=true|pid=12|ppid=56|process=foo|processpath=foo|uid=-2"
         "|user=nobody|gid=-1|group=nogroup|record_type=my_rec_type|record_name=my_rec_name"
         "|node_name=my_node_name|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);
}

- (void)testSerializeMessageAuthenticationTouchID {
  es_file_t procFile = MakeESFile("foo");
  es_process_t proc = MakeESProcess(&procFile, MakeAuditToken(12, 34), MakeAuditToken(56, 78));
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_AUTHENTICATION, &proc);

  es_file_t instigatorProcFile = MakeESFile("foo");
  es_process_t instigatorProc =
      MakeESProcess(&instigatorProcFile, MakeAuditToken(21, 43), MakeAuditToken(65, 87));

  es_event_authentication_touchid_t touchid = {
      .instigator = &instigatorProc,
      .touchid_mode = ES_TOUCHID_MODE_VERIFICATION,
      .has_uid = true,
      .uid = {.uid = NOBODY_UID},
#if HAVE_MACOS_15
      .instigator_token = MakeAuditToken(654, 321),
#endif
  };

  es_event_authentication_t auth = {
      .success = true,
      .type = ES_AUTHENTICATION_TYPE_TOUCHID,
      .data = {.touchid = &touchid},
  };

  esMsg.event.authentication = &auth;
  esMsg.version = 8;

  std::string got = BasicStringSerializeMessage(&esMsg);
  std::string want =
      "action=AUTHENTICATION_TOUCHID|success=true|pid=12|ppid=56|process=foo|processpath=foo"
      "|uid=-2|user=nobody|gid=-1|group=nogroup|auth_pid=21|auth_ppid=65|auth_process=foo"
      "|auth_processpath=foo|auth_uid=-2|auth_user=nobody|auth_gid=-1|auth_group=nogroup"
      "|touchid_mode=VERIFICATION|event_user=nobody|event_uid=-2|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);

  // Simulate the auth instigator process exiting and only the fallback token exists
  touchid.instigator = NULL;

  got = BasicStringSerializeMessage(&esMsg);
#if HAVE_MACOS_15
  want = "action=AUTHENTICATION_TOUCHID|success=true|pid=12|ppid=56|process=foo|processpath=foo"
         "|uid=-2|user=nobody|gid=-1|group=nogroup|auth_pid=654|auth_pidver=321"
         "|touchid_mode=VERIFICATION|event_user=nobody|event_uid=-2|machineid=my_id\n";
#else
  want = "action=AUTHENTICATION_TOUCHID|success=true|pid=12|ppid=56|process=foo|processpath=foo"
         "|uid=-2|user=nobody|gid=-1|group=nogroup|touchid_mode=VERIFICATION|event_user=nobody"
         "|event_uid=-2|machineid=my_id\n";
#endif

  XCTAssertCppStringEqual(got, want);

  // This state shouldn't be possible to exist in older macOS versions where if the instigator
  // process was null, the message was dropped by the kernel and not sent to the client. However
  // testing this here as a preventative measure as this behavior isn't documented by ES.
  esMsg.version = 7;
  touchid.has_uid = false;

  got = BasicStringSerializeMessage(&esMsg);
  want = "action=AUTHENTICATION_TOUCHID|success=true|pid=12|ppid=56|process=foo|processpath=foo"
         "|uid=-2|user=nobody|gid=-1|group=nogroup|touchid_mode=VERIFICATION|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);
}

- (void)testSerializeMessageAuthenticationToken {
  es_file_t procFile = MakeESFile("foo");
  es_process_t proc = MakeESProcess(&procFile, MakeAuditToken(12, 34), MakeAuditToken(56, 78));
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_AUTHENTICATION, &proc);

  es_file_t instigatorProcFile = MakeESFile("foo");
  es_process_t instigatorProc =
      MakeESProcess(&instigatorProcFile, MakeAuditToken(21, 43), MakeAuditToken(65, 87));

  es_event_authentication_token_t token = {
      .instigator = &instigatorProc,
      .pubkey_hash = MakeESStringToken("abc123"),
      .token_id = MakeESStringToken("my_tok_id"),
      .kerberos_principal = MakeESStringToken("my_kerberos_principal"),
#if HAVE_MACOS_15
      .instigator_token = MakeAuditToken(654, 321),
#endif
  };

  es_event_authentication_t auth = {
      .success = true,
      .type = ES_AUTHENTICATION_TYPE_TOKEN,
      .data = {.token = &token},
  };

  esMsg.event.authentication = &auth;
  esMsg.version = 8;

  std::string got = BasicStringSerializeMessage(&esMsg);
  std::string want =
      "action=AUTHENTICATION_TOKEN|success=true|pid=12|ppid=56|process=foo|processpath=foo"
      "|uid=-2|user=nobody|gid=-1|group=nogroup|auth_pid=21|auth_ppid=65|auth_process=foo"
      "|auth_processpath=foo|auth_uid=-2|auth_user=nobody|auth_gid=-1|auth_group=nogroup"
      "|pubkey_hash=abc123|token_id=my_tok_id|kerberos_principal=my_kerberos_principal"
      "|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);

  // Simulate the auth instigator process exiting and only the fallback token exists
  token.instigator = NULL;

  got = BasicStringSerializeMessage(&esMsg);
#if HAVE_MACOS_15
  want = "action=AUTHENTICATION_TOKEN|success=true|pid=12|ppid=56|process=foo|processpath=foo"
         "|uid=-2|user=nobody|gid=-1|group=nogroup|auth_pid=654|auth_pidver=321|pubkey_hash=abc123"
         "|token_id=my_tok_id|kerberos_principal=my_kerberos_principal|machineid=my_id\n";
#else
  want = "action=AUTHENTICATION_TOKEN|success=true|pid=12|ppid=56|process=foo|processpath=foo"
         "|uid=-2|user=nobody|gid=-1|group=nogroup|pubkey_hash=abc123|token_id=my_tok_id"
         "|kerberos_principal=my_kerberos_principal|machineid=my_id\n";
#endif

  XCTAssertCppStringEqual(got, want);

  // This state shouldn't be possible to exist in older macOS versions where if the instigator
  // process was null, the message was dropped by the kernel and not sent to the client. However
  // testing this here as a preventative measure as this behavior isn't documented by ES.
  esMsg.version = 7;
  token.kerberos_principal = MakeESStringToken(NULL);

  got = BasicStringSerializeMessage(&esMsg);
  want = "action=AUTHENTICATION_TOKEN|success=true|pid=12|ppid=56|process=foo|processpath=foo"
         "|uid=-2|user=nobody|gid=-1|group=nogroup|pubkey_hash=abc123|token_id=my_tok_id"
         "|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);
}

- (void)testGetAuthenticationAutoUnlockTypeString {
  std::map<es_auto_unlock_type_t, std::string> autoUnlockTypeToString{
      {ES_AUTO_UNLOCK_MACHINE_UNLOCK, "MACHINE_UNLOCK"},
      {ES_AUTO_UNLOCK_AUTH_PROMPT, "AUTH_PROMPT"},
      {(es_auto_unlock_type_t)1234, "UNKNOWN"},
  };

  for (const auto &kv : autoUnlockTypeToString) {
    XCTAssertCppStringEqual(santa::GetAuthenticationAutoUnlockTypeString(kv.first), kv.second);
  }
}

- (void)testSerializeMessageAuthenticationAutoUnlock {
  es_file_t procFile = MakeESFile("foo");
  es_process_t proc = MakeESProcess(&procFile, MakeAuditToken(12, 34), MakeAuditToken(56, 78));
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_AUTHENTICATION, &proc);

  es_event_authentication_auto_unlock_t auto_unlock = {
      .username = MakeESStringToken("daemon"),
      .type = ES_AUTO_UNLOCK_MACHINE_UNLOCK,
  };

  es_event_authentication_t auth = {
      .success = true,
      .type = ES_AUTHENTICATION_TYPE_AUTO_UNLOCK,
      .data = {.auto_unlock = &auto_unlock},
  };

  esMsg.event.authentication = &auth;
  esMsg.version = 8;

  std::string got = BasicStringSerializeMessage(&esMsg);
  std::string want = "action=AUTHENTICATION_AUTO_UNLOCK|success=true|pid=12|ppid=56|process=foo"
                     "|processpath=foo|uid=-2|user=nobody|gid=-1|group=nogroup|event_user=daemon"
                     "|event_uid=1|type=MACHINE_UNLOCK|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);
}

- (void)testGetBTMLaunchItemTypeString {
  std::map<es_btm_item_type_t, std::string> launchItemTypeToString{
      {ES_BTM_ITEM_TYPE_USER_ITEM, "USER_ITEM"},   {ES_BTM_ITEM_TYPE_APP, "APP"},
      {ES_BTM_ITEM_TYPE_LOGIN_ITEM, "LOGIN_ITEM"}, {ES_BTM_ITEM_TYPE_AGENT, "AGENT"},
      {ES_BTM_ITEM_TYPE_DAEMON, "DAEMON"},         {(es_btm_item_type_t)1234, "UNKNOWN"},
  };

  for (const auto &kv : launchItemTypeToString) {
    XCTAssertCppStringEqual(santa::GetBTMLaunchItemTypeString(kv.first), kv.second);
  }
}

- (void)testSerializeMessageLaunchItemAdd {
  es_file_t procFile = MakeESFile("foo");
  es_process_t proc = MakeESProcess(&procFile, MakeAuditToken(12, 34), MakeAuditToken(56, 78));
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_BTM_LAUNCH_ITEM_ADD, &proc);

  es_file_t instigatorProcFile = MakeESFile("fooInst");
  es_process_t instigatorProc =
      MakeESProcess(&instigatorProcFile, MakeAuditToken(21, 43), MakeAuditToken(65, 87));

  es_file_t instigatorAppFile = MakeESFile("fooApp");
  es_process_t instigatorApp =
      MakeESProcess(&instigatorAppFile, MakeAuditToken(21, 43), MakeAuditToken(65, 87));
#if HAVE_MACOS_15
  audit_token_t tokInst = MakeAuditToken(654, 321);
  audit_token_t tokApp = MakeAuditToken(111, 222);
#endif

  es_btm_launch_item_t item = {
      .item_type = ES_BTM_ITEM_TYPE_USER_ITEM,
      .legacy = true,
      .managed = false,
      .uid = (uid_t)-2,
      .item_url = MakeESStringToken("/absolute/path/item"),
      .app_url = MakeESStringToken("/absolute/path/app"),
  };

  es_event_btm_launch_item_add_t launchItem = {
      .instigator = &instigatorProc,
      .app = &instigatorApp,
      .item = &item,
      .executable_path = MakeESStringToken("exec_path"),
#if HAVE_MACOS_15
      .instigator_token = &tokInst,
      .app_token = &tokApp,
#endif
  };

  esMsg.event.btm_launch_item_add = &launchItem;
  esMsg.version = 8;

  std::string got = BasicStringSerializeMessage(&esMsg);
  std::string want =
      "action=LAUNCH_ITEM_ADD|item_type=USER_ITEM|legacy=true|managed=false"
      "|item_user=nobody|item_uid=-2|exec_path=/absolute/path/app/exec_path"
      "|item_path=/absolute/path/item|app_path=/absolute/path/app"
      "|event_pid=21|event_ppid=65|event_process=fooInst|event_processpath=fooInst"
      "|event_uid=-2|event_user=nobody|event_gid=-1|event_group=nogroup|pid=12|ppid=56"
      "|process=foo|processpath=foo|uid=-2|user=nobody|gid=-1|group=nogroup|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);

  launchItem.instigator = NULL;
  item.item_url = MakeESStringToken("relative/path");
  item.app_url = MakeESStringToken("file:///path/url");
  item.item_type = ES_BTM_ITEM_TYPE_DAEMON;

  got = BasicStringSerializeMessage(&esMsg);
#if HAVE_MACOS_15
  want = "action=LAUNCH_ITEM_ADD|item_type=DAEMON|legacy=true|managed=false"
         "|item_user=nobody|item_uid=-2|exec_path=/path/url/exec_path"
         "|item_path=/path/url/relative/path|app_path=/path/url"
         "|event_pid=654|event_pidver=321|pid=12|ppid=56|process=foo|processpath=foo"
         "|uid=-2|user=nobody|gid=-1|group=nogroup|machineid=my_id\n";
#else
  want = "action=LAUNCH_ITEM_ADD|item_type=DAEMON|legacy=true|managed=false"
         "|item_user=nobody|item_uid=-2|exec_path=/path/url/exec_path"
         "|item_path=/path/url/relative/path|app_path=/path/url"
         "|pid=12|ppid=56|process=foo|processpath=foo"
         "|uid=-2|user=nobody|gid=-1|group=nogroup|machineid=my_id\n";
#endif

  XCTAssertCppStringEqual(got, want);

  item.app_url = MakeESStringToken(NULL);
  item.item_type = ES_BTM_ITEM_TYPE_AGENT;

  got = BasicStringSerializeMessage(&esMsg);
#if HAVE_MACOS_15
  want = "action=LAUNCH_ITEM_ADD|item_type=AGENT|legacy=true|managed=false"
         "|item_user=nobody|item_uid=-2|exec_path=exec_path"
         "|item_path=relative/path|event_pid=654|event_pidver=321|pid=12|ppid=56"
         "|process=foo|processpath=foo|uid=-2|user=nobody|gid=-1|group=nogroup|machineid=my_id\n";
#else
  want = "action=LAUNCH_ITEM_ADD|item_type=AGENT|legacy=true|managed=false"
         "|item_user=nobody|item_uid=-2|exec_path=exec_path"
         "|item_path=relative/path|pid=12|ppid=56"
         "|process=foo|processpath=foo|uid=-2|user=nobody|gid=-1|group=nogroup|machineid=my_id\n";
#endif

  XCTAssertCppStringEqual(got, want);
}

- (void)testSerializeMessageLaunchItemRemove {
  es_file_t procFile = MakeESFile("foo");
  es_process_t proc = MakeESProcess(&procFile, MakeAuditToken(12, 34), MakeAuditToken(56, 78));
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_BTM_LAUNCH_ITEM_REMOVE, &proc);

  es_file_t instigatorProcFile = MakeESFile("fooInst");
  es_process_t instigatorProc =
      MakeESProcess(&instigatorProcFile, MakeAuditToken(21, 43), MakeAuditToken(65, 87));

  es_file_t instigatorAppFile = MakeESFile("fooApp");
  es_process_t instigatorApp =
      MakeESProcess(&instigatorAppFile, MakeAuditToken(21, 43), MakeAuditToken(65, 87));
#if HAVE_MACOS_15
  audit_token_t tokInst = MakeAuditToken(654, 321);
  audit_token_t tokApp = MakeAuditToken(111, 222);
#endif

  es_btm_launch_item_t item = {
      .item_type = ES_BTM_ITEM_TYPE_APP,
      .legacy = true,
      .managed = false,
      .uid = (uid_t)-2,
      .item_url = MakeESStringToken("/absolute/path/item"),
      .app_url = MakeESStringToken("/absolute/path/app"),
  };

  es_event_btm_launch_item_remove_t launchItem = {
      .instigator = &instigatorProc,
      .app = &instigatorApp,
      .item = &item,
#if HAVE_MACOS_15
      .instigator_token = &tokInst,
      .app_token = &tokApp,
#endif
  };

  esMsg.event.btm_launch_item_remove = &launchItem;
  esMsg.version = 8;

  std::string got = BasicStringSerializeMessage(&esMsg);
  std::string want = "action=LAUNCH_ITEM_REMOVE|item_type=APP|legacy=true|managed=false"
                     "|item_user=nobody|item_uid=-2|item_path=/absolute/path/item"
                     "|app_path=/absolute/path/app|event_pid=21|event_ppid=65|event_process=fooInst"
                     "|event_processpath=fooInst|event_uid=-2|event_user=nobody|event_gid=-1"
                     "|event_group=nogroup|pid=12|ppid=56|process=foo|processpath=foo"
                     "|uid=-2|user=nobody|gid=-1|group=nogroup|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);

  launchItem.instigator = NULL;
  item.item_url = MakeESStringToken("relative/path");
  item.app_url = MakeESStringToken("file:///path/url");
  item.item_type = ES_BTM_ITEM_TYPE_LOGIN_ITEM;

  got = BasicStringSerializeMessage(&esMsg);
#if HAVE_MACOS_15
  want = "action=LAUNCH_ITEM_REMOVE|item_type=LOGIN_ITEM|legacy=true|managed=false"
         "|item_user=nobody|item_uid=-2|item_path=/path/url/relative/path|app_path=/path/url"
         "|event_pid=654|event_pidver=321|pid=12|ppid=56|process=foo|processpath=foo"
         "|uid=-2|user=nobody|gid=-1|group=nogroup|machineid=my_id\n";
#else
  want = "action=LAUNCH_ITEM_REMOVE|item_type=LOGIN_ITEM|legacy=true|managed=false"
         "|item_user=nobody|item_uid=-2|item_path=/path/url/relative/path|app_path=/path/url"
         "|pid=12|ppid=56|process=foo|processpath=foo"
         "|uid=-2|user=nobody|gid=-1|group=nogroup|machineid=my_id\n";
#endif

  XCTAssertCppStringEqual(got, want);

  item.app_url = MakeESStringToken(NULL);
  item.item_type = ES_BTM_ITEM_TYPE_AGENT;

  got = BasicStringSerializeMessage(&esMsg);
#if HAVE_MACOS_15
  want = "action=LAUNCH_ITEM_REMOVE|item_type=AGENT|legacy=true|managed=false"
         "|item_user=nobody|item_uid=-2|item_path=relative/path|event_pid=654"
         "|event_pidver=321|pid=12|ppid=56|process=foo|processpath=foo"
         "|uid=-2|user=nobody|gid=-1|group=nogroup|machineid=my_id\n";
#else
  want = "action=LAUNCH_ITEM_REMOVE|item_type=AGENT|legacy=true|managed=false"
         "|item_user=nobody|item_uid=-2|item_path=relative/path"
         "|pid=12|ppid=56|process=foo|processpath=foo"
         "|uid=-2|user=nobody|gid=-1|group=nogroup|machineid=my_id\n";
#endif

  XCTAssertCppStringEqual(got, want);
}

- (void)testSerializeMessageXProtectDetected {
  es_file_t procFile = MakeESFile("foo");
  es_process_t proc = MakeESProcess(&procFile, MakeAuditToken(12, 34), MakeAuditToken(56, 78));
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_XP_MALWARE_DETECTED, &proc);

  es_event_xp_malware_detected_t xp = {
      .signature_version = MakeESStringToken("v1.0"),
      .malware_identifier = MakeESStringToken("Eicar"),
      .incident_identifier = MakeESStringToken("C42221A2-7C14-4107-8B06-FB94D602187"),
      .detected_path = MakeESStringToken("/tmp/eicar"),
  };

  esMsg.event.xp_malware_detected = &xp;

  std::string got = BasicStringSerializeMessage(&esMsg);
  std::string want = "action=XPROTECT_DETECTED|signature_version=v1.0|malware_identifier=Eicar"
                     "|incident_identifier=C42221A2-7C14-4107-8B06-FB94D602187"
                     "|detected_path=/tmp/eicar|pid=12|ppid=56|process=foo|processpath=foo"
                     "|uid=-2|user=nobody|gid=-1|group=nogroup|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);
}

- (void)testSerializeMessageXProtectRemediated {
  es_file_t procFile = MakeESFile("foo");
  es_process_t proc = MakeESProcess(&procFile, MakeAuditToken(12, 34), MakeAuditToken(56, 78));
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_XP_MALWARE_REMEDIATED, &proc);

  audit_token_t tok = MakeAuditToken(99, 88);

  es_event_xp_malware_remediated_t xp = {
      .signature_version = MakeESStringToken("v1.0"),
      .malware_identifier = MakeESStringToken("Eicar"),
      .incident_identifier = MakeESStringToken("C42221A2-7C14-4107-8B06-FB94D602187"),
      .success = true,
      .result_description = MakeESStringToken("Successful"),
      .remediated_path = MakeESStringToken("/tmp/foo"),
      .remediated_process_audit_token = &tok,
  };

  esMsg.event.xp_malware_remediated = &xp;

  std::string got = BasicStringSerializeMessage(&esMsg);
  std::string want = "action=XPROTECT_REMEDIATED|signature_version=v1.0|malware_identifier=Eicar"
                     "|incident_identifier=C42221A2-7C14-4107-8B06-FB94D602187|success=true"
                     "|result_description=Successful|remediated_path=/tmp/foo"
                     "|remediated_pid=99|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);

  xp.remediated_process_audit_token = NULL;

  got = BasicStringSerializeMessage(&esMsg);
  want = "action=XPROTECT_REMEDIATED|signature_version=v1.0|malware_identifier=Eicar"
         "|incident_identifier=C42221A2-7C14-4107-8B06-FB94D602187|success=true"
         "|result_description=Successful|remediated_path=/tmp/foo|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);
}

#if HAVE_MACOS_15

- (void)testSerializeMessageGatekeeperOverride {
  es_file_t procFile = MakeESFile("foo");
  es_process_t proc = MakeESProcess(&procFile, MakeAuditToken(12, 34), MakeAuditToken(56, 78));
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_GATEKEEPER_USER_OVERRIDE, &proc);
  es_file_t gkFile = MakeESFile("MyAppFile");

  es_sha256_t fileHash;
  std::fill(std::begin(fileHash), std::end(fileHash), 'A');

  es_signed_file_info_t signingInfo = {
      .signing_id = MakeESStringToken("com.my.sid"),
      .team_id = MakeESStringToken("mytid"),
  };
  std::fill(std::begin(signingInfo.cdhash), std::end(signingInfo.cdhash), 'B');

  es_event_gatekeeper_user_override_t gatekeeper = {
      .file_type = ES_GATEKEEPER_USER_OVERRIDE_FILE_TYPE_FILE,
      .file = {.file = &gkFile},
      .sha256 = &fileHash,
      .signing_info = &signingInfo,
  };

  esMsg.event.gatekeeper_user_override = &gatekeeper;

  std::string got = BasicStringSerializeMessage(&esMsg);
  std::string want =
      "action=GATEKEEPER_OVERRIDE|target=MyAppFile"
      "|hash=4141414141414141414141414141414141414141414141414141414141414141|team_id=mytid"
      "|signing_id=com.my.sid|cdhash=4242424242424242424242424242424242424242"
      "|pid=12|ppid=56|process=foo|processpath=foo"
      "|uid=-2|user=nobody|gid=-1|group=nogroup|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);

  gatekeeper.file_type = ES_GATEKEEPER_USER_OVERRIDE_FILE_TYPE_PATH;
  gatekeeper.file.file_path = MakeESStringToken("MyAppPath");

  got = BasicStringSerializeMessage(&esMsg);
  want = "action=GATEKEEPER_OVERRIDE|target=MyAppPath"
         "|hash=4141414141414141414141414141414141414141414141414141414141414141|team_id=mytid"
         "|signing_id=com.my.sid|cdhash=4242424242424242424242424242424242424242"
         "|pid=12|ppid=56|process=foo|processpath=foo"
         "|uid=-2|user=nobody|gid=-1|group=nogroup|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);
}

#endif  // HAVE_MACOS_15

#if HAVE_MACOS_15_4

- (void)testGetTCCIdentityTypeString {
  std::map<es_tcc_identity_type_t, std::string> identityTypeToString{
      {ES_TCC_IDENTITY_TYPE_BUNDLE_ID, "BUNDLE_ID"},
      {ES_TCC_IDENTITY_TYPE_EXECUTABLE_PATH, "EXECUTABLE_PATH"},
      {ES_TCC_IDENTITY_TYPE_POLICY_ID, "POLICY_ID"},
      {ES_TCC_IDENTITY_TYPE_FILE_PROVIDER_DOMAIN_ID, "FILE_PROVIDER_DOMAIN_ID"},
      {(es_tcc_identity_type_t)1234, "UNKNOWN"},
  };

  for (const auto &kv : identityTypeToString) {
    XCTAssertCppStringEqual(santa::GetTCCIdentityTypeString(kv.first), kv.second);
  }
}
- (void)testGetTCCEventTypeString {
  std::map<es_tcc_event_type_t, std::string> eventTypeToString{
      {ES_TCC_EVENT_TYPE_CREATE, "CREATE"},
      {ES_TCC_EVENT_TYPE_MODIFY, "MODIFY"},
      {ES_TCC_EVENT_TYPE_DELETE, "DELETE"},
      {(es_tcc_event_type_t)1234, "UNKNOWN"},
  };

  for (const auto &kv : eventTypeToString) {
    XCTAssertCppStringEqual(santa::GetTCCEventTypeString(kv.first), kv.second);
  }
}
- (void)testGetTCCAuthorizationRightString {
  std::map<es_tcc_authorization_right_t, std::string> authRightToString{
      {ES_TCC_AUTHORIZATION_RIGHT_DENIED, "DENIED"},
      {ES_TCC_AUTHORIZATION_RIGHT_UNKNOWN, "UNKNOWN"},
      {ES_TCC_AUTHORIZATION_RIGHT_ALLOWED, "ALLOWED"},
      {ES_TCC_AUTHORIZATION_RIGHT_LIMITED, "LIMITED"},
      {ES_TCC_AUTHORIZATION_RIGHT_ADD_MODIFY_ADDED, "ADD_MODIFY_ADDED"},
      {ES_TCC_AUTHORIZATION_RIGHT_SESSION_PID, "SESSION_PID"},
      {ES_TCC_AUTHORIZATION_RIGHT_LEARN_MORE, "LEARN_MORE"},
      {(es_tcc_authorization_right_t)1234, "UNKNOWN"},
  };

  for (const auto &kv : authRightToString) {
    XCTAssertCppStringEqual(santa::GetTCCAuthorizationRightString(kv.first), kv.second);
  }
}
- (void)testGetTCCAuthorizationReasonString {
  std::map<es_tcc_authorization_reason_t, std::string> authReasonToString{
      {ES_TCC_AUTHORIZATION_REASON_NONE, "NONE"},
      {ES_TCC_AUTHORIZATION_REASON_ERROR, "ERROR"},
      {ES_TCC_AUTHORIZATION_REASON_USER_CONSENT, "USER_CONSENT"},
      {ES_TCC_AUTHORIZATION_REASON_USER_SET, "USER_SET"},
      {ES_TCC_AUTHORIZATION_REASON_SYSTEM_SET, "SYSTEM_SET"},
      {ES_TCC_AUTHORIZATION_REASON_SERVICE_POLICY, "SERVICE_POLICY"},
      {ES_TCC_AUTHORIZATION_REASON_MDM_POLICY, "MDM_POLICY"},
      {ES_TCC_AUTHORIZATION_REASON_SERVICE_OVERRIDE_POLICY, "SERVICE_OVERRIDE_POLICY"},
      {ES_TCC_AUTHORIZATION_REASON_MISSING_USAGE_STRING, "MISSING_USAGE_STRING"},
      {ES_TCC_AUTHORIZATION_REASON_PROMPT_TIMEOUT, "PROMPT_TIMEOUT"},
      {ES_TCC_AUTHORIZATION_REASON_PREFLIGHT_UNKNOWN, "PREFLIGHT_UNKNOWN"},
      {ES_TCC_AUTHORIZATION_REASON_ENTITLED, "ENTITLED"},
      {ES_TCC_AUTHORIZATION_REASON_APP_TYPE_POLICY, "APP_TYPE_POLICY"},
      {ES_TCC_AUTHORIZATION_REASON_PROMPT_CANCEL, "PROMPT_CANCEL"},
      {(es_tcc_authorization_reason_t)1234, "UNKNOWN"},
  };

  for (const auto &kv : authReasonToString) {
    XCTAssertCppStringEqual(santa::GetTCCAuthorizationReasonString(kv.first), kv.second);
  }
}

- (void)testSerializeMessageTCCModification {
  es_file_t procFile = MakeESFile("foo");
  es_process_t proc = MakeESProcess(&procFile, MakeAuditToken(12, 34), MakeAuditToken(56, 78));
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_TCC_MODIFY, &proc);

  es_file_t instigatorProcFile = MakeESFile("fooInst");
  es_process_t instigatorProc =
      MakeESProcess(&instigatorProcFile, MakeAuditToken(21, 43), MakeAuditToken(65, 87));

  es_file_t responsibleFile = MakeESFile("fooApp");
  es_process_t responsibleProc =
      MakeESProcess(&responsibleFile, MakeAuditToken(21, 43), MakeAuditToken(65, 87));

  audit_token_t tokInstigator = MakeAuditToken(654, 321);
  audit_token_t tokResponsible = MakeAuditToken(111, 222);

  es_event_tcc_modify_t tcc = {
      .service = MakeESStringToken("SystemPolicyDocumentsFolder"),
      .identity = MakeESStringToken("security.northpole.santa"),
      .identity_type = ES_TCC_IDENTITY_TYPE_BUNDLE_ID,
      .update_type = ES_TCC_EVENT_TYPE_MODIFY,
      .instigator_token = tokInstigator,
      .instigator = &instigatorProc,
      .responsible_token = &tokResponsible,
      .responsible = &responsibleProc,
      .right = ES_TCC_AUTHORIZATION_RIGHT_SESSION_PID,
      .reason = ES_TCC_AUTHORIZATION_REASON_SERVICE_POLICY,
  };

  esMsg.event.tcc_modify = &tcc;

  std::string got = BasicStringSerializeMessage(&esMsg);
  std::string want =
      "action=TCC_MODIFICATION|event_type=MODIFY|service=SystemPolicyDocumentsFolder"
      "|identity=security.northpole.santa|identity_type=BUNDLE_ID|auth_right=SESSION_PID"
      "|auth_reason=SERVICE_POLICY|event_pid=21|event_ppid=65|event_process=fooInst"
      "|event_processpath=fooInst|event_uid=-2|event_user=nobody"
      "|event_gid=-1|event_group=nogroup|pid=12|ppid=56|process=foo|processpath=foo"
      "|uid=-2|user=nobody|gid=-1|group=nogroup|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);

  tcc.instigator = NULL;
  tcc.update_type = ES_TCC_EVENT_TYPE_CREATE;
  tcc.identity_type = ES_TCC_IDENTITY_TYPE_POLICY_ID;
  tcc.right = ES_TCC_AUTHORIZATION_RIGHT_ALLOWED;
  tcc.reason = ES_TCC_AUTHORIZATION_REASON_PROMPT_TIMEOUT;

  got = BasicStringSerializeMessage(&esMsg);
  want = "action=TCC_MODIFICATION|event_type=CREATE|service=SystemPolicyDocumentsFolder"
         "|identity=security.northpole.santa|identity_type=POLICY_ID|auth_right=ALLOWED"
         "|auth_reason=PROMPT_TIMEOUT|event_pid=654|event_pidver=321|pid=12|ppid=56"
         "|process=foo|processpath=foo|uid=-2|user=nobody|gid=-1|group=nogroup|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);
}

#endif  // HAVE_MACOS_15_4

- (void)testGetAccessTypeString {
  std::map<es_event_type_t, std::string> accessTypeToString = {
      {ES_EVENT_TYPE_AUTH_OPEN, "OPEN"},         {ES_EVENT_TYPE_AUTH_LINK, "LINK"},
      {ES_EVENT_TYPE_AUTH_RENAME, "RENAME"},     {ES_EVENT_TYPE_AUTH_UNLINK, "UNLINK"},
      {ES_EVENT_TYPE_AUTH_CLONE, "CLONE"},       {ES_EVENT_TYPE_AUTH_EXCHANGEDATA, "EXCHANGEDATA"},
      {ES_EVENT_TYPE_AUTH_CREATE, "CREATE"},     {ES_EVENT_TYPE_AUTH_TRUNCATE, "TRUNCATE"},
      {ES_EVENT_TYPE_AUTH_COPYFILE, "COPYFILE"}, {(es_event_type_t)1234, "UNKNOWN_TYPE_1234"},
  };

  for (const auto &kv : accessTypeToString) {
    XCTAssertCppStringEqual(santa::GetAccessTypeString(kv.first), kv.second);
  }
}

- (void)testGetFileAccessPolicyDecisionString {
  std::map<FileAccessPolicyDecision, std::string> policyDecisionToString = {
      {FileAccessPolicyDecision::kNoPolicy, "NO_POLICY"},
      {FileAccessPolicyDecision::kDenied, "DENIED"},
      {FileAccessPolicyDecision::kDeniedInvalidSignature, "DENIED_INVALID_SIGNATURE"},
      {FileAccessPolicyDecision::kAllowed, "ALLOWED"},
      {FileAccessPolicyDecision::kAllowedReadAccess, "ALLOWED_READ_ACCESS"},
      {FileAccessPolicyDecision::kAllowedAuditOnly, "AUDIT_ONLY"},
      {(FileAccessPolicyDecision)1234, "UNKNOWN_DECISION_1234"},
  };

  for (const auto &kv : policyDecisionToString) {
    XCTAssertCppStringEqual(santa::GetFileAccessPolicyDecisionString(kv.first), kv.second);
  }
}

- (void)testSerializeFileAccess {
  es_file_t procFile = MakeESFile("foo");
  es_process_t proc = MakeESProcess(&procFile, MakeAuditToken(12, 34), MakeAuditToken(56, 78));
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_AUTH_OPEN, &proc);

  auto mockESApi = std::make_shared<MockEndpointSecurityAPI>();
  mockESApi->SetExpectationsRetainReleaseMessage();

  std::vector<uint8_t> ret =
      BasicString::Create(nullptr, nil, false)
          ->SerializeFileAccess("v1.0", "pol_name", Message(mockESApi, &esMsg),
                                Enricher().Enrich(*esMsg.process), "file_target",
                                FileAccessPolicyDecision::kAllowedAuditOnly, "abc123");
  std::string got(ret.begin(), ret.end());
  std::string want =
      "action=FILE_ACCESS|policy_version=v1.0|policy_name=pol_name|path=file_target"
      "|access_type=OPEN|decision=AUDIT_ONLY|operation_id=abc123|pid=12|ppid=56"
      "|process=foo|processpath=foo|uid=-2|user=nobody|gid=-1|group=nogroup|machineid=my_id\n";
  XCTAssertCppStringEqual(got, want);
}

- (void)testSerializeAllowlist {
  es_file_t file = MakeESFile("foo");
  es_process_t proc = MakeESProcess(&file, MakeAuditToken(12, 34), MakeAuditToken(56, 78));
  es_message_t esMsg = MakeESMessage(ES_EVENT_TYPE_NOTIFY_CLOSE, &proc);
  esMsg.event.close.target = &file;

  auto mockESApi = std::make_shared<MockEndpointSecurityAPI>();
  mockESApi->SetExpectationsRetainReleaseMessage();

  std::vector<uint8_t> ret = BasicString::Create(mockESApi, nil, false)
                                 ->SerializeAllowlist(Message(mockESApi, &esMsg), "test_hash");

  XCTAssertTrue(testing::Mock::VerifyAndClearExpectations(mockESApi.get()),
                "Expected calls were not properly mocked");

  std::string got(ret.begin(), ret.end());
  std::string want = "action=ALLOWLIST|pid=12|pidversion=34|path=foo"
                     "|sha256=test_hash|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);
}

- (void)testSerializeBundleHashingEvent {
  SNTStoredExecutionEvent *se = [[SNTStoredExecutionEvent alloc] init];

  se.fileSHA256 = @"file_hash";
  se.fileBundleHash = @"file_bundle_hash";
  se.fileBundleName = @"file_bundle_Name";
  se.fileBundleID = nil;
  se.fileBundlePath = @"file_bundle_path";
  se.filePath = @"file_path";

  std::vector<uint8_t> ret =
      BasicString::Create(nullptr, nil, false)->SerializeBundleHashingEvent(se);
  std::string got(ret.begin(), ret.end());

  std::string want = "action=BUNDLE|sha256=file_hash"
                     "|bundlehash=file_bundle_hash|bundlename=file_bundle_Name|bundleid="
                     "|bundlepath=file_bundle_path|path=file_path|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);
}

- (void)testSerializeDiskAppeared {
  NSDictionary *props = @{
    @"DADevicePath" : @"",
    @"DADeviceVendor" : @"vendor",
    @"DADeviceModel" : @"model",
    @"DAAppearanceTime" : @(1252487349),  // 2009-09-09 09:09:09
    @"DAVolumePath" : [NSURL URLWithString:@"/"],
    @"DAMediaBSDName" : @"bsd",
    @"DAVolumeKind" : @"apfs",
    @"DADeviceProtocol" : @"usb",
  };

  // Arbitrarily overwriting mock to test not adding machine id in this event
  self.mockConfigurator = OCMClassMock([SNTConfigurator class]);
  OCMStub([self.mockConfigurator configurator]).andReturn(self.mockConfigurator);
  OCMStub([self.mockConfigurator enableMachineIDDecoration]).andReturn(NO);

  std::vector<uint8_t> ret = BasicString::Create(nullptr, nil, false)->SerializeDiskAppeared(props);
  std::string got(ret.begin(), ret.end());

  std::string want = "action=DISKAPPEAR|mount=/|volume=|bsdname=bsd|fs=apfs"
                     "|model=vendor model|serial=|bus=usb|dmgpath="
                     "|appearance=2040-09-09T09:09:09.000Z|mountfrom=/";

  XCTAssertCppStringBeginsWith(got, want);
}

- (void)testSerializeDiskDisappeared {
  NSDictionary *props = @{
    @"DAVolumePath" : [NSURL URLWithString:@"path"],
    @"DAMediaBSDName" : @"bsd",
  };

  std::vector<uint8_t> ret =
      BasicString::Create(nullptr, nil, false)->SerializeDiskDisappeared(props);
  std::string got(ret.begin(), ret.end());

  std::string want = "action=DISKDISAPPEAR|mount=path|volume=|bsdname=bsd|machineid=my_id\n";

  XCTAssertCppStringEqual(got, want);
}

- (void)testGetDecisionString {
  std::map<SNTEventState, std::string> stateToDecision = {
      {SNTEventStateUnknown, "UNKNOWN"},
      {SNTEventStateBundleBinary, "UNKNOWN"},
      {SNTEventStateBlockUnknown, "DENY"},
      {SNTEventStateBlockBinary, "DENY"},
      {SNTEventStateBlockCertificate, "DENY"},
      {SNTEventStateBlockScope, "DENY"},
      {SNTEventStateBlockTeamID, "DENY"},
      {SNTEventStateBlockLongPath, "DENY"},
      {SNTEventStateAllowUnknown, "ALLOW"},
      {SNTEventStateAllowBinary, "ALLOW"},
      {SNTEventStateAllowCertificate, "ALLOW"},
      {SNTEventStateAllowScope, "ALLOW"},
      {SNTEventStateAllowCompilerBinary, "ALLOW_COMPILER"},
      {SNTEventStateAllowCompilerCDHash, "ALLOW_COMPILER"},
      {SNTEventStateAllowCompilerSigningID, "ALLOW_COMPILER"},
      {SNTEventStateAllowTransitive, "ALLOW"},
      {SNTEventStateAllowPendingTransitive, "ALLOW"},
      {SNTEventStateAllowTeamID, "ALLOW"},
  };

  for (const auto &kv : stateToDecision) {
    XCTAssertCppStringEqual(santa::GetDecisionString(kv.first), kv.second);
  }
}

- (void)testGetReasonString {
  std::string want;
  for (uint64_t i = 0; i <= 64; i++) {
    SNTEventState state = static_cast<SNTEventState>(i == 0 ? 0 : 1 << (i - 1));
    std::string want = "UNKNOWN";
    switch (state) {
      case SNTEventStateUnknown: want = "UNKNOWN"; break;
      case SNTEventStateBundleBinary: want = "UNKNOWN"; break;
      case SNTEventStateBlockUnknown: want = "UNKNOWN"; break;
      case SNTEventStateBlockBinary: want = "BINARY"; break;
      case SNTEventStateBlockCertificate: want = "CERT"; break;
      case SNTEventStateBlockScope: want = "SCOPE"; break;
      case SNTEventStateBlockTeamID: want = "TEAMID"; break;
      case SNTEventStateBlockLongPath: want = "LONG_PATH"; break;
      case SNTEventStateBlockSigningID: want = "SIGNINGID"; break;
      case SNTEventStateBlockCDHash: want = "CDHASH"; break;
      case SNTEventStateAllowUnknown: want = "UNKNOWN"; break;
      case SNTEventStateAllowBinary: want = "BINARY"; break;
      case SNTEventStateAllowCertificate: want = "CERT"; break;
      case SNTEventStateAllowScope: want = "SCOPE"; break;
      case SNTEventStateAllowCompilerBinary: want = "BINARY"; break;
      case SNTEventStateAllowTransitive: want = "TRANSITIVE"; break;
      case SNTEventStateAllowPendingTransitive: want = "PENDING_TRANSITIVE"; break;
      case SNTEventStateAllowTeamID: want = "TEAMID"; break;
      case SNTEventStateAllowSigningID: want = "SIGNINGID"; break;
      case SNTEventStateAllowCDHash: want = "CDHASH"; break;
      case SNTEventStateAllowLocalBinary: want = "BINARY"; break;
      case SNTEventStateAllowLocalSigningID: want = "SIGNINGID"; break;
      case SNTEventStateAllowCompilerSigningID: want = "SIGNINGID"; break;
      case SNTEventStateAllowCompilerCDHash: want = "CDHASH"; break;
      case SNTEventStateBlock: want = "UNKNOWN"; break;
      case SNTEventStateAllow: want = "UNKNOWN"; break;
    }

    XCTAssertCppStringEqual(santa::GetReasonString(state), want);
  }
}

- (void)testGetModeString {
  std::map<SNTClientMode, std::string> modeToString = {
      {SNTClientModeMonitor, "M"},
      {SNTClientModeLockdown, "L"},
      {SNTClientModeStandalone, "S"},
      {(SNTClientMode)123, "U"},
  };

  for (const auto &kv : modeToString) {
    XCTAssertCppStringEqual(santa::GetModeString(kv.first), kv.second);
  }
}

@end
