/// Copyright 2024 Google LLC
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

#include "Source/santad/EventProviders/SNTEndpointSecurityClient.h"

#include "Source/santad/EventProviders/EndpointSecurity/EndpointSecurityAPI.h"
#include "Source/santad/Metrics.h"
#include "Source/santad/ProcessTree/process_tree.h"

@interface SNTEndpointSecurityTreeAwareClient : SNTEndpointSecurityClient
@property std::shared_ptr<santa::santad::process_tree::ProcessTree> processTree;

- (instancetype)initWithESAPI:(std::shared_ptr<santa::EndpointSecurityAPI>)esApi
                      metrics:(std::shared_ptr<santa::Metrics>)metrics
                    processor:(santa::Processor)processor
                  processTree:
                      (std::shared_ptr<santa::santad::process_tree::ProcessTree>)processTree;
@end
