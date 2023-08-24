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

#include "Source/common/PeriodicTimer.h"

namespace santa::common {

PeriodicTimer PeriodicTimer::Create(uint64_t interval_ms, uint64_t delay_ms, PeriodicFunction func,
                                    std::string_view lbl) {
  dispatch_queue_t q = dispatch_queue_create(
    lbl.data(), dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL_WITH_AUTORELEASE_POOL,
                                                        QOS_CLASS_BACKGROUND, 0));

  dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);

  std::shared_ptr<TimerData> timer_data = std::make_shared<TimerData>();
  timer_data->queue = q;
  timer_data->source = source;
  timer_data->func = std::move(func);

  printf("PeriodicTimer Create: q: %p | s: %p\n", timer_data->queue, timer_data->source);

  dispatch_set_context(source, timer_data.get());
  dispatch_source_set_event_handler_f(source, PeriodicTimer::TimerFire);

  return PeriodicTimer(interval_ms, delay_ms, std::move(timer_data));
}

PeriodicTimer::PeriodicTimer(uint64_t interval_ms, uint64_t delay_ms,
                             std::shared_ptr<TimerData> timer_data)
    : interval_ms_(interval_ms), delay_ms_(delay_ms), timer_data_(std::move(timer_data)) {
  SetInterval(interval_ms_, delay_ms_);
}

PeriodicTimer::~PeriodicTimer() {
  printf("PeriodicTimer DTOR: started: %d | timer_data sp: %p\n", periodic_timer_started_,
         timer_data_.get());
  if (!periodic_timer_started_ && timer_data_ && timer_data_->source) {
    dispatch_source_cancel(timer_data_->source);
    dispatch_resume(timer_data_->source);
  }
}

void PeriodicTimer::TimerFire(void *ctx) {
  TimerData *timer_data = (TimerData *)ctx;
  printf("In TimerFuncWrapper\n");
  timer_data->func(timer_data->context);
}

void PeriodicTimer::Start(std::any ctx) {
  printf("PeriodicTimer Start: q: %p | s: %p\n", timer_data_->queue, timer_data_->source);
  dispatch_sync(timer_data_->queue, ^{
    if (periodic_timer_started_) {
      return;
    }

    timer_data_->context = ctx;

    dispatch_resume(timer_data_->source);

    periodic_timer_started_ = true;
  });
}

void PeriodicTimer::Stop() {
  dispatch_sync(timer_data_->queue, ^{
    if (!periodic_timer_started_) {
      return;
    }

    dispatch_suspend(timer_data_->source);

    periodic_timer_started_ = false;
  });
}

void PeriodicTimer::SetInterval(uint64_t interval_ms) {
  SetInterval(interval_ms, 0);
}

void PeriodicTimer::SetInterval(uint64_t interval_ms, uint64_t delay_ms) {

  dispatch_sync(timer_data_->queue, ^{
    printf("Setting interval...: %llu\n", interval_ms);
  interval_ms_ = interval_ms;
  dispatch_source_set_timer(timer_data_->source,
                            dispatch_time(DISPATCH_TIME_NOW, delay_ms * NSEC_PER_MSEC),
                            interval_ms * NSEC_PER_MSEC, 0);
  });
}

void PeriodicTimer::RunSynchronouslyWithTimer(std::function<void()> func) {
  dispatch_sync(timer_data_->queue, ^{
    func();
  });
}

}  // namespace santa::common
