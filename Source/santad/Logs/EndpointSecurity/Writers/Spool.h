/// Copyright 2022 Google LLC
/// Copyright 2025 North Pole Security, Inc.
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

#ifndef SANTA__SANTAD__LOGS_ENDPOINTSECURITY_WRITERS_SPOOL_H
#define SANTA__SANTAD__LOGS_ENDPOINTSECURITY_WRITERS_SPOOL_H

#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>

#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "Source/santad/Logs/EndpointSecurity/Writers/FSSpool/fsspool.h"
#include "Source/santad/Logs/EndpointSecurity/Writers/FSSpool/fsspool_log_batch_writer.h"
#include "Source/santad/Logs/EndpointSecurity/Writers/Writer.h"
#include "absl/container/flat_hash_map.h"
#include "absl/container/flat_hash_set.h"

// Forward declarations
namespace santa {
class SpoolPeer;
}

namespace santa {
class Spool : public Writer, public std::enable_shared_from_this<Spool> {
 public:
  // Factory
  static std::shared_ptr<Spool> Create(std::string_view base_dir, size_t max_spool_disk_size,
                                       size_t max_spool_file_size, uint64_t flush_timeout_ms);

  Spool(dispatch_queue_t q, dispatch_source_t timer_source, std::string_view base_dir,
        size_t max_spool_disk_size, size_t max_spool_file_size,
        void (^write_complete_f)(void) = nullptr, void (^flush_task_complete_f)(void) = nullptr);

  ~Spool();

  void Write(std::vector<uint8_t> &&bytes) override;
  void Flush() override;

  std::optional<absl::flat_hash_set<std::string>> GetFilesToExport(size_t max_count) override;
  std::optional<std::string> NextFileToExport() override;
  void FilesExported(absl::flat_hash_map<std::string, bool> files_exported) override;

  void BeginFlushTask();

  // Peer class for testing
  friend class santa::SpoolPeer;

 private:
  bool FlushSerialized();

  dispatch_queue_t q_ = NULL;
  dispatch_source_t timer_source_ = NULL;
  ::fsspool::FsSpoolReader spool_reader_;
  ::fsspool::FsSpoolWriter spool_writer_;
  ::fsspool::FsSpoolLogBatchWriter log_batch_writer_;
  const size_t spool_file_size_threshold_;
  // Make a "leniency factor" of 20%. This will be used to allow some more
  // records to accumulate in the event flushing fails for some reason.
  const double spool_file_size_threshold_leniency_factor_ = 1.2;
  const size_t spool_file_size_threshold_leniency_;
  std::string type_url_;
  bool flush_task_started_ = false;
  void (^write_complete_f_)(void);
  void (^flush_task_complete_f_)(void);

  size_t accumulated_bytes_ = 0;
};

}  // namespace santa

#endif
