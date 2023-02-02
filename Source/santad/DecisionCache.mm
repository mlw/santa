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

#include "Source/santad/DecisionCache.h"

#import "Source/common/SNTCommonEnums.h"
#import "Source/common/SNTRule.h"
#include "Source/common/SantaVnode.h"
#include "Source/common/SantaVnodeHash.h"
#import "Source/santad/DataLayer/SNTRuleTable.h"
#import "Source/santad/SNTDatabaseController.h"

namespace santa::santad {

std::shared_ptr<DecisionCache> DecisionCache::Create() {
  return std::make_shared<DecisionCache>();
}

DecisionCache::DecisionCache() {
  timestamp_reset_map_ = [[NSCache alloc] init];
  timestamp_reset_map_.countLimit = 100;
}

void DecisionCache::CacheDecision(SNTCachedDecision *cd) {
  decision_cache_.set(cd.vnodeId, cd);
}

SNTCachedDecision *DecisionCache::CachedDecisionForFile(const struct stat &stat_info) {
  return decision_cache_.get(SantaVnode::VnodeForFile(stat_info));
}

void DecisionCache::ForgetCachedDecisionForFile(const struct stat &stat_info) {
  decision_cache_.remove(SantaVnode::VnodeForFile(stat_info));
}

// Whenever a cached decision resulting from a transitive allowlist rule is used to allow the
// execution of a binary, we update the timestamp on the transitive rule in the rules database.
// To prevent writing to the database too often, we space out consecutive writes by 3600 seconds.
SNTCachedDecision *DecisionCache::ResetTimestampForCachedDecision(const struct stat &stat_info) {
  SNTCachedDecision *cd = CachedDecisionForFile(stat_info);
  if (!cd || cd.decision != SNTEventStateAllowTransitive || !cd.sha256) {
    return cd;
  }

  NSDate *lastUpdate = [timestamp_reset_map_ objectForKey:cd.sha256];
  if (!lastUpdate || -[lastUpdate timeIntervalSinceNow] > 3600) {
    SNTRule *rule = [[SNTRule alloc] initWithIdentifier:cd.sha256
                                                  state:SNTRuleStateAllowTransitive
                                                   type:SNTRuleTypeBinary
                                              customMsg:nil];
    [[SNTDatabaseController ruleTable] resetTimestampForRule:rule];
    [timestamp_reset_map_ setObject:[NSDate date] forKey:cd.sha256];
  }

  return cd;
}

}  // namespace santa::santad
