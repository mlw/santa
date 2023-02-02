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

#ifndef SANTA__SANTAD__DECISIONCACHE_H
#define SANTA__SANTAD__DECISIONCACHE_H

#import <Foundation/Foundation.h>
#include <sys/stat.h>

#include <memory>

#import "Source/common/SNTCachedDecision.h"
#include "Source/common/SantaCache.h"
#include "Source/common/SantaVnode.h"

namespace santa::santad {

class DecisionCache {
 public:
  // Factory
  static std::shared_ptr<DecisionCache> Create();

  DecisionCache();

  void CacheDecision(SNTCachedDecision *cd);
  SNTCachedDecision *CachedDecisionForFile(const struct stat &stat_info);
  void ForgetCachedDecisionForFile(const struct stat &stat_info);
  SNTCachedDecision *ResetTimestampForCachedDecision(const struct stat &stat_info);

 private:
  SantaCache<SantaVnode, SNTCachedDecision *> decision_cache_;
  NSCache *timestamp_reset_map_;
};
}  // namespace santa::santad
#endif
