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

#include "Source/santad/Logs/EndpointSecurity/Serializers/Empty.h"

namespace santa {

std::shared_ptr<Empty> Empty::Create() {
  return std::make_shared<Empty>();
}

Empty::Empty() : Serializer(nil) {}

std::vector<uint8_t> Empty::SerializeMessage(const EnrichedClose &msg) {
  return {};
}

std::vector<uint8_t> Empty::SerializeMessage(const EnrichedExchange &msg) {
  return {};
}

std::vector<uint8_t> Empty::SerializeMessage(const EnrichedExec &msg, SNTCachedDecision *cd) {
  return {};
}

std::vector<uint8_t> Empty::SerializeMessage(const EnrichedExit &msg) {
  return {};
}

std::vector<uint8_t> Empty::SerializeMessage(const EnrichedFork &msg) {
  return {};
}

std::vector<uint8_t> Empty::SerializeMessage(const EnrichedLink &msg) {
  return {};
}

std::vector<uint8_t> Empty::SerializeMessage(const EnrichedRename &msg) {
  return {};
}

std::vector<uint8_t> Empty::SerializeMessage(const EnrichedUnlink &msg) {
  return {};
}

std::vector<uint8_t> Empty::SerializeMessage(const EnrichedCSInvalidated &msg) {
  return {};
}

std::vector<uint8_t> Empty::SerializeMessage(const EnrichedClone &msg) {
  return {};
}

std::vector<uint8_t> Empty::SerializeMessage(const EnrichedCopyfile &msg) {
  return {};
}

std::vector<uint8_t> Empty::SerializeMessage(const EnrichedLoginWindowSessionLogin &msg) {
  return {};
}

std::vector<uint8_t> Empty::SerializeMessage(const EnrichedLoginWindowSessionLogout &msg) {
  return {};
}

std::vector<uint8_t> Empty::SerializeMessage(const EnrichedLoginWindowSessionLock &) {
  return {};
}

std::vector<uint8_t> Empty::SerializeMessage(const EnrichedLoginWindowSessionUnlock &) {
  return {};
}

std::vector<uint8_t> Empty::SerializeMessage(const EnrichedScreenSharingAttach &) {
  return {};
}

std::vector<uint8_t> Empty::SerializeMessage(const EnrichedScreenSharingDetach &) {
  return {};
}

std::vector<uint8_t> Empty::SerializeMessage(const EnrichedOpenSSHLogin &) {
  return {};
}

std::vector<uint8_t> Empty::SerializeMessage(const EnrichedOpenSSHLogout &) {
  return {};
}

std::vector<uint8_t> Empty::SerializeMessage(const EnrichedLoginLogin &) {
  return {};
}

std::vector<uint8_t> Empty::SerializeMessage(const EnrichedLoginLogout &) {
  return {};
}

std::vector<uint8_t> Empty::SerializeMessage(const EnrichedAuthenticationOD &) {
  return {};
}

std::vector<uint8_t> Empty::SerializeMessage(const EnrichedAuthenticationTouchID &) {
  return {};
}

std::vector<uint8_t> Empty::SerializeMessage(const EnrichedAuthenticationToken &) {
  return {};
}

std::vector<uint8_t> Empty::SerializeMessage(const EnrichedAuthenticationAutoUnlock &) {
  return {};
}

std::vector<uint8_t> Empty::SerializeMessage(const EnrichedLaunchItem &) {
  return {};
}

std::vector<uint8_t> Empty::SerializeMessage(const EnrichedXProtectDetected &) {
  return {};
}

std::vector<uint8_t> Empty::SerializeMessage(const EnrichedXProtectRemediated &) {
  return {};
}

#if HAVE_MACOS_15

std::vector<uint8_t> Empty::SerializeMessage(const EnrichedGatekeeperOverride &) {
  return {};
}

#endif  // HAVE_MACOS_15

#if HAVE_MACOS_15_4

std::vector<uint8_t> Empty::SerializeMessage(const EnrichedTCCModification &) {
  return {};
}

#endif  // HAVE_MACOS_15_4

std::vector<uint8_t> Empty::SerializeFileAccess(const std::string &policy_version,
                                                const std::string &policy_name, const Message &msg,
                                                const EnrichedProcess &enriched_process,
                                                const std::string &target,
                                                FileAccessPolicyDecision decision,
                                                std::string_view operation_id) {
  return {};
}

std::vector<uint8_t> Empty::SerializeAllowlist(const Message &msg, const std::string_view hash) {
  return {};
}

std::vector<uint8_t> Empty::SerializeBundleHashingEvent(SNTStoredExecutionEvent *event) {
  return {};
}

std::vector<uint8_t> Empty::SerializeDiskAppeared(NSDictionary *props) {
  return {};
}

std::vector<uint8_t> Empty::SerializeDiskDisappeared(NSDictionary *props) {
  return {};
}

}  // namespace santa
