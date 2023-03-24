/// Copyright 2023 Google LLC
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

#include <dispatch/dispatch.h>
#include <sys/types.h>

#include <any>
#include <functional>
#include <memory>
#include <string_view>

#ifndef SANTA__COMMON__PERIODICTIMER_H
#define SANTA__COMMON__PERIODICTIMER_H

namespace santa::common {

using PeriodicFunction = std::function<void(std::any)>;

struct TimerData {
  TimerData() = default;
  TimerData(TimerData &&other)
      : queue(std::move(other.queue)),
        source(std::move(other.source)),
        func(std::move(other.func)),
        context(std::move(other.context)) {
    other.queue = nullptr;
    other.source = nullptr;
  }

  TimerData &operator=(TimerData &&rhs) = delete;
  TimerData(const TimerData &other) = delete;
  void operator=(const TimerData &rhs) = delete;

  dispatch_queue_t queue = nullptr;
  dispatch_source_t source = nullptr;
  PeriodicFunction func;
  std::any context;
};

class PeriodicTimer {
 public:
  static PeriodicTimer Create(
      uint64_t interval_ms, uint64_t delay_ms, PeriodicFunction func,
      std::string_view lbl = "com.google.santa.daemon.timer");

  PeriodicTimer(uint64_t interval_ms, uint64_t delay_ms,
                std::shared_ptr<TimerData> timer_data);

  ~PeriodicTimer();

  // Allow moving timers
  PeriodicTimer(PeriodicTimer &&other) = default;
  PeriodicTimer &operator=(PeriodicTimer &&rhs) = default;

  // Timer isn't copyable
  PeriodicTimer(const PeriodicTimer &other) = delete;
  PeriodicTimer &operator=(const PeriodicTimer &rhs) = delete;

  static void TimerFire(void *ctx);

  void Start(std::any ctx);
  void Stop();

  void SetInterval(uint64_t interval_ms);
  void SetInterval(uint64_t interval_ms, uint64_t delay_ms);

  void RunSynchronouslyWithTimer(std::function<void()> func);

  inline uint64_t IntervalMS() { return interval_ms_; };
  inline bool IsRunning() { return periodic_timer_started_; }

 private:
  uint64_t interval_ms_;
  uint64_t delay_ms_;
  std::shared_ptr<TimerData> timer_data_;

  bool periodic_timer_started_ = false;
};

}  // namespace santa::common

#endif
