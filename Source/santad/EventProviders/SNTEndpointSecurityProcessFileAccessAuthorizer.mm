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

#import "Source/santad/EventProviders/SNTEndpointSecurityProcessFileAccessAuthorizer.h"
#include <EndpointSecurity/ESTypes.h>
#include "Source/santad/EventProviders/FAAPolicyProcessor.h"

#include <bsm/libbsm.h>

#import "Source/common/SNTLogging.h"
#include "Source/santad/DataLayer/WatchItemPolicy.h"
#include "Source/santad/EventProviders/SNTEndpointSecurityEventHandler.h"

using santa::FAAPolicyProcessor;
using santa::IterateProcessPoliciesBlock;
using santa::Message;
using santa::ProcessWatchItemPolicy;

using PidPidverPair = std::pair<pid_t, int>;
using ProcessRuleCache = SantaCache<PidPidverPair, std::shared_ptr<ProcessWatchItemPolicy>>;

static inline PidPidverPair PidPidver(const es_process_t *proc) {
  return {audit_token_to_pid(proc->audit_token), audit_token_to_pidversion(proc->audit_token)};
}

@interface SNTEndpointSecurityProcessFileAccessAuthorizer ()
@property bool isSubscribed;
@property(copy) IterateProcessPoliciesBlock iterateProcessPoliciesBlock;
@property std::shared_ptr<FAAPolicyProcessor> faaPolicyProcessor;
@property SNTConfigurator *configurator;
@end

@implementation SNTEndpointSecurityProcessFileAccessAuthorizer {
  std::unique_ptr<ProcessRuleCache> _procRuleCache;
}

- (instancetype)initWithESAPI:(std::shared_ptr<santa::EndpointSecurityAPI>)esApi
                        metrics:(std::shared_ptr<santa::Metrics>)metrics
             faaPolicyProcessor:(std::shared_ptr<FAAPolicyProcessor>)faaPolicyProcessor
    iterateProcessPoliciesBlock:(IterateProcessPoliciesBlock)iterateProcessPoliciesBlock {
  self = [super initWithESAPI:std::move(esApi)
                      metrics:std::move(metrics)
                    processor:santa::Processor::kProcessFileAccessAuthorizer];
  if (self) {
    _faaPolicyProcessor = faaPolicyProcessor;
    _iterateProcessPoliciesBlock = iterateProcessPoliciesBlock;

    _procRuleCache = std::make_unique<ProcessRuleCache>(2000);
    _configurator = [SNTConfigurator configurator];

    [self establishClientOrDie];
    [self enableProcessWatching];
  }
  return self;
}

- (NSString *)description {
  return @"ProcessFileAccessAuthorizer";
}

- (void)processMessage:(Message)msg
                policy:(std::shared_ptr<ProcessWatchItemPolicy>)procPolicy
        overrideAction:(SNTOverrideFileAccessAction)overrideAction {
  if (msg->action_type != ES_ACTION_TYPE_AUTH) {
    return;
  }

  std::vector<FAAPolicyProcessor::TargetPolicyPair> targetPolicyPairs;
  for (const FAAPolicyProcessor::PathTarget &target : FAAPolicyProcessor::PathTargets(msg)) {
    targetPolicyPairs.push_back({target, procPolicy});
  }

  FAAPolicyProcessor::ESResult result = _faaPolicyProcessor->ProcessMessage(
      msg, targetPolicyPairs,
      ^(const es_process_t *, std::pair<dev_t, ino_t>){
          // TODO: reads cache updates
      },
      ^bool(const santa::WatchItemPolicyBase &base_policy,
            const FAAPolicyProcessor::PathTarget &target, const Message &msg) {
        const ProcessWatchItemPolicy *policy =
            dynamic_cast<const ProcessWatchItemPolicy *>(&base_policy);
        if (!policy) {
          LOGW(@"Failed to cast process policy");
          return false;
        }

        if (policy->tree->Contains(target.path.c_str())) {
          return true;
        } else {
          return false;
        }
      },
      self.fileAccessDeniedBlock, overrideAction);

  [self respondToMessage:msg withAuthResult:result.auth_result cacheable:result.cacheable];
}

- (void)handleMessage:(Message &&)esMsg
    recordEventMetrics:(void (^)(santa::EventDisposition))recordEventMetrics {
  switch (esMsg->event_type) {
    case ES_EVENT_TYPE_NOTIFY_EXEC: {
      // If the exec was allowed, remove the pid/pidver of the process that
      // was just replaced. If the exec was denied, cleanup the entry that
      // was added optimistically in the probe. The EXIT event will take care
      // of the original entry later on.
      if (esMsg->action.notify.result.auth == ES_AUTH_RESULT_ALLOW) {
        _procRuleCache->remove(PidPidver(esMsg->process));
      } else {
        _procRuleCache->remove(PidPidver(esMsg->event.exec.target));
      }

      return;
    }

    case ES_EVENT_TYPE_NOTIFY_FORK: {
      // Clone the policy from the parent to the child.
      // NB: This is safe to do as two steps (get+set) since we process the
      // fork synchronously which will occur before any EXIT event.
      std::shared_ptr<ProcessWatchItemPolicy> policy =
          _procRuleCache->get(PidPidver(esMsg->process));
      if (policy) {
        _procRuleCache->set(PidPidver(esMsg->event.fork.child), policy);
      }
      return;
    }

    case ES_EVENT_TYPE_NOTIFY_EXIT: {
      _procRuleCache->remove(PidPidver(esMsg->process));
      return;
    };

    default: break;
  }

  std::shared_ptr<ProcessWatchItemPolicy> policy = _procRuleCache->get(PidPidver(esMsg->process));
  if (!policy) {
    auto [pid, pidver] = PidPidver(esMsg->process);
    LOGW(@"Policy unexpectedly missing for process: %d/%d: %s", pid, pidver,
         esMsg->process->executable->path.data);

    if (esMsg->action_type == ES_ACTION_TYPE_AUTH) {
      [self respondToMessage:esMsg withAuthResult:ES_AUTH_RESULT_ALLOW cacheable:true];
    }

    return;
  }

  SNTOverrideFileAccessAction overrideAction = [self.configurator overrideFileAccessAction];

  [self processMessage:std::move(esMsg)
               handler:^(Message msg) {
                 [self processMessage:std::move(msg) policy:policy overrideAction:overrideAction];
                 recordEventMetrics(santa::EventDisposition::kProcessed);
               }];
}

- (santa::ProbeInterest)probeInterest:(const santa::Message &)esMsg {
  if (!self.isSubscribed) {
    return santa::ProbeInterest::kUninterested;
  }

  __block santa::ProbeInterest interest = santa::ProbeInterest::kUninterested;

  self.iterateProcessPoliciesBlock(^bool(std::shared_ptr<ProcessWatchItemPolicy> policy) {
    ProcessRuleCache *cache = _procRuleCache.get();
    for (const santa::WatchItemProcess &policyProcess : policy->processes) {
      if (_faaPolicyProcessor->PolicyMatchesProcess(policyProcess, esMsg->event.exec.target)) {
        // Map the new process to the matched policy and begin
        // watching the new process
        cache->set(PidPidver(esMsg->event.exec.target), policy);
        [self muteProcess:&esMsg->event.exec.target->audit_token];

        interest = santa::ProbeInterest::kInterested;

        // Stop iteration, no need to continue once a match is found
        return true;
      }
    }

    return false;
  });

  return interest;
}

- (void)enable {
  static const std::set<es_event_type_t> events = {
      ES_EVENT_TYPE_AUTH_CLONE,        ES_EVENT_TYPE_AUTH_COPYFILE, ES_EVENT_TYPE_AUTH_CREATE,
      ES_EVENT_TYPE_AUTH_EXCHANGEDATA, ES_EVENT_TYPE_AUTH_LINK,     ES_EVENT_TYPE_AUTH_OPEN,
      ES_EVENT_TYPE_AUTH_RENAME,       ES_EVENT_TYPE_AUTH_TRUNCATE, ES_EVENT_TYPE_AUTH_UNLINK,
      ES_EVENT_TYPE_NOTIFY_EXEC,       ES_EVENT_TYPE_NOTIFY_EXIT,   ES_EVENT_TYPE_NOTIFY_FORK};

  if (!self.isSubscribed) {
    if ([super subscribe:events]) {
      LOGD(@"Proc FAA subscribed");
      self.isSubscribed = true;
    }
  }

  // Always clear cache to ensure operations that were previously allowed are re-evaluated.
  [super clearCache];
}

- (void)disable {
  if (self.isSubscribed) {
    if ([super unsubscribeAll]) {
      LOGD(@"Proc FAA unsubscribed");
      self.isSubscribed = false;
    }
    [super unmuteAllTargetPaths];
  }
}

- (void)processWatchItemsCount:(size_t)count {
  if (count > 0) {
    [self enable];
  } else {
    [self disable];
  }
}

@end
