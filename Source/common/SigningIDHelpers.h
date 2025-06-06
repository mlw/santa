/// Copyright 2024 Google LLC
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

#import <Foundation/Foundation.h>

@class MOLCodesignChecker;

__BEGIN_DECLS

/**
  Return a string representing normalized SigningID (prefixed with TeamID and a
  colon).

  @param csc A MOLCodesignChecker instance

  @return An NSString formated as teamID:signingID or nil if there isn't a valid signing ID.
*/
NSString *_Nullable FormatSigningID(MOLCodesignChecker *_Nullable csc);

__END_DECLS
