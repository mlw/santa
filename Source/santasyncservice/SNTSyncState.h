/// Copyright 2015 Google Inc. All rights reserved.
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

#import <Foundation/Foundation.h>

#import "Source/common/SNTCommonEnums.h"
#import "Source/common/SNTExportConfiguration.h"

@class SNTSyncManager;
@class MOLXPCConnection;

/// An instance of this class is passed to each stage of the sync process for storing data
/// that might be needed in later stages.
@interface SNTSyncState : NSObject

/// Configured session to use for requests.
@property NSURLSession *session;

/// Connection to the daemon control interface.
@property MOLXPCConnection *daemonConn;

/// The base API URL.
@property NSURL *syncBaseURL;

/// An XSRF token to send in the headers with each request.
@property NSString *xsrfToken;

/// The header name to use when sending the XSRF token back to the server.
@property NSString *xsrfTokenHeader;

/// Full sync interval in seconds, defaults to kDefaultFullSyncInterval. If push notifications are
/// being used this interval will be ignored in favor of pushNotificationsFullSyncInterval.
@property NSUInteger fullSyncInterval;

/// An token to subscribe to push notifications.
@property(copy) NSString *pushNotificationsToken;

/// Full sync interval in seconds while listening for push notifications, defaults to
/// kDefaultPushNotificationsFullSyncInterval.
@property NSUInteger pushNotificationsFullSyncInterval;

/// Leeway time in seconds when receiving a global rule sync push notification, defaults to
/// kDefaultPushNotificationsGlobalRuleSyncDeadline.
@property NSUInteger pushNotificationsGlobalRuleSyncDeadline;

/// Machine identifier and owner.
@property(copy) NSString *machineID;
@property(copy) NSString *machineOwner;
@property(copy) NSArray<NSString *> *machineOwnerGroups;

/// Settings sent from server during preflight that are set during postflight.
@property SNTClientMode clientMode;
@property NSString *allowlistRegex;
@property NSString *blocklistRegex;
@property NSNumber *enableBundles;
@property NSNumber *enableTransitiveRules;
@property NSNumber *enableAllEventUpload;
@property NSNumber *disableUnknownEventUpload;
@property NSNumber *blockUSBMount;
// Array of mount args for the forced remounting feature.
@property NSArray *remountUSBMode;
@property NSString *overrideFileAccessAction;
@property SNTExportConfiguration *exportConfig;

/// Clean sync flag, if True, all existing rules should be deleted before inserting any new rules.
@property SNTSyncType syncType;

/// Batch size for uploading events.
@property NSUInteger eventBatchSize;

/// Array of bundle IDs to find binaries for.
@property NSArray *bundleBinaryRequests;

/// The content-encoding to use for the client uploads during the sync session.
@property SNTSyncContentEncoding contentEncoding;

/// Counts of rules received and processed during rule download.
@property NSUInteger rulesReceived;
@property NSUInteger rulesProcessed;

@property BOOL preflightOnly;
@property BOOL pushNotificationSync;

@end
