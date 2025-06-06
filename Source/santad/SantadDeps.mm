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

#include "Source/santad/SantadDeps.h"

#include <cstdlib>
#include <memory>

#include "Source/common/RingBuffer.h"
#import "Source/common/SNTExportConfiguration.h"
#import "Source/common/SNTLogging.h"
#import "Source/common/SNTMetricSet.h"
#import "Source/common/SNTXPCControlInterface.h"
#include "Source/common/TelemetryEventMap.h"
#import "Source/santad/DataLayer/SNTEventTable.h"
#import "Source/santad/DataLayer/SNTRuleTable.h"
#include "Source/santad/DataLayer/WatchItems.h"
#include "Source/santad/EventProviders/EndpointSecurity/EndpointSecurityAPI.h"
#include "Source/santad/ProcessTree/annotations/originator.h"
#include "Source/santad/ProcessTree/process_tree.h"
#import "Source/santad/SNTDatabaseController.h"
#include "Source/santad/SNTDecisionCache.h"
#include "Source/santad/TTYWriter.h"

using santa::AuthResultCache;
using santa::Enricher;
using santa::Logger;
using santa::Metrics;
using santa::PrefixTree;
using santa::TTYWriter;
using santa::WatchItems;

namespace santa {

std::unique_ptr<SantadDeps> SantadDeps::Create(SNTConfigurator *configurator,
                                               SNTMetricSet *metric_set,
                                               santa::ProcessControlBlock processControlBlock) {
  // TODO(mlw): The XPC interfaces should be injectable. Could either make a new
  // protocol defining appropriate methods or accept values as params.
  MOLXPCConnection *control_connection =
      [[MOLXPCConnection alloc] initServerWithName:[SNTXPCControlInterface serviceID]];
  if (!control_connection) {
    LOGE(@"Failed to initialize control connection.");
    exit(EXIT_FAILURE);
  }

  control_connection.privilegedInterface = [SNTXPCControlInterface controlInterface];
  control_connection.unprivilegedInterface = [SNTXPCUnprivilegedControlInterface controlInterface];

  SNTRuleTable *rule_table = [SNTDatabaseController ruleTable];
  if (!rule_table) {
    LOGE(@"Failed to initialize rule table.");
    exit(EXIT_FAILURE);
  }

  SNTEventTable *event_table = [SNTDatabaseController eventTable];
  if (!event_table) {
    LOGE(@"Failed to initialize event table.");
    exit(EXIT_FAILURE);
  }

  SNTCompilerController *compiler_controller = [[SNTCompilerController alloc] init];
  if (!compiler_controller) {
    LOGE(@"Failed to initialize compiler controller.");
    exit(EXIT_FAILURE);
  }

  auto ringbuf = std::make_unique<RingBuffer<NSMutableDictionary *>>(10);
  SNTNotificationQueue *notifier_queue =
      [[SNTNotificationQueue alloc] initWithRingBuffer:std::move(ringbuf)];
  if (!notifier_queue) {
    LOGE(@"Failed to initialize notification queue.");
    exit(EXIT_FAILURE);
  }

  SNTSyncdQueue *syncd_queue = [[SNTSyncdQueue alloc] init];
  if (!syncd_queue) {
    LOGE(@"Failed to initialize syncd queue.");
    exit(EXIT_FAILURE);
  }

  std::shared_ptr<::TTYWriter> tty_writer = TTYWriter::Create(configurator.enableSilentTTYMode);
  if (!tty_writer) {
    LOGE(@"Failed to initialize TTY writer");
    exit(EXIT_FAILURE);
  }

  SNTExecutionController *exec_controller =
      [[SNTExecutionController alloc] initWithRuleTable:rule_table
                                             eventTable:event_table
                                          notifierQueue:notifier_queue
                                             syncdQueue:syncd_queue
                                              ttyWriter:tty_writer
                               entitlementsPrefixFilter:[configurator entitlementsPrefixFilter]
                               entitlementsTeamIDFilter:[configurator entitlementsTeamIDFilter]
                                    processControlBlock:processControlBlock];
  if (!exec_controller) {
    LOGE(@"Failed to initialize exec controller.");
    exit(EXIT_FAILURE);
  }

  std::shared_ptr<::PrefixTree<Unit>> prefix_tree = std::make_shared<::PrefixTree<Unit>>();

  // TODO(bur): Add KVO handling for fileChangesPrefixFilters.
  NSArray<NSString *> *prefix_filters =
      [@[ @"/.", @"/dev/" ] arrayByAddingObjectsFromArray:[configurator fileChangesPrefixFilters]];
  for (NSString *filter in prefix_filters) {
    prefix_tree->InsertPrefix([filter fileSystemRepresentation], Unit {});
  }

  std::shared_ptr<EndpointSecurityAPI> esapi = std::make_shared<EndpointSecurityAPI>();
  if (!esapi) {
    LOGE(@"Failed to create ES API wrapper.");
    exit(EXIT_FAILURE);
  }

  size_t spool_file_threshold_bytes = [configurator spoolDirectoryFileSizeThresholdKB] * 1024;
  size_t spool_dir_threshold_bytes = [configurator spoolDirectorySizeThresholdMB] * 1024 * 1024;
  uint64_t spool_flush_timeout_ms = [configurator spoolDirectoryEventMaxFlushTimeSec] * 1000;
  uint32_t telemetry_export_frequency_secs = [configurator telemetryExportIntervalSec];

  std::unique_ptr<::Logger> logger = Logger::Create(
      esapi, syncd_queue,
      ^SNTExportConfiguration *() {
        return [configurator exportConfig];
      },
      TelemetryConfigToBitmask([configurator telemetry], [configurator enableAllEventUpload]),
      [configurator eventLogType], [SNTDecisionCache sharedCache], [configurator eventLogPath],
      [configurator spoolDirectory], spool_dir_threshold_bytes, spool_file_threshold_bytes,
      spool_flush_timeout_ms, telemetry_export_frequency_secs);
  if (!logger) {
    LOGE(@"Failed to create logger.");
    exit(EXIT_FAILURE);
  }

  std::shared_ptr<::WatchItems> watch_items =
      [configurator fileAccessPolicy]
          ? WatchItems::Create([configurator fileAccessPolicy],
                               [configurator fileAccessPolicyUpdateIntervalSec])
          : WatchItems::Create([configurator fileAccessPolicyPlist],
                               [configurator fileAccessPolicyUpdateIntervalSec]);
  if (!watch_items) {
    LOGE(@"Failed to create watch items");
    exit(EXIT_FAILURE);
  }

  std::shared_ptr<::Metrics> metrics =
      Metrics::Create(metric_set, [configurator metricExportInterval]);
  if (!metrics) {
    LOGE(@"Failed to create metrics");
    exit(EXIT_FAILURE);
  }

  std::shared_ptr<::AuthResultCache> auth_result_cache = AuthResultCache::Create(esapi, metric_set);
  if (!auth_result_cache) {
    LOGE(@"Failed to create auth result cache");
    exit(EXIT_FAILURE);
  }

  std::shared_ptr<santa::santad::process_tree::ProcessTree> process_tree;
  std::vector<std::unique_ptr<santa::santad::process_tree::Annotator>> annotators;

  for (NSString *annotation in [configurator enabledProcessAnnotations]) {
    if ([[annotation lowercaseString] isEqualToString:@"originator"]) {
      annotators.emplace_back(std::make_unique<santa::santad::process_tree::OriginatorAnnotator>());
    } else {
      LOGW(@"Unrecognized process annotation %@", annotation);
    }
  }

  auto tree_status = santa::santad::process_tree::CreateTree(std::move(annotators));
  if (!tree_status.ok()) {
    LOGE(@"Failed to create process tree: %@", @(tree_status.status().ToString().c_str()));
    exit(EXIT_FAILURE);
  }
  process_tree = *tree_status;

  return std::make_unique<SantadDeps>(
      esapi, std::move(logger), std::move(metrics), std::move(watch_items),
      std::move(auth_result_cache), control_connection, compiler_controller, notifier_queue,
      syncd_queue, exec_controller, prefix_tree, std::move(tty_writer), std::move(process_tree));
}

SantadDeps::SantadDeps(
    std::shared_ptr<EndpointSecurityAPI> esapi, std::unique_ptr<::Logger> logger,
    std::shared_ptr<::Metrics> metrics, std::shared_ptr<::WatchItems> watch_items,
    std::shared_ptr<santa::AuthResultCache> auth_result_cache, MOLXPCConnection *control_connection,
    SNTCompilerController *compiler_controller, SNTNotificationQueue *notifier_queue,
    SNTSyncdQueue *syncd_queue, SNTExecutionController *exec_controller,
    std::shared_ptr<::PrefixTree<Unit>> prefix_tree, std::shared_ptr<::TTYWriter> tty_writer,
    std::shared_ptr<santa::santad::process_tree::ProcessTree> process_tree)
    : esapi_(std::move(esapi)),
      logger_(std::move(logger)),
      metrics_(std::move(metrics)),
      watch_items_(std::move(watch_items)),
      enricher_(std::make_shared<::Enricher>(process_tree)),
      auth_result_cache_(std::move(auth_result_cache)),
      control_connection_(control_connection),
      compiler_controller_(compiler_controller),
      notifier_queue_(notifier_queue),
      syncd_queue_(syncd_queue),
      exec_controller_(exec_controller),
      prefix_tree_(prefix_tree),
      tty_writer_(std::move(tty_writer)),
      process_tree_(std::move(process_tree)) {}

std::shared_ptr<::AuthResultCache> SantadDeps::AuthResultCache() {
  return auth_result_cache_;
}

std::shared_ptr<Enricher> SantadDeps::Enricher() {
  return enricher_;
}
std::shared_ptr<EndpointSecurityAPI> SantadDeps::ESAPI() {
  return esapi_;
}

std::shared_ptr<Logger> SantadDeps::Logger() {
  return logger_;
}

std::shared_ptr<::Metrics> SantadDeps::Metrics() {
  return metrics_;
}

std::shared_ptr<::WatchItems> SantadDeps::WatchItems() {
  return watch_items_;
}

MOLXPCConnection *SantadDeps::ControlConnection() {
  return control_connection_;
}

SNTCompilerController *SantadDeps::CompilerController() {
  return compiler_controller_;
}

SNTNotificationQueue *SantadDeps::NotifierQueue() {
  return notifier_queue_;
}

SNTSyncdQueue *SantadDeps::SyncdQueue() {
  return syncd_queue_;
}

SNTExecutionController *SantadDeps::ExecController() {
  return exec_controller_;
}

std::shared_ptr<PrefixTree<Unit>> SantadDeps::PrefixTree() {
  return prefix_tree_;
}

std::shared_ptr<::TTYWriter> SantadDeps::TTYWriter() {
  return tty_writer_;
}

std::shared_ptr<santa::santad::process_tree::ProcessTree> SantadDeps::ProcessTree() {
  return process_tree_;
}

}  // namespace santa
