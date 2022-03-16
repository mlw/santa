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

#import "Source/common/SNTLogging.h"

#import <os/log.h>

#import "Source/common/SNTConfigurator.h"

#ifdef DEBUG
static os_log_type_t logLevel = OS_LOG_TYPE_DEBUG;
#else
static os_log_type_t logLevel = OS_LOG_TYPE_INFO;  // default to info
#endif

void logMessage(os_log_type_t logType, FILE *destination, const char *format, ...) {
  static dispatch_once_t onceToken;
  static BOOL printToConsole = YES;

  dispatch_once(&onceToken, ^{
    if ([SNTConfigurator configurator].enableDebugLogging) {
      logLevel = LOG_LEVEL_DEBUG;
    }

    // If requested, redirect output to syslog.
    if ([[[NSProcessInfo processInfo] arguments] containsObject:@"--syslog"] ||
        [[[NSProcessInfo processInfo] processName] isEqualToString:@"com.google.santa.daemon"]) {
      printToConsole = YES;
    }
  });

  va_list args;
  va_start(args, format);
  NSString *s = [[NSString alloc] initWithFormat:@(format) arguments:args];
  va_end(args);

  if (printToConsole) {
    if (logLevel < level) return;

    fprintf(destination, "%s\n", [s UTF8String]);
  } else {
    // When logging via os_log, logLevel isn't checked as these can be filtered via usual
    // methods when accessing system wide logging methods.
    os_log_with_type(OS_LOG_DEFAULT, logType, "%s", [s UTF8String]);
  }
}
