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

#include "Source/santad/Logs/EndpointSecurity/Serializers/Parquet.h"

namespace santa {

std::shared_ptr<Parquet> Parquet::Create(std::shared_ptr<EndpointSecurityAPI> esapi,
                                                  SNTDecisionCache *decision_cache,
                                                  std::string spool_dir,
                                                  bool prefix_time_name) {
  return std::make_shared<Parquet>(esapi, decision_cache, std::move(spool_dir), prefix_time_name);
}

Parquet::Parquet(std::shared_ptr<EndpointSecurityAPI> esapi,
                         SNTDecisionCache *decision_cache, std::string spool_dir, bool prefix_time_name)
    : Serializer(std::move(decision_cache)), esapi_(esapi), prefix_time_name_(prefix_time_name), builder_(santa::new_exec_builder(spool_dir)) {}

std::vector<uint8_t> Parquet::SerializeMessage(const EnrichedClose &msg) {
  return {};
}

std::vector<uint8_t> Parquet::SerializeMessage(const EnrichedExchange &msg) {
  return {};
}

std::vector<uint8_t> Parquet::SerializeMessage(const EnrichedExec &msg, SNTCachedDecision *cd) {
  // builder_->set_cwd("asdf");
  LOGE(@"log exec: %s", msg->event.exec.target->executable->path.data);
  builder_->set_executable_path(msg->event.exec.target->executable->path.data,
    msg->event.exec.target->executable->path_truncated);
  builder_->autocomplete();
  return {};
}

std::vector<uint8_t> Parquet::SerializeMessage(const EnrichedExit &msg) {
  return {};
}

std::vector<uint8_t> Parquet::SerializeMessage(const EnrichedFork &msg) {
  return {};
}

std::vector<uint8_t> Parquet::SerializeMessage(const EnrichedLink &msg) {
  return {};
}

std::vector<uint8_t> Parquet::SerializeMessage(const EnrichedRename &msg) {
  return {};
}

std::vector<uint8_t> Parquet::SerializeMessage(const EnrichedUnlink &msg) {
  return {};
}

std::vector<uint8_t> Parquet::SerializeMessage(const EnrichedCSInvalidated &msg) {
  return {};
}

std::vector<uint8_t> Parquet::SerializeMessage(const EnrichedClone &msg) {
  return {};
}

std::vector<uint8_t> Parquet::SerializeMessage(const EnrichedCopyfile &msg) {
  return {};
}

std::vector<uint8_t> Parquet::SerializeMessage(const EnrichedLoginWindowSessionLogin &msg) {
  return {};
}

std::vector<uint8_t> Parquet::SerializeMessage(const EnrichedLoginWindowSessionLogout &msg) {
  return {};
}

std::vector<uint8_t> Parquet::SerializeMessage(const EnrichedLoginWindowSessionLock &) {
  return {};
}

std::vector<uint8_t> Parquet::SerializeMessage(const EnrichedLoginWindowSessionUnlock &) {
  return {};
}

std::vector<uint8_t> Parquet::SerializeMessage(const EnrichedScreenSharingAttach &) {
  return {};
}

std::vector<uint8_t> Parquet::SerializeMessage(const EnrichedScreenSharingDetach &) {
  return {};
}

std::vector<uint8_t> Parquet::SerializeMessage(const EnrichedOpenSSHLogin &) {
  return {};
}

std::vector<uint8_t> Parquet::SerializeMessage(const EnrichedOpenSSHLogout &) {
  return {};
}

std::vector<uint8_t> Parquet::SerializeMessage(const EnrichedLoginLogin &) {
  return {};
}

std::vector<uint8_t> Parquet::SerializeMessage(const EnrichedLoginLogout &) {
  return {};
}

std::vector<uint8_t> Parquet::SerializeMessage(const EnrichedAuthenticationOD &) {
  return {};
}

std::vector<uint8_t> Parquet::SerializeMessage(const EnrichedAuthenticationTouchID &) {
  return {};
}

std::vector<uint8_t> Parquet::SerializeMessage(const EnrichedAuthenticationToken &) {
  return {};
}

std::vector<uint8_t> Parquet::SerializeMessage(const EnrichedAuthenticationAutoUnlock &) {
  return {};
}

std::vector<uint8_t> Parquet::SerializeMessage(const EnrichedLaunchItem &) {
  return {};
}

std::vector<uint8_t> Parquet::SerializeMessage(const EnrichedXProtectDetected &) {
  return {};
}

std::vector<uint8_t> Parquet::SerializeMessage(const EnrichedXProtectRemediated &) {
  return {};
}

#if HAVE_MACOS_15

std::vector<uint8_t> Parquet::SerializeMessage(const EnrichedGatekeeperOverride &) {
  return {};
}

#endif  // HAVE_MACOS_15

#if HAVE_MACOS_15_4

std::vector<uint8_t> Parquet::SerializeMessage(const EnrichedTCCModification &) {
  return {};
}

#endif  // HAVE_MACOS_15_4

std::vector<uint8_t> Parquet::SerializeFileAccess(const std::string &policy_version,
                                                const std::string &policy_name, const Message &msg,
                                                const EnrichedProcess &enriched_process,
                                                const std::string &target,
                                                FileAccessPolicyDecision decision,
                                                std::string_view operation_id) {
  return {};
}

std::vector<uint8_t> Parquet::SerializeAllowlist(const Message &msg, const std::string_view hash) {
  return {};
}

std::vector<uint8_t> Parquet::SerializeBundleHashingEvent(SNTStoredExecutionEvent *event) {
  return {};
}

std::vector<uint8_t> Parquet::SerializeDiskAppeared(NSDictionary *props) {
  return {};
}

std::vector<uint8_t> Parquet::SerializeDiskDisappeared(NSDictionary *props) {
  return {};
}

}  // namespace santa
