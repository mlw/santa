/// Copyright 2015 Google Inc. All rights reserved.
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

///
/// Logging definitions
///

#ifndef SANTA__COMMON__LOGGING_H
#define SANTA__COMMON__LOGGING_H

#import <os/base.h>
#import <os/log.h>

__BEGIN_DECLS

void logMessage(os_log_type_t logType, FILE *destination, const char *format, ...)
  __attribute__((format(os_log, 3, 4)));

#define LOG_WITH_TYPE(type, dest, fmt, ...) logMessage(OS_LOG_DEFAULT, dest, type, fmt, ##__VA_ARGS__)
#define LOGD(fmt, ...) LOG_WITH_TYPE(OS_LOG_TYPE_DEBUG, stdout, "D " fmt, ##__VA_ARGS__)
#define LOGI(fmt, ...) LOG_WITH_TYPE(OS_LOG_TYPE_INFO, stdout, "I " fmt, ##__VA_ARGS__)
#define LOGW(fmt, ...) LOG_WITH_TYPE(OS_LOG_TYPE_DEFAULT, stderr, "W " fmt, ##__VA_ARGS__)
#define LOGE(fmt, ...) LOG_WITH_TYPE(OS_LOG_TYPE_ERROR, stderr, "E " fmt, ##__VA_ARGS__)

__END_DECLS

#endif  // SANTA__COMMON__LOGGING_H
