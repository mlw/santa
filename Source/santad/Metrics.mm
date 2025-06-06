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

#include "Source/santad/Metrics.h"

#include <EndpointSecurity/ESTypes.h>

#include <memory>

#include "Source/common/Platform.h"
#import "Source/common/SNTLogging.h"
#import "Source/common/SNTXPCMetricServiceInterface.h"
#import "Source/santad/SNTApplicationCoreMetrics.h"

static NSString *const kProcessorAuthorizer = @"Authorizer";
static NSString *const kProcessorDeviceManager = @"DeviceManager";
static NSString *const kProcessorRecorder = @"Recorder";
static NSString *const kProcessorTamperResistance = @"TamperResistance";
static NSString *const kProcessorDataFileAccessAuthorizer = @"DataFileAccessAuthorizer";
static NSString *const kProcessorProcessFileAccessAuthorizer = @"ProcessFileAccessAuthorizer";

static NSString *const kEventTypeAuthClone = @"AuthClone";
static NSString *const kEventTypeAuthCopyfile = @"AuthCopyfile";
static NSString *const kEventTypeAuthCreate = @"AuthCreate";
static NSString *const kEventTypeAuthExchangedata = @"AuthExchangedata";
static NSString *const kEventTypeAuthExec = @"AuthExec";
static NSString *const kEventTypeAuthKextload = @"AuthKextload";
static NSString *const kEventTypeAuthLink = @"AuthLink";
static NSString *const kEventTypeAuthMount = @"AuthMount";
static NSString *const kEventTypeAuthOpen = @"AuthOpen";
static NSString *const kEventTypeAuthRemount = @"AuthRemount";
static NSString *const kEventTypeAuthRename = @"AuthRename";
static NSString *const kEventTypeAuthSignal = @"AuthSignal";
static NSString *const kEventTypeAuthProcSuspendResume = @"AuthProcSuspendResume";
static NSString *const kEventTypeAuthTruncate = @"AuthTruncate";
static NSString *const kEventTypeAuthUnlink = @"AuthUnlink";
static NSString *const kEventTypeNotifyClone = @"NotifyClone";
static NSString *const kEventTypeNotifyClose = @"NotifyClose";
static NSString *const kEventTypeNotifyCodesigningInvalidated = @"NotifyCodesigningInvalidated";
static NSString *const kEventTypeNotifyCopyfile = @"NotifyCopyfile";
static NSString *const kEventTypeNotifyExchangedata = @"NotifyExchangedata";
static NSString *const kEventTypeNotifyExec = @"NotifyExec";
static NSString *const kEventTypeNotifyExit = @"NotifyExit";
static NSString *const kEventTypeNotifyFork = @"NotifyFork";
static NSString *const kEventTypeNotifyLink = @"NotifyLink";
static NSString *const kEventTypeNotifyRename = @"NotifyRename";
static NSString *const kEventTypeNotifyUnlink = @"NotifyUnlink";
static NSString *const kEventTypeNotifyUnmount = @"NotifyUnmount";
static NSString *const kPseudoEventTypeGlobal = @"Global";
static NSString *const kEventTypeNotifyAuthentication = @"NotifyAuthentication";
static NSString *const kEventTypeNotifyLoginLogin = @"NotifyLoginLogin";
static NSString *const kEventTypeNotifyLoginLogout = @"NotifyLoginLogout";
static NSString *const kEventTypeNotifyLWSessionLogin = @"NotifyLWSessionLogin";
static NSString *const kEventTypeNotifyLWSessionLogout = @"NotifyLWSessionLogout";
static NSString *const kEventTypeNotifyLWSessionLock = @"NotifyLWSessionLock";
static NSString *const kEventTypeNotifyLWSessionUnlock = @"NotifyLWSessionUnlock";
static NSString *const kEventTypeNotifyScreensharingAttach = @"NotifyScreensharingAttach";
static NSString *const kEventTypeNotifyScreensharingDetach = @"NotifyScreensharingDetach";
static NSString *const kEventTypeNotifyOpenSSHLogin = @"NotifyOpenSSHLogin";
static NSString *const kEventTypeNotifyOpenSSHLogout = @"NotifyOpenSSHLogout";
static NSString *const kEventTypeNotifyLaunchItemAdd = @"NotifyLaunchItemAdd";
static NSString *const kEventTypeNotifyLaunchItemRemove = @"NotifyLaunchItemRemove";
static NSString *const kEventTypeNotifyXProtectDetected = @"NotifyXProtectDetected";
static NSString *const kEventTypeNotifyXProtectRemediated = @"NotifyXProtectRemediated";
#if HAVE_MACOS_15
static NSString *const kEventTypeNotifyGatekeeperOverride = @"NotifyGatekeeperOverride";
#endif  // HAVE_MACOS_15
#if HAVE_MACOS_15_4
static NSString *const kEventTypeNotifyTCCModification = @"NotifyTCCModification";
#endif  // HAVE_MACOS_15_4

static NSString *const kEventDispositionDropped = @"Dropped";
static NSString *const kEventDispositionProcessed = @"Processed";

static NSString *const kStatChangeStepNoChange = @"NoChange";
static NSString *const kStatChangeStepMessageCreate = @"MessageCreate";
static NSString *const kStatChangeStepCodesignValidation = @"CodesignValidation";

static NSString *const kStatResultOK = @"OK";
static NSString *const kStatResultStatError = @"StatError";
static NSString *const kStatResultDevnoInodeMismatch = @"DevnoInodeMismatch";

// Compat values
static NSString *const kFileAccessMetricStatusOK = @"OK";
static NSString *const kFileAccessMetricStatusBlockedUser = @"BLOCKED_USER";

static NSString *const kFileAccessPolicyDecisionDenied = @"Denied";
static NSString *const kFileAccessPolicyDecisionDeniedInvalidSignature = @"Denied";
static NSString *const kFileAccessPolicyDecisionAllowedAuditOnly = @"AllowedAuditOnly";

static NSString *const kFileAccessMetricsAccessType = @"access";

namespace santa {

NSString *const ProcessorToString(Processor processor) {
  switch (processor) {
    case Processor::kAuthorizer: return kProcessorAuthorizer;
    case Processor::kDeviceManager: return kProcessorDeviceManager;
    case Processor::kRecorder: return kProcessorRecorder;
    case Processor::kTamperResistance: return kProcessorTamperResistance;
    case Processor::kDataFileAccessAuthorizer: return kProcessorDataFileAccessAuthorizer;
    case Processor::kProcessFileAccessAuthorizer: return kProcessorProcessFileAccessAuthorizer;
    default:
      [NSException raise:@"Invalid processor"
                  format:@"Unknown processor value: %d", static_cast<int>(processor)];
      return nil;
  }
}

NSString *const EventTypeToString(es_event_type_t eventType) {
  switch (eventType) {
    case ES_EVENT_TYPE_AUTH_CLONE: return kEventTypeAuthClone;
    case ES_EVENT_TYPE_AUTH_COPYFILE: return kEventTypeAuthCopyfile;
    case ES_EVENT_TYPE_AUTH_CREATE: return kEventTypeAuthCreate;
    case ES_EVENT_TYPE_AUTH_EXCHANGEDATA: return kEventTypeAuthExchangedata;
    case ES_EVENT_TYPE_AUTH_EXEC: return kEventTypeAuthExec;
    case ES_EVENT_TYPE_AUTH_KEXTLOAD: return kEventTypeAuthKextload;
    case ES_EVENT_TYPE_AUTH_LINK: return kEventTypeAuthLink;
    case ES_EVENT_TYPE_AUTH_MOUNT: return kEventTypeAuthMount;
    case ES_EVENT_TYPE_AUTH_OPEN: return kEventTypeAuthOpen;
    case ES_EVENT_TYPE_AUTH_REMOUNT: return kEventTypeAuthRemount;
    case ES_EVENT_TYPE_AUTH_RENAME: return kEventTypeAuthRename;
    case ES_EVENT_TYPE_AUTH_SIGNAL: return kEventTypeAuthSignal;
    case ES_EVENT_TYPE_AUTH_PROC_SUSPEND_RESUME: return kEventTypeAuthProcSuspendResume;
    case ES_EVENT_TYPE_AUTH_TRUNCATE: return kEventTypeAuthTruncate;
    case ES_EVENT_TYPE_AUTH_UNLINK: return kEventTypeAuthUnlink;
    case ES_EVENT_TYPE_NOTIFY_CLONE: return kEventTypeNotifyClone;
    case ES_EVENT_TYPE_NOTIFY_CLOSE: return kEventTypeNotifyClose;
    case ES_EVENT_TYPE_NOTIFY_COPYFILE: return kEventTypeNotifyCopyfile;
    case ES_EVENT_TYPE_NOTIFY_CS_INVALIDATED: return kEventTypeNotifyCodesigningInvalidated;
    case ES_EVENT_TYPE_NOTIFY_EXCHANGEDATA: return kEventTypeNotifyExchangedata;
    case ES_EVENT_TYPE_NOTIFY_EXEC: return kEventTypeNotifyExec;
    case ES_EVENT_TYPE_NOTIFY_EXIT: return kEventTypeNotifyExit;
    case ES_EVENT_TYPE_NOTIFY_FORK: return kEventTypeNotifyFork;
    case ES_EVENT_TYPE_NOTIFY_LINK: return kEventTypeNotifyLink;
    case ES_EVENT_TYPE_NOTIFY_RENAME: return kEventTypeNotifyRename;
    case ES_EVENT_TYPE_NOTIFY_UNLINK: return kEventTypeNotifyUnlink;
    case ES_EVENT_TYPE_NOTIFY_UNMOUNT: return kEventTypeNotifyUnmount;
    case ES_EVENT_TYPE_NOTIFY_AUTHENTICATION: return kEventTypeNotifyAuthentication;
    case ES_EVENT_TYPE_NOTIFY_LOGIN_LOGIN: return kEventTypeNotifyLoginLogin;
    case ES_EVENT_TYPE_NOTIFY_LOGIN_LOGOUT: return kEventTypeNotifyLoginLogout;
    case ES_EVENT_TYPE_NOTIFY_LW_SESSION_LOGIN: return kEventTypeNotifyLWSessionLogin;
    case ES_EVENT_TYPE_NOTIFY_LW_SESSION_LOGOUT: return kEventTypeNotifyLWSessionLogout;
    case ES_EVENT_TYPE_NOTIFY_LW_SESSION_LOCK: return kEventTypeNotifyLWSessionLock;
    case ES_EVENT_TYPE_NOTIFY_LW_SESSION_UNLOCK: return kEventTypeNotifyLWSessionUnlock;
    case ES_EVENT_TYPE_NOTIFY_SCREENSHARING_ATTACH: return kEventTypeNotifyScreensharingAttach;
    case ES_EVENT_TYPE_NOTIFY_SCREENSHARING_DETACH: return kEventTypeNotifyScreensharingDetach;
    case ES_EVENT_TYPE_NOTIFY_OPENSSH_LOGIN: return kEventTypeNotifyOpenSSHLogin;
    case ES_EVENT_TYPE_NOTIFY_OPENSSH_LOGOUT: return kEventTypeNotifyOpenSSHLogout;
    case ES_EVENT_TYPE_NOTIFY_BTM_LAUNCH_ITEM_ADD: return kEventTypeNotifyLaunchItemAdd;
    case ES_EVENT_TYPE_NOTIFY_BTM_LAUNCH_ITEM_REMOVE: return kEventTypeNotifyLaunchItemRemove;
    case ES_EVENT_TYPE_NOTIFY_XP_MALWARE_DETECTED: return kEventTypeNotifyXProtectDetected;
    case ES_EVENT_TYPE_NOTIFY_XP_MALWARE_REMEDIATED: return kEventTypeNotifyXProtectRemediated;
#if HAVE_MACOS_15
    case ES_EVENT_TYPE_NOTIFY_GATEKEEPER_USER_OVERRIDE: return kEventTypeNotifyGatekeeperOverride;
#endif  // HAVE_MACOS_15
#if HAVE_MACOS_15_4
    case ES_EVENT_TYPE_NOTIFY_TCC_MODIFY: return kEventTypeNotifyTCCModification;
#endif  // HAVE_MACOS_15_4
    case ES_EVENT_TYPE_LAST: return kPseudoEventTypeGlobal;
    default:
      [NSException raise:@"Invalid event type" format:@"Invalid event type: %d", eventType];
      return nil;
  }
}

NSString *const EventDispositionToString(EventDisposition d) {
  switch (d) {
    case EventDisposition::kDropped: return kEventDispositionDropped;
    case EventDisposition::kProcessed: return kEventDispositionProcessed;
    default:
      [NSException raise:@"Invalid disposition"
                  format:@"Unknown disposition value: %d", static_cast<int>(d)];
      return nil;
  }
}

NSString *const FileAccessMetricStatusToString(FileAccessMetricStatus status) {
  switch (status) {
    case FileAccessMetricStatus::kOK: return kFileAccessMetricStatusOK;
    case FileAccessMetricStatus::kBlockedUser: return kFileAccessMetricStatusBlockedUser;
    default:
      [NSException raise:@"Invalid file access metric status"
                  format:@"Unknown file access metric status value: %d", static_cast<int>(status)];
      return nil;
  }
}

NSString *const FileAccessPolicyDecisionToString(FileAccessPolicyDecision decision) {
  switch (decision) {
    case FileAccessPolicyDecision::kDenied: return kFileAccessPolicyDecisionDenied;
    case FileAccessPolicyDecision::kDeniedInvalidSignature:
      return kFileAccessPolicyDecisionDeniedInvalidSignature;
    case FileAccessPolicyDecision::kAllowedAuditOnly:
      return kFileAccessPolicyDecisionAllowedAuditOnly;
    default:
      [NSException
           raise:@"Invalid file access policy decision"
          format:@"Unknown file access policy decision value: %d", static_cast<int>(decision)];
      return nil;
  }
}

std::shared_ptr<Metrics> Metrics::Create(SNTMetricSet *metric_set, uint64_t interval) {
  dispatch_queue_t q = dispatch_queue_create("com.northpolesec.santa.santametricsservice.q",
                                             DISPATCH_QUEUE_SERIAL_WITH_AUTORELEASE_POOL);

  dispatch_source_t timer_source = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);

  SNTMetricInt64Gauge *event_processing_times =
      [metric_set int64GaugeWithName:@"/santa/event_processing_time"
                          fieldNames:@[ @"Processor", @"Event" ]
                            helpText:@"Time to process various event types by each processor"];

  SNTMetricCounter *event_counts =
      [metric_set counterWithName:@"/santa/event_count"
                       fieldNames:@[ @"Processor", @"Event", @"Disposition" ]
                         helpText:@"Events received and processed by each processor"];

  SNTMetricCounter *rate_limit_counts =
      [metric_set counterWithName:@"/santa/rate_limit_count"
                       fieldNames:@[]
                         helpText:@"Number of FAA events rate limited"];

  SNTMetricCounter *faa_event_counts = [metric_set
      counterWithName:@"/santa/file_access_authorizer/log/count"
           fieldNames:@[
             @"config_version", @"access_type", @"rule_id", @"status", @"operation", @"decision"
           ]
             helpText:@"Count of times a log is emitted from the File Access Authorizer client"];

  SNTMetricCounter *drop_counts =
      [metric_set counterWithName:@"/santa/event_drop_count"
                       fieldNames:@[ @"Processor", @"Event" ]
                         helpText:@"Count of the number of drops for each event"];

  std::shared_ptr<Metrics> metrics = std::make_shared<Metrics>(
      q, timer_source, interval, event_processing_times, event_counts, rate_limit_counts,
      faa_event_counts, drop_counts, metric_set, ^(Metrics *metrics) {
        SNTRegisterCoreMetrics();
        metrics->EstablishConnection();
      });

  std::weak_ptr<Metrics> weak_metrics(metrics);
  dispatch_source_set_event_handler(metrics->timer_source_, ^{
    std::shared_ptr<Metrics> shared_metrics = weak_metrics.lock();
    if (!shared_metrics) {
      return;
    }

    shared_metrics->ExportSerialized(metric_set);
  });

  return metrics;
}

Metrics::Metrics(dispatch_queue_t q, dispatch_source_t timer_source, uint64_t interval,
                 SNTMetricInt64Gauge *event_processing_times, SNTMetricCounter *event_counts,
                 SNTMetricCounter *rate_limit_counts, SNTMetricCounter *faa_event_counts,
                 SNTMetricCounter *drop_counts, SNTMetricSet *metric_set,
                 void (^run_on_first_start)(Metrics *))
    : q_(q),
      timer_source_(timer_source),
      interval_(interval),
      event_processing_times_(event_processing_times),
      event_counts_(event_counts),
      rate_limit_counts_(rate_limit_counts),
      faa_event_counts_(faa_event_counts),
      drop_counts_(drop_counts),
      metric_set_(metric_set),
      run_on_first_start_(run_on_first_start),
      rate_limit_counts_cache_(0) {
  SetInterval(interval_);

  events_q_ = dispatch_queue_create("com.northpolesec.santa.santametricsservice.events_q",
                                    DISPATCH_QUEUE_SERIAL_WITH_AUTORELEASE_POOL);
}

Metrics::~Metrics() {
  if (!running_) {
    // The timer_source_ must be resumed to ensure it has a proper retain count before being
    // destroyed. Additionally, it should first be cancelled to ensure the timer isn't ever fired
    // (see man page for `dispatch_source_cancel(3)`).
    dispatch_source_cancel(timer_source_);
    dispatch_resume(timer_source_);
  }
}

void Metrics::EstablishConnection() {
  MOLXPCConnection *metrics_connection = [SNTXPCMetricServiceInterface configuredConnection];
  metrics_connection.invalidationHandler = ^{
    dispatch_sync(dispatch_get_main_queue(), ^{
      LOGW(@"Metrics service connection invalidated. Reconnecting...");
      EstablishConnection();
    });
  };
  [metrics_connection resume];
  metrics_connection_ = metrics_connection;
}

void Metrics::Export() {
  dispatch_sync(q_, ^{
    ExportSerialized(metric_set_);
  });
}

void Metrics::ExportSerialized(SNTMetricSet *metric_set) {
  FlushMetrics();
  [[metrics_connection_ remoteObjectProxy] exportForMonitoring:[metric_set export]];
}

void Metrics::FlushMetrics() {
  dispatch_sync(events_q_, ^{
    for (const auto &kv : event_counts_cache_) {
      NSString *processorName = ProcessorToString(std::get<Processor>(kv.first));
      NSString *eventName = EventTypeToString(std::get<es_event_type_t>(kv.first));
      NSString *dispositionName = EventDispositionToString(std::get<EventDisposition>(kv.first));

      [event_counts_ incrementBy:kv.second
                  forFieldValues:@[ processorName, eventName, dispositionName ]];
    }

    for (const auto &kv : event_times_cache_) {
      NSString *processorName = ProcessorToString(std::get<Processor>(kv.first));
      NSString *eventName = EventTypeToString(std::get<es_event_type_t>(kv.first));

      [event_processing_times_ set:kv.second forFieldValues:@[ processorName, eventName ]];
    }

    // NB: Must use exchange here to atomically fetch the old value and reset the count. Doing
    // both operations atomically means a dispatch queue is not needed in AddRateLimitingMetrics().
    [rate_limit_counts_ incrementBy:rate_limit_counts_cache_.exchange(0, std::memory_order_relaxed)
                     forFieldValues:@[]];

    for (const auto &kv : faa_event_counts_cache_) {
      NSString *policyVersion = @(std::get<0>(kv.first).c_str());  // FileAccessMetricsPolicyVersion
      NSString *policyName = @(std::get<1>(kv.first).c_str());     // FileAccessMetricsPolicyName
      NSString *eventName = EventTypeToString(std::get<es_event_type_t>(kv.first));
      NSString *status = FileAccessMetricStatusToString(std::get<FileAccessMetricStatus>(kv.first));
      NSString *decision =
          FileAccessPolicyDecisionToString(std::get<FileAccessPolicyDecision>(kv.first));

      [faa_event_counts_
             incrementBy:kv.second
          forFieldValues:@[
            policyVersion, kFileAccessMetricsAccessType, policyName, status, eventName, decision
          ]];
    }

    for (auto &[key, stats] : drop_cache_) {
      if (stats.drops > 0) {
        NSString *processorName = ProcessorToString(std::get<Processor>(key));
        NSString *eventName = EventTypeToString(std::get<es_event_type_t>(key));

        [drop_counts_ incrementBy:stats.drops forFieldValues:@[ processorName, eventName ]];

        // Reset drops to 0, but leave sequence number intact. Sequence numbers
        // must persist so that accurate drops can be counted.
        stats.drops = 0;
      }
    }

    // Reset the maps so the next cycle begins with a clean state
    // IMPORTANT: Do not reset drop_cache_, the sequence numbers must persist
    // for accurate accounting
    event_counts_cache_ = {};
    event_times_cache_ = {};
    faa_event_counts_cache_ = {};
  });
}

void Metrics::SetInterval(uint64_t interval) {
  dispatch_sync(q_, ^{
    LOGI(@"Setting metrics interval to %llu (exporting? %s)", interval, running_ ? "YES" : "NO");
    interval_ = interval;
    dispatch_source_set_timer(timer_source_, dispatch_time(DISPATCH_TIME_NOW, 0),
                              interval_ * NSEC_PER_SEC, 250 * NSEC_PER_MSEC);
  });
}

void Metrics::StartPoll() {
  static dispatch_once_t once_token;
  dispatch_once(&once_token, ^{
    run_on_first_start_(this);
  });

  dispatch_sync(q_, ^{
    if (!running_) {
      LOGI(@"Starting to export metrics every %llu seconds", interval_);
      running_ = true;
      dispatch_resume(timer_source_);
    } else {
      LOGW(@"Attempted to start metrics poll while already started");
    }
  });
}

void Metrics::StopPoll() {
  dispatch_sync(q_, ^{
    if (running_) {
      LOGI(@"Stopping metrics export");
      dispatch_suspend(timer_source_);
      running_ = false;
    } else {
      LOGW(@"Attempted to stop metrics poll while already stopped");
    }
  });
}

void Metrics::SetEventMetrics(Processor processor, EventDisposition event_disposition,
                              int64_t nanos, const santa::Message &msg) {
  dispatch_sync(events_q_, ^{
    event_counts_cache_[EventCountTuple{processor, msg->event_type, event_disposition}]++;
    event_times_cache_[EventTimesTuple{processor, msg->event_type}] = nanos;
  });
}

void Metrics::UpdateEventStats(Processor processor, const es_message_t *msg) {
  dispatch_sync(events_q_, ^{
    EventStatsTuple event_stats_key{processor, msg->event_type};
    // NB: Using the invalid event type ES_EVENT_TYPE_LAST to store drop counts
    // based on the global sequence number.
    EventStatsTuple global_stats_key{processor, ES_EVENT_TYPE_LAST};

    SequenceStats old_event_stats = drop_cache_[event_stats_key];
    SequenceStats old_global_stats = drop_cache_[global_stats_key];

    // Sequence number should always increment by 1.
    // Drops detected if there is a difference between the current sequence
    // number and the expected sequence number
    int64_t new_event_drops = msg->seq_num - old_event_stats.next_seq_num;
    int64_t new_global_drops = msg->global_seq_num - old_global_stats.next_seq_num;

    // Only log one or the other, prefer the event specific log.
    // For higher volume event types, we'll normally see the event-specific log eventually
    // For lower volume event types, we may only see the global drop message
    if (new_event_drops > 0) {
      LOGD(@"Drops detected for client: %@, event: %@, drops: %llu", ProcessorToString(processor),
           EventTypeToString(msg->event_type), new_event_drops);
    } else if (new_global_drops > 0) {
      LOGD(@"Drops detected globally for client: %@, drops: %llu", ProcessorToString(processor),
           new_global_drops);
    }

    drop_cache_[event_stats_key] = SequenceStats{.next_seq_num = msg->seq_num + 1,
                                                 .drops = old_event_stats.drops + new_event_drops};

    drop_cache_[global_stats_key] =
        SequenceStats{.next_seq_num = msg->global_seq_num + 1,
                      .drops = old_global_stats.drops + new_global_drops};
  });
}

void Metrics::AddRateLimitingMetrics(int64_t events_rate_limited_count) {
  rate_limit_counts_cache_.fetch_add(events_rate_limited_count, std::memory_order_relaxed);
}

void Metrics::SetFileAccessEventMetrics(std::string policy_version, std::string rule_name,
                                        FileAccessMetricStatus status, es_event_type_t event_type,
                                        FileAccessPolicyDecision decision) {
  dispatch_sync(events_q_, ^{
    faa_event_counts_cache_[FileAccessEventCountTuple{
        std::move(policy_version), std::move(rule_name), status, event_type, decision}]++;
  });
}

}  // namespace santa
