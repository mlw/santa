/// Copyright 2022 Google LLC
/// Copyright 2024 North Pole Security, Inc.
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

#include <CommonCrypto/CommonDigest.h>
#import <Foundation/Foundation.h>
#include <Kernel/kern/cs_blobs.h>
#import <XCTest/XCTest.h>
#include <dispatch/dispatch.h>
#include <sys/syslimits.h>
#include <unistd.h>

#include <algorithm>
#include <iostream>
#include <map>
#include <memory>
#include <optional>
#include <string_view>
#include <variant>
#include <vector>

#include "Source/common/TestUtils.h"
#import "Source/common/Unit.h"
#include "Source/santad/DataLayer/WatchItemPolicy.h"
#include "Source/santad/DataLayer/WatchItems.h"
#include "absl/container/flat_hash_set.h"

using santa::DataWatchItemPolicy;
using santa::kWatchItemPolicyDefaultAllowReadAccess;
using santa::kWatchItemPolicyDefaultAuditOnly;
using santa::kWatchItemPolicyDefaultPathType;
using santa::kWatchItemPolicyDefaultRuleType;
using santa::PathAndTypePair;
using santa::PathAndTypeVec;
using santa::PolicyProcessVec;
using santa::ProcessWatchItemPolicy;
using santa::Unit;
using santa::WatchItemPathType;
using santa::WatchItemProcess;
using santa::WatchItems;
using santa::WatchItemsState;

namespace santa {

extern bool ParseConfig(NSDictionary *config,
                        std::vector<std::shared_ptr<DataWatchItemPolicy>> &data_policies,
                        ProcessWatchItemPolicySet &proc_policies, NSError **err);
extern bool IsWatchItemNameValid(NSString *watch_item_name, NSError **err);
bool ParseConfigSingleWatchItem(NSString *name, std::string_view policy_version,
                                NSDictionary *watch_item,
                                std::vector<std::shared_ptr<DataWatchItemPolicy>> &data_policies,
                                ProcessWatchItemPolicySet &proc_policies, NSError **err);
extern std::variant<Unit, PathAndTypeVec> VerifyConfigWatchItemPaths(NSArray<id> *paths,
                                                                     NSError **err);
extern std::variant<Unit, PolicyProcessVec> VerifyConfigWatchItemProcesses(NSDictionary *watch_item,
                                                                           NSError **err);
extern std::optional<WatchItemRuleType> GetRuleType(NSString *rule_type);

class WatchItemsPeer : public WatchItems {
 public:
  using WatchItems::WatchItems;

  using WatchItems::ReloadConfig;
  using WatchItems::SetConfig;
  using WatchItems::SetConfigPath;

  using WatchItems::config_path_;
  using WatchItems::embedded_config_;
};

}  // namespace santa

using santa::GetRuleType;
using santa::IsWatchItemNameValid;
using santa::ParseConfig;
using santa::ParseConfigSingleWatchItem;
using santa::VerifyConfigWatchItemPaths;
using santa::VerifyConfigWatchItemProcesses;
using santa::WatchItemsPeer;

static constexpr std::string_view kBadPolicyName("__BAD_NAME__");
static constexpr std::string_view kBadPolicyPath("__BAD_PATH__");
static constexpr std::string_view kVersion("v0.1");

static std::shared_ptr<DataWatchItemPolicy> MakeBadPolicy() {
  return std::make_shared<DataWatchItemPolicy>(kBadPolicyName, kVersion, kBadPolicyPath);
}

static NSMutableDictionary *WrapWatchItemsConfig(NSDictionary *config) {
  return [@{@"Version" : @(kVersion.data()), @"WatchItems" : [config mutableCopy]} mutableCopy];
}

@interface WatchItemsTest : XCTestCase
@property NSFileManager *fileMgr;
@property NSString *testDir;
@property NSMutableArray *dirStack;
@property dispatch_queue_t q;
@end

@implementation WatchItemsTest

- (void)setUp {
  self.dirStack = [[NSMutableArray alloc] init];
  self.fileMgr = [NSFileManager defaultManager];
  self.testDir =
      [NSString stringWithFormat:@"%@santa-watchitems-%d", NSTemporaryDirectory(), getpid()];

  XCTAssertTrue([self.fileMgr createDirectoryAtPath:self.testDir
                        withIntermediateDirectories:YES
                                         attributes:nil
                                              error:nil]);

  self.q = dispatch_queue_create(NULL, DISPATCH_QUEUE_SERIAL);
  XCTAssertNotNil(self.q);
}

- (void)tearDown {
  XCTAssertTrue([self.fileMgr removeItemAtPath:self.testDir error:nil]);
}

- (void)pushd:(NSString *)path withRoot:(NSString *)root {
  NSString *dir = [NSString pathWithComponents:@[ root, path ]];
  NSString *origCwd = [self.fileMgr currentDirectoryPath];
  XCTAssertNotNil(origCwd);

  XCTAssertTrue([self.fileMgr changeCurrentDirectoryPath:dir]);
  [self.dirStack addObject:origCwd];
}

- (void)pushd:(NSString *)dir {
  [self pushd:dir withRoot:self.testDir];
}

- (void)popd {
  NSString *dir = [self.dirStack lastObject];
  XCTAssertTrue([self.fileMgr changeCurrentDirectoryPath:dir]);
  [self.dirStack removeLastObject];
}

- (void)createTestDirStructure:(NSArray *)fs rootedAt:(NSString *)root {
  NSString *origCwd = [self.fileMgr currentDirectoryPath];
  XCTAssertNotNil(origCwd);
  XCTAssertTrue([self.fileMgr changeCurrentDirectoryPath:root]);

  for (id item in fs) {
    if ([item isKindOfClass:[NSString class]]) {
      XCTAssertTrue([self.fileMgr createFileAtPath:item contents:nil attributes:nil]);
    } else if ([item isKindOfClass:[NSDictionary class]]) {
      for (id dir in item) {
        XCTAssertTrue([item[dir] isKindOfClass:[NSArray class]]);
        XCTAssertTrue([self.fileMgr createDirectoryAtPath:dir
                              withIntermediateDirectories:NO
                                               attributes:nil
                                                    error:nil]);

        [self createTestDirStructure:item[dir] rootedAt:dir];
      }
    } else {
      XCTFail("Unexpected dir structure item: %@: %@", item, [item class]);
    }
  }

  XCTAssertTrue([self.fileMgr changeCurrentDirectoryPath:origCwd]);
}

- (void)createTestDirStructure:(NSArray *)fs {
  [self createTestDirStructure:fs rootedAt:self.testDir];
}

- (void)testGetRuleType {
  std::optional<santa::WatchItemRuleType> ruleType;

  ruleType = GetRuleType(@"PathsWithAllowedProcesses");
  XCTAssertTrue(ruleType.has_value());
  XCTAssertEqual(ruleType.value(), santa::WatchItemRuleType::kPathsWithAllowedProcesses);

  ruleType = GetRuleType(@"PAthSWITHallowedProCesSES");
  XCTAssertTrue(ruleType.has_value());
  XCTAssertEqual(ruleType.value(), santa::WatchItemRuleType::kPathsWithAllowedProcesses);

  ruleType = GetRuleType(@"PathsWithDeniedProcesses");
  XCTAssertTrue(ruleType.has_value());
  XCTAssertEqual(ruleType.value(), santa::WatchItemRuleType::kPathsWithDeniedProcesses);

  ruleType = GetRuleType(@"paTHswIThdENieDProCEssES");
  XCTAssertTrue(ruleType.has_value());
  XCTAssertEqual(ruleType.value(), santa::WatchItemRuleType::kPathsWithDeniedProcesses);

  ruleType = GetRuleType(@"ProcessesWithDeniedPaths");
  XCTAssertTrue(ruleType.has_value());
  XCTAssertEqual(ruleType.value(), santa::WatchItemRuleType::kProcessesWithDeniedPaths);

  ruleType = GetRuleType(@"ProCEssESwIThdENieDpaTHs");
  XCTAssertTrue(ruleType.has_value());
  XCTAssertEqual(ruleType.value(), santa::WatchItemRuleType::kProcessesWithDeniedPaths);

  ruleType = GetRuleType(@"ProcessesWithAllowedPaths");
  XCTAssertTrue(ruleType.has_value());
  XCTAssertEqual(ruleType.value(), santa::WatchItemRuleType::kProcessesWithAllowedPaths);

  ruleType = GetRuleType(@"ProCEssESwIThaLLowEDpaTHs");
  XCTAssertTrue(ruleType.has_value());
  XCTAssertEqual(ruleType.value(), santa::WatchItemRuleType::kProcessesWithAllowedPaths);

  ruleType = GetRuleType(@"NotARealRuleType");
  XCTAssertFalse(ruleType.has_value());
}

- (void)testReloadScenarios {
  [self createTestDirStructure:@[
    @{
      @"a" : @[ @"f1", @"f2" ],
    },
    @{
      @"b" : @[ @"f1" ],
    },
  ]];

  NSDictionary *allFilesPolicy = @{kWatchItemConfigKeyPaths : @[ @"*" ]};
  NSDictionary *configAllFilesOriginal =
      WrapWatchItemsConfig(@{@"all_files_orig" : allFilesPolicy});
  NSDictionary *configAllFilesRename =
      WrapWatchItemsConfig(@{@"all_files_rename" : allFilesPolicy});

  WatchItems::VersionAndPolicies policies;

  std::vector<std::string_view> f1Path = {"f1"};
  std::vector<std::string_view> f2Path = {"f2"};

  // Changes in config dictionary will update policy info even if the
  // filesystem didn't change.
  {
    WatchItemsPeer watchItems((NSString *)nil, NULL, NULL);
    [self pushd:@"a"];
    watchItems.ReloadConfig(configAllFilesOriginal);

    policies = watchItems.FindPolciesForPaths(f1Path);
    XCTAssertCStringEqual(policies.second[0].value_or(MakeBadPolicy())->name.c_str(),
                          "all_files_orig");

    watchItems.ReloadConfig(configAllFilesRename);
    policies = watchItems.FindPolciesForPaths(f1Path);
    XCTAssertCStringEqual(policies.second[0].value_or(MakeBadPolicy())->name.c_str(),
                          "all_files_rename");

    policies = watchItems.FindPolciesForPaths(f1Path);
    XCTAssertCStringEqual(policies.second[0].value_or(MakeBadPolicy())->name.c_str(),
                          "all_files_rename");
    [self popd];
  }

  // Changes to fileystem structure are reflected when a config is reloaded
  {
    WatchItemsPeer watchItems((NSString *)nil, NULL, NULL);
    [self pushd:@"a"];
    watchItems.ReloadConfig(configAllFilesOriginal);
    [self popd];

    policies = watchItems.FindPolciesForPaths(f2Path);
    XCTAssertCStringEqual(policies.second[0].value_or(MakeBadPolicy())->name.c_str(),
                          "all_files_orig");

    [self pushd:@"b"];
    watchItems.ReloadConfig(configAllFilesOriginal);
    [self popd];

    policies = watchItems.FindPolciesForPaths(f2Path);
    XCTAssertFalse(policies.second[0].has_value());
  }
}

- (void)testPeriodicTask {
  // Ensure watch item policy memory is properly handled
  [self createTestDirStructure:@[ @"f1", @"f2", @"weird1" ]];

  NSDictionary *fFiles = @{
    kWatchItemConfigKeyPaths : @[ @{
      kWatchItemConfigKeyPathsPath : @"f?",
      kWatchItemConfigKeyPathsIsPrefix : @(NO),
    } ]
  };
  NSDictionary *weirdFiles = @{
    kWatchItemConfigKeyPaths : @[ @{
      kWatchItemConfigKeyPathsPath : @"weird?",
      kWatchItemConfigKeyPathsIsPrefix : @(NO),
    } ]
  };

  NSString *configFile = @"config.plist";
  NSDictionary *firstConfig = WrapWatchItemsConfig(@{@"f_files" : fFiles});
  NSDictionary *secondConfig =
      WrapWatchItemsConfig(@{@"f_files" : fFiles, @"weird_files" : weirdFiles});

  dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.q);

  const uint64 periodicFlushMS = 1000;
  dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0),
                            NSEC_PER_MSEC * periodicFlushMS, 0);

  dispatch_semaphore_t sema = dispatch_semaphore_create(0);
  auto watchItems = std::make_shared<WatchItemsPeer>(configFile, self.q, timer, ^{
    dispatch_semaphore_signal(sema);
  });

  // Move into the base test directory and write the config to disk
  [self pushd:@""];
  XCTAssertTrue([firstConfig writeToFile:configFile atomically:YES]);

  std::vector<std::string_view> f1Path = {"f1"};
  std::vector<std::string_view> weird1Path = {"weird1"};

  // Ensure no policy has been loaded yet
  XCTAssertFalse(watchItems->FindPolciesForPaths(f1Path).second[0].has_value());
  XCTAssertFalse(watchItems->FindPolciesForPaths(weird1Path).second[0].has_value());

  // Begin the periodic task
  watchItems->BeginPeriodicTask();

  // The first run of the task starts immediately
  // Wait for the first iteration and check for the expected policy
  XCTAssertSemaTrue(sema, 5, "Periodic task did not complete within expected window");
  XCTAssertTrue(watchItems->FindPolciesForPaths(f1Path).second[0].has_value());
  XCTAssertFalse(watchItems->FindPolciesForPaths(weird1Path).second[0].has_value());

  // Write the config update
  XCTAssertTrue([secondConfig writeToFile:configFile atomically:YES]);

  // Wait for the new config to be loaded and check for the new expected policies
  XCTAssertSemaTrue(sema, 5, "Periodic task did not complete within expected window");
  XCTAssertTrue(watchItems->FindPolciesForPaths(f1Path).second[0].has_value());
  XCTAssertTrue(watchItems->FindPolciesForPaths(weird1Path).second[0].has_value());

  [self popd];
}

- (void)testPolicyLookup {
  // Test multiple, more comprehensive policies before/after config reload
  [self createTestDirStructure:@[
    @{
      @"foo" : @[ @"bar.txt", @"bar.txt.tmp" ],
      @"baz" : @[ @{@"qaz" : @[]} ],
    },
    @"f1",
  ]];

  NSMutableDictionary *config = WrapWatchItemsConfig(@{
    @"foo_subdir" : @{
      kWatchItemConfigKeyPaths : @[ @{
        kWatchItemConfigKeyPathsPath : @"./foo",
        kWatchItemConfigKeyPathsIsPrefix : @(YES),
      } ]
    }
  });

  WatchItemsPeer watchItems((NSString *)nil, NULL, NULL);
  WatchItems::VersionAndPolicies policies;

  // Resultant vector is same size as input vector
  // Initially nothing should be in the map
  std::vector<std::string_view> paths = {};
  XCTAssertEqual(watchItems.FindPolciesForPaths(paths).second.size(), 0);
  paths.push_back("./foo");
  XCTAssertEqual(watchItems.FindPolciesForPaths(paths).second.size(), 1);
  XCTAssertFalse(watchItems.FindPolciesForPaths(paths).second[0].has_value());
  paths.push_back("./baz");
  XCTAssertEqual(watchItems.FindPolciesForPaths(paths).second.size(), 2);

  // Load the initial config
  [self pushd:@""];
  watchItems.ReloadConfig(config);
  [self popd];

  {
    // Test expected values with the inital policy
    const std::map<std::vector<std::string_view>, std::string_view> pathToPolicyName = {
        {{"./foo"}, "foo_subdir"},
        {{"./foo/bar.txt.tmp"}, "foo_subdir"},
        {{"./foo/bar.txt"}, "foo_subdir"},
        {{"./does/not/exist"}, kBadPolicyName},
    };

    for (const auto &kv : pathToPolicyName) {
      policies = watchItems.FindPolciesForPaths(kv.first);
      XCTAssertCStringEqual(policies.first.data(), kVersion.data());
      XCTAssertCStringEqual(policies.second[0].value_or(MakeBadPolicy())->name.c_str(),
                            kv.second.data());
    }

    // Test multiple lookup
    policies = watchItems.FindPolciesForPaths({"./foo", "./does/not/exist"});
    XCTAssertCStringEqual(policies.second[0].value_or(MakeBadPolicy())->name.c_str(), "foo_subdir");
    XCTAssertFalse(policies.second[1].has_value());
  }

  // Add a new policy and reload the config
  NSDictionary *barTxtFilePolicy = @{
    kWatchItemConfigKeyPaths : @[ @{
      kWatchItemConfigKeyPathsPath : @"./foo/bar.txt",
      kWatchItemConfigKeyPathsIsPrefix : @(NO),
    } ]
  };
  [config[@"WatchItems"] setObject:barTxtFilePolicy forKey:@"bar_txt"];

  // Load the updated config
  [self pushd:@""];
  watchItems.ReloadConfig(config);
  [self popd];

  {
    // Test expected values with the updated policy
    const std::map<std::vector<std::string_view>, std::string_view> pathToPolicyName = {
        {{"./foo"}, "foo_subdir"},
        {{"./foo/bar.txt.tmp"}, "foo_subdir"},
        {{"./foo/bar.txt"}, "bar_txt"},
        {{"./does/not/exist"}, kBadPolicyName},
    };

    for (const auto &kv : pathToPolicyName) {
      policies = watchItems.FindPolciesForPaths(kv.first);
      XCTAssertCStringEqual(policies.second[0].value_or(MakeBadPolicy())->name.c_str(),
                            kv.second.data());
    }
  }

  // Add a catch-all policy that should only affect the previously non-matching path
  NSDictionary *catchAllFilePolicy = @{
    kWatchItemConfigKeyPaths : @[ @{
      kWatchItemConfigKeyPathsPath : @".",
      kWatchItemConfigKeyPathsIsPrefix : @(YES),
    } ]
  };
  [config[@"WatchItems"] setObject:catchAllFilePolicy forKey:@"dot_everything"];

  // Load the updated config
  [self pushd:@""];
  watchItems.ReloadConfig(config);
  [self popd];

  {
    // Test expected values with the catch-all policy
    const std::map<std::vector<std::string_view>, std::string_view> pathToPolicyName = {
        {{"./foo"}, "foo_subdir"},
        {{"./foo/bar.txt.tmp"}, "foo_subdir"},
        {{"./foo/bar.txt"}, "bar_txt"},
        {{"./does/not/exist"}, "dot_everything"},
    };

    for (const auto &kv : pathToPolicyName) {
      policies = watchItems.FindPolciesForPaths(kv.first);
      XCTAssertCStringEqual(policies.second[0].value_or(MakeBadPolicy())->name.c_str(),
                            kv.second.data());
    }
  }

  // Now remove the foo_subdir rule, previous matches should fallback to the catch-all
  [config[@"WatchItems"] removeObjectForKey:@"foo_subdir"];
  [self pushd:@""];
  watchItems.ReloadConfig(config);
  [self popd];

  {
    // Test expected values with the foo_subdir policy removed
    const std::map<std::vector<std::string_view>, std::string_view> pathToPolicyName = {
        {{"./foo"}, "dot_everything"},
        {{"./foo/bar.txt.tmp"}, "dot_everything"},
        {{"./foo/bar.txt"}, "bar_txt"},
        {{"./does/not/exist"}, "dot_everything"},
    };

    for (const auto &kv : pathToPolicyName) {
      policies = watchItems.FindPolciesForPaths(kv.first);
      XCTAssertCStringEqual(policies.second[0].value_or(MakeBadPolicy())->name.c_str(),
                            kv.second.data());
    }
  }
}

- (void)testVerifyConfigWatchItemPaths {
  std::variant<Unit, PathAndTypeVec> path_list;
  NSError *err;

  // Test no paths specified
  path_list = VerifyConfigWatchItemPaths(@[], &err);
  XCTAssertTrue(std::holds_alternative<Unit>(path_list));

  // Test invalid types in paths array
  path_list = VerifyConfigWatchItemPaths(@[ @(0) ], &err);
  XCTAssertTrue(std::holds_alternative<Unit>(path_list));

  // Test path array with long string
  path_list = VerifyConfigWatchItemPaths(@[ RepeatedString(@"A", PATH_MAX + 1) ], &err);
  XCTAssertTrue(std::holds_alternative<Unit>(path_list));

  // Test path array dictionary with missing required key
  path_list = VerifyConfigWatchItemPaths(@[ @{@"FakePath" : @"A"} ], &err);
  XCTAssertTrue(std::holds_alternative<Unit>(path_list));

  // Test path array dictionary with long string
  path_list = VerifyConfigWatchItemPaths(
      @[ @{kWatchItemConfigKeyPathsPath : RepeatedString(@"A", PATH_MAX + 1)} ], &err);
  XCTAssertTrue(std::holds_alternative<Unit>(path_list));

  // Test path array dictionary with default path type
  path_list = VerifyConfigWatchItemPaths(@[ @{kWatchItemConfigKeyPathsPath : @"A"} ], &err);
  XCTAssertTrue(std::holds_alternative<PathAndTypeVec>(path_list));
  XCTAssertEqual(std::get<PathAndTypeVec>(path_list).size(), 1);
  XCTAssertCStringEqual(std::get<PathAndTypeVec>(path_list)[0].first.c_str(), "A");
  XCTAssertEqual(std::get<PathAndTypeVec>(path_list)[0].second, kWatchItemPolicyDefaultPathType);

  // Test path array dictionary with custom path type
  path_list = VerifyConfigWatchItemPaths(
      @[ @{kWatchItemConfigKeyPathsPath : @"A", kWatchItemConfigKeyPathsIsPrefix : @(YES)} ], &err);
  XCTAssertTrue(std::holds_alternative<PathAndTypeVec>(path_list));
  XCTAssertEqual(std::get<PathAndTypeVec>(path_list).size(), 1);
  XCTAssertCStringEqual(std::get<PathAndTypeVec>(path_list)[0].first.c_str(), "A");
  XCTAssertEqual(std::get<PathAndTypeVec>(path_list)[0].second, WatchItemPathType::kPrefix);
}

- (void)testVerifyConfigWatchItemProcesses {
  std::variant<Unit, PolicyProcessVec> proc_list;
  NSError *err;

  // Non-existent process list parses successfully, but has no items
  proc_list = VerifyConfigWatchItemProcesses(@{}, &err);
  XCTAssertTrue(std::holds_alternative<PolicyProcessVec>(proc_list));
  XCTAssertEqual(std::get<PolicyProcessVec>(proc_list).size(), 0);

  // Process list fails to parse if contains non-array type
  proc_list = VerifyConfigWatchItemProcesses(@{kWatchItemConfigKeyProcesses : @""}, &err);
  XCTAssertTrue(std::holds_alternative<Unit>(proc_list));
  proc_list = VerifyConfigWatchItemProcesses(@{kWatchItemConfigKeyProcesses : @(0)}, &err);
  XCTAssertTrue(std::holds_alternative<Unit>(proc_list));
  proc_list = VerifyConfigWatchItemProcesses(@{kWatchItemConfigKeyProcesses : @{}}, &err);
  XCTAssertTrue(std::holds_alternative<Unit>(proc_list));
  proc_list = VerifyConfigWatchItemProcesses(@{kWatchItemConfigKeyProcesses : @[]}, &err);
  XCTAssertTrue(std::holds_alternative<PolicyProcessVec>(proc_list));

  // Test a process dictionary with no valid attributes set
  proc_list = VerifyConfigWatchItemProcesses(@{kWatchItemConfigKeyProcesses : @[ @{} ]}, &err);
  XCTAssertTrue(std::holds_alternative<Unit>(proc_list));

  // Test BinaryPath length limits
  proc_list = VerifyConfigWatchItemProcesses(@{
    kWatchItemConfigKeyProcesses :
        @[ @{kWatchItemConfigKeyProcessesBinaryPath : RepeatedString(@"A", PATH_MAX + 1)} ]
  },
                                             &err);
  XCTAssertTrue(std::holds_alternative<Unit>(proc_list));

  // Test valid BinaryPath
  proc_list = VerifyConfigWatchItemProcesses(
      @{kWatchItemConfigKeyProcesses : @[ @{kWatchItemConfigKeyProcessesBinaryPath : @"mypath"} ]},
      &err);
  XCTAssertTrue(std::holds_alternative<PolicyProcessVec>(proc_list));
  XCTAssertEqual(std::get<PolicyProcessVec>(proc_list).size(), 1);
  XCTAssertEqual(std::get<PolicyProcessVec>(proc_list)[0],
                 WatchItemProcess("mypath", "", "", {}, "", std::nullopt));

  // Test SigningID length limits
  proc_list = VerifyConfigWatchItemProcesses(@{
    kWatchItemConfigKeyProcesses :
        @[ @{kWatchItemConfigKeyProcessesSigningID : RepeatedString(@"A", 513)} ]
  },
                                             &err);
  XCTAssertTrue(std::holds_alternative<Unit>(proc_list));

  // Test valid SigningID
  proc_list = VerifyConfigWatchItemProcesses(@{
    kWatchItemConfigKeyProcesses :
        @[ @{kWatchItemConfigKeyProcessesSigningID : @"com.northpolesec.test"} ]
  },
                                             &err);
  XCTAssertTrue(std::holds_alternative<PolicyProcessVec>(proc_list));
  XCTAssertEqual(std::get<PolicyProcessVec>(proc_list).size(), 1);
  XCTAssertEqual(std::get<PolicyProcessVec>(proc_list)[0],
                 WatchItemProcess("", "com.northpolesec.test", "", {}, "", std::nullopt));

  // Test TeamID length limits
  proc_list = VerifyConfigWatchItemProcesses(@{
    kWatchItemConfigKeyProcesses :
        @[ @{kWatchItemConfigKeyProcessesTeamID : @"LongerThanExpectedTeamID"} ]
  },
                                             &err);
  XCTAssertTrue(std::holds_alternative<Unit>(proc_list));

  // Test valid TeamID
  proc_list = VerifyConfigWatchItemProcesses(
      @{kWatchItemConfigKeyProcesses : @[ @{kWatchItemConfigKeyProcessesTeamID : @"myvalidtid"} ]},
      &err);
  XCTAssertTrue(std::holds_alternative<PolicyProcessVec>(proc_list));
  XCTAssertEqual(std::get<PolicyProcessVec>(proc_list).size(), 1);
  XCTAssertEqual(std::get<PolicyProcessVec>(proc_list)[0],
                 WatchItemProcess("", "", "myvalidtid", {}, "", std::nullopt));

  // Test CDHash length limits
  proc_list = VerifyConfigWatchItemProcesses(@{
    kWatchItemConfigKeyProcesses :
        @[ @{kWatchItemConfigKeyProcessesCDHash : RepeatedString(@"A", CS_CDHASH_LEN * 2 + 1)} ]
  },
                                             &err);
  XCTAssertTrue(std::holds_alternative<Unit>(proc_list));

  // Test CDHash hex-only
  proc_list = VerifyConfigWatchItemProcesses(@{
    kWatchItemConfigKeyProcesses :
        @[ @{kWatchItemConfigKeyProcessesCDHash : RepeatedString(@"Z", CS_CDHASH_LEN * 2)} ]
  },
                                             &err);
  XCTAssertTrue(std::holds_alternative<Unit>(proc_list));

  // Test valid CDHash
  NSString *cdhash = RepeatedString(@"A", CS_CDHASH_LEN * 2);
  std::vector<uint8_t> cdhashBytes(cdhash.length / 2);
  std::fill(cdhashBytes.begin(), cdhashBytes.end(), 0xAA);
  proc_list = VerifyConfigWatchItemProcesses(
      @{kWatchItemConfigKeyProcesses : @[ @{kWatchItemConfigKeyProcessesCDHash : cdhash} ]}, &err);
  XCTAssertTrue(std::holds_alternative<PolicyProcessVec>(proc_list));
  XCTAssertEqual(std::get<PolicyProcessVec>(proc_list).size(), 1);
  XCTAssertEqual(std::get<PolicyProcessVec>(proc_list)[0],
                 WatchItemProcess("", "", "", cdhashBytes, "", std::nullopt));

  // Test Cert Hash length limits
  proc_list = VerifyConfigWatchItemProcesses(@{
    kWatchItemConfigKeyProcesses : @[ @{
      kWatchItemConfigKeyProcessesCertificateSha256 :
          RepeatedString(@"A", CC_SHA256_DIGEST_LENGTH * 2 + 1)
    } ]
  },
                                             &err);
  XCTAssertTrue(std::holds_alternative<Unit>(proc_list));

  // Test Cert Hash hex-only
  proc_list = VerifyConfigWatchItemProcesses(@{
    kWatchItemConfigKeyProcesses : @[ @{
      kWatchItemConfigKeyProcessesCertificateSha256 :
          RepeatedString(@"Z", CC_SHA256_DIGEST_LENGTH * 2)
    } ]
  },
                                             &err);
  XCTAssertTrue(std::holds_alternative<Unit>(proc_list));

  // Test valid Cert Hash
  NSString *certHash = RepeatedString(@"A", CC_SHA256_DIGEST_LENGTH * 2);
  proc_list = VerifyConfigWatchItemProcesses(@{
    kWatchItemConfigKeyProcesses : @[ @{kWatchItemConfigKeyProcessesCertificateSha256 : certHash} ]
  },
                                             &err);
  XCTAssertTrue(std::holds_alternative<PolicyProcessVec>(proc_list));
  XCTAssertEqual(std::get<PolicyProcessVec>(proc_list).size(), 1);
  XCTAssertEqual(std::get<PolicyProcessVec>(proc_list)[0],
                 WatchItemProcess("", "", "", {}, [certHash UTF8String], std::nullopt));

  // Test valid invalid PlatformBinary type
  proc_list = VerifyConfigWatchItemProcesses(
      @{kWatchItemConfigKeyProcesses : @[ @{kWatchItemConfigKeyProcessesPlatformBinary : @"YES"} ]},
      &err);
  XCTAssertTrue(std::holds_alternative<Unit>(proc_list));

  // Test valid valid PlatformBinary
  proc_list = VerifyConfigWatchItemProcesses(
      @{kWatchItemConfigKeyProcesses : @[ @{kWatchItemConfigKeyProcessesPlatformBinary : @(YES)} ]},
      &err);
  XCTAssertTrue(std::holds_alternative<PolicyProcessVec>(proc_list));
  XCTAssertEqual(std::get<PolicyProcessVec>(proc_list).size(), 1);
  XCTAssertEqual(std::get<PolicyProcessVec>(proc_list)[0],
                 WatchItemProcess("", "", "", {}, "", std::make_optional(true)));

  // Test valid multiple attributes, multiple procs
  proc_list = VerifyConfigWatchItemProcesses(@{
    kWatchItemConfigKeyProcesses : @[
      @{
        kWatchItemConfigKeyProcessesBinaryPath : @"mypath1",
        kWatchItemConfigKeyProcessesSigningID : @"com.northpolesec.test1",
        kWatchItemConfigKeyProcessesTeamID : @"validtid_1",
        kWatchItemConfigKeyProcessesCDHash : cdhash,
        kWatchItemConfigKeyProcessesCertificateSha256 : certHash,
        kWatchItemConfigKeyProcessesPlatformBinary : @(YES),
      },
      @{
        kWatchItemConfigKeyProcessesBinaryPath : @"mypath2",
        kWatchItemConfigKeyProcessesSigningID : @"com.northpolesec.test2",
        kWatchItemConfigKeyProcessesTeamID : @"validtid_2",
        kWatchItemConfigKeyProcessesCDHash : cdhash,
        kWatchItemConfigKeyProcessesCertificateSha256 : certHash,
        kWatchItemConfigKeyProcessesPlatformBinary : @(NO),
      },
    ]
  },
                                             &err);
  XCTAssertTrue(std::holds_alternative<PolicyProcessVec>(proc_list));
  XCTAssertEqual(std::get<PolicyProcessVec>(proc_list).size(), 2);
  XCTAssertEqual(std::get<PolicyProcessVec>(proc_list)[0],
                 WatchItemProcess("mypath1", "com.northpolesec.test1", "validtid_1", cdhashBytes,
                                  [certHash UTF8String], std::make_optional(true)));
  XCTAssertEqual(std::get<PolicyProcessVec>(proc_list)[1],
                 WatchItemProcess("mypath2", "com.northpolesec.test2", "validtid_2", cdhashBytes,
                                  [certHash UTF8String], std::make_optional(false)));
}

- (void)testIsWatchItemNameValid {
  // Only legal C identifiers should be accepted
  XCTAssertFalse(IsWatchItemNameValid(nil, nil));
  XCTAssertFalse(IsWatchItemNameValid(@"", nil));
  XCTAssertFalse(IsWatchItemNameValid(@"1abc", nil));
  XCTAssertFalse(IsWatchItemNameValid(@"abc-1234", nil));
  XCTAssertFalse(IsWatchItemNameValid(@"a=b", nil));
  XCTAssertFalse(IsWatchItemNameValid(@"a!b", nil));

  XCTAssertTrue(IsWatchItemNameValid(@"_", nil));
  XCTAssertTrue(IsWatchItemNameValid(@"_1", nil));
  XCTAssertTrue(IsWatchItemNameValid(@"_1_", nil));
  XCTAssertTrue(IsWatchItemNameValid(@"abc", nil));
  XCTAssertTrue(IsWatchItemNameValid(@"A", nil));
  XCTAssertTrue(IsWatchItemNameValid(@"A_B", nil));
  XCTAssertTrue(IsWatchItemNameValid(@"FooName", nil));
  XCTAssertTrue(IsWatchItemNameValid(@"bar_Name", nil));
}

- (void)testParseConfig {
  NSError *err;
  std::vector<std::shared_ptr<DataWatchItemPolicy>> data_policies;
  santa::ProcessWatchItemPolicySet proc_policies;

  // Ensure top level keys must exist and be correct types
  XCTAssertFalse(ParseConfig(@{}, data_policies, proc_policies, &err));
  XCTAssertFalse(
      ParseConfig(@{kWatchItemConfigKeyVersion : @(0)}, data_policies, proc_policies, &err));
  XCTAssertFalse(
      ParseConfig(@{kWatchItemConfigKeyVersion : @{}}, data_policies, proc_policies, &err));
  XCTAssertFalse(
      ParseConfig(@{kWatchItemConfigKeyVersion : @[]}, data_policies, proc_policies, &err));
  XCTAssertFalse(
      ParseConfig(@{kWatchItemConfigKeyVersion : @""}, data_policies, proc_policies, &err));
  XCTAssertFalse(
      ParseConfig(@{kWatchItemConfigKeyVersion : @"1", kWatchItemConfigKeyWatchItems : @""},
                  data_policies, proc_policies, &err));
  XCTAssertFalse(
      ParseConfig(@{kWatchItemConfigKeyVersion : @"1", kWatchItemConfigKeyWatchItems : @[]},
                  data_policies, proc_policies, &err));
  XCTAssertFalse(
      ParseConfig(@{kWatchItemConfigKeyVersion : @"1", kWatchItemConfigKeyWatchItems : @(0)},
                  data_policies, proc_policies, &err));

  // Minimally successful configs without watch items
  XCTAssertTrue(
      ParseConfig(@{kWatchItemConfigKeyVersion : @"1"}, data_policies, proc_policies, &err));
  XCTAssertTrue(
      ParseConfig(@{kWatchItemConfigKeyVersion : @"1", kWatchItemConfigKeyWatchItems : @{}},
                  data_policies, proc_policies, &err));

  // Ensure constraints on watch items entries match expectations
  XCTAssertFalse(ParseConfig(
      @{kWatchItemConfigKeyVersion : @"1", kWatchItemConfigKeyWatchItems : @{@(0) : @(0)}},
      data_policies, proc_policies, &err));
  XCTAssertFalse(ParseConfig(
      @{kWatchItemConfigKeyVersion : @"1", kWatchItemConfigKeyWatchItems : @{@"" : @{}}},
      data_policies, proc_policies, &err));
  XCTAssertFalse(ParseConfig(
      @{kWatchItemConfigKeyVersion : @"1", kWatchItemConfigKeyWatchItems : @{@"a" : @[]}},
      data_policies, proc_policies, &err));
  XCTAssertFalse(ParseConfig(
      @{kWatchItemConfigKeyVersion : @"1", kWatchItemConfigKeyWatchItems : @{@"a" : @{}}},
      data_policies, proc_policies, &err));

  // Minimally successful config with watch item
  XCTAssertTrue(ParseConfig(@{
    kWatchItemConfigKeyVersion : @"1",
    kWatchItemConfigKeyWatchItems : @{@"a" : @{kWatchItemConfigKeyPaths : @[ @"asdf" ]}}
  },
                            data_policies, proc_policies, &err));
}

- (void)testParseConfigSingleWatchItemGeneral {
  std::vector<std::shared_ptr<DataWatchItemPolicy>> data_policies;
  santa::ProcessWatchItemPolicySet proc_policies;
  NSError *err;

  // There must be valid Paths in a watch item
  XCTAssertFalse(ParseConfigSingleWatchItem(@"", "", @{}, data_policies, proc_policies, &err));
  XCTAssertFalse(ParseConfigSingleWatchItem(@"", "", @{kWatchItemConfigKeyPaths : @[ @"" ]},
                                            data_policies, proc_policies, &err));
  XCTAssertTrue(ParseConfigSingleWatchItem(@"", "", @{kWatchItemConfigKeyPaths : @[ @"a" ]},
                                           data_policies, proc_policies, &err));

  // Empty options are fine
  XCTAssertTrue(ParseConfigSingleWatchItem(
      @"", "", @{kWatchItemConfigKeyPaths : @[ @"a" ], kWatchItemConfigKeyOptions : @{}},
      data_policies, proc_policies, &err));

  // If an Options key exist, it must be a dictionary type
  XCTAssertFalse(ParseConfigSingleWatchItem(
      @"", "", @{kWatchItemConfigKeyPaths : @[ @"a" ], kWatchItemConfigKeyOptions : @[]},
      data_policies, proc_policies, &err));
  XCTAssertFalse(ParseConfigSingleWatchItem(
      @"", "", @{kWatchItemConfigKeyPaths : @[ @"a" ], kWatchItemConfigKeyOptions : @""},
      data_policies, proc_policies, &err));
  XCTAssertFalse(ParseConfigSingleWatchItem(
      @"", "", @{kWatchItemConfigKeyPaths : @[ @"a" ], kWatchItemConfigKeyOptions : @(0)},
      data_policies, proc_policies, &err));

  // Options keys must be valid types
  {
    // Check bool option keys
    for (NSString *key in @[
           kWatchItemConfigKeyOptionsAllowReadAccess,
           kWatchItemConfigKeyOptionsAuditOnly,
           kWatchItemConfigKeyOptionsInvertProcessExceptions,
           kWatchItemConfigKeyOptionsEnableSilentMode,
           kWatchItemConfigKeyOptionsEnableSilentTTYMode,
         ]) {
      // Parse bool option with invliad type
      XCTAssertFalse(ParseConfigSingleWatchItem(
          @"", "",
          @{kWatchItemConfigKeyPaths : @[ @"a" ],
            kWatchItemConfigKeyOptions : @{key : @""}},
          data_policies, proc_policies, &err));

      // Parse bool option with valid type
      XCTAssertTrue(ParseConfigSingleWatchItem(
          @"", "",
          @{kWatchItemConfigKeyPaths : @[ @"a" ],
            kWatchItemConfigKeyOptions : @{key : @(0)}},
          data_policies, proc_policies, &err));
    }

    // Check other option keys

    // kWatchItemConfigKeyOptionsRuleType - Invalid type
    XCTAssertFalse(ParseConfigSingleWatchItem(
        @"", "", @{
          kWatchItemConfigKeyPaths : @[ @"a" ],
          kWatchItemConfigKeyOptions : @{kWatchItemConfigKeyOptionsRuleType : @[]}
        },
        data_policies, proc_policies, &err));

    // kWatchItemConfigKeyOptionsRuleType - Invalid RuleType value
    XCTAssertFalse(ParseConfigSingleWatchItem(
        @"", "", @{
          kWatchItemConfigKeyPaths : @[ @"a" ],
          kWatchItemConfigKeyOptions : @{kWatchItemConfigKeyOptionsRuleType : @"InvalidValue"}
        },
        data_policies, proc_policies, &err));

    // kWatchItemConfigKeyOptionsRuleType - Override
    // kWatchItemConfigKeyOptionsInvertProcessExceptions
    data_policies.clear();
    XCTAssertTrue(ParseConfigSingleWatchItem(
        @"", "", @{
          kWatchItemConfigKeyPaths : @[ @"a" ],
          kWatchItemConfigKeyOptions : @{
            kWatchItemConfigKeyOptionsRuleType : @"PathsWithAllowedProcesses",
            kWatchItemConfigKeyOptionsInvertProcessExceptions : @(YES)
          }
        },
        data_policies, proc_policies, &err));
    XCTAssertEqual(data_policies.size(), 1);
    XCTAssertEqual(data_policies[0].get()->rule_type,
                   santa::WatchItemRuleType::kPathsWithAllowedProcesses);

    // kWatchItemConfigKeyOptionsRuleType - kWatchItemConfigKeyOptionsInvertProcessExceptions used
    // as fallback
    data_policies.clear();
    XCTAssertTrue(ParseConfigSingleWatchItem(
        @"", "", @{
          kWatchItemConfigKeyPaths : @[ @"a" ],
          kWatchItemConfigKeyOptions : @{kWatchItemConfigKeyOptionsInvertProcessExceptions : @(YES)}
        },
        data_policies, proc_policies, &err));
    XCTAssertEqual(data_policies.size(), 1);
    XCTAssertEqual(data_policies[0].get()->rule_type,
                   santa::WatchItemRuleType::kPathsWithDeniedProcesses);

    // kWatchItemConfigKeyOptionsCustomMessage - Invalid type
    XCTAssertFalse(ParseConfigSingleWatchItem(
        @"", "", @{
          kWatchItemConfigKeyPaths : @[ @"a" ],
          kWatchItemConfigKeyOptions : @{kWatchItemConfigKeyOptionsCustomMessage : @[]}
        },
        data_policies, proc_policies, &err));

    // kWatchItemConfigKeyOptionsCustomMessage zero length
    XCTAssertTrue(ParseConfigSingleWatchItem(
        @"", "", @{
          kWatchItemConfigKeyPaths : @[ @"a" ],
          kWatchItemConfigKeyOptions : @{kWatchItemConfigKeyOptionsCustomMessage : @""}
        },
        data_policies, proc_policies, &err));

    // kWatchItemConfigKeyOptionsCustomMessage valid "normal" length
    XCTAssertTrue(ParseConfigSingleWatchItem(
        @"", "", @{
          kWatchItemConfigKeyPaths : @[ @"a" ],
          kWatchItemConfigKeyOptions :
              @{kWatchItemConfigKeyOptionsCustomMessage : @"This is a custom message"}
        },
        data_policies, proc_policies, &err));

    // kWatchItemConfigKeyOptionsCustomMessage Invalid "long" length
    XCTAssertFalse(ParseConfigSingleWatchItem(
        @"", "", @{
          kWatchItemConfigKeyPaths : @[ @"a" ],
          kWatchItemConfigKeyOptions :
              @{kWatchItemConfigKeyOptionsCustomMessage : RepeatedString(@"A", 4096)}
        },
        data_policies, proc_policies, &err));
  }

  // If processes are specified, they must be valid format
  // Note: Full tests in `testVerifyConfigWatchItemProcesses`
  XCTAssertFalse(ParseConfigSingleWatchItem(
      @"", "", @{kWatchItemConfigKeyPaths : @[ @"a" ], kWatchItemConfigKeyProcesses : @""},
      data_policies, proc_policies, &err));

  // Test the policy vector is populated as expected

  // Test default options with no processes
  data_policies.clear();
  XCTAssertTrue(ParseConfigSingleWatchItem(@"rule", kVersion,
                                           @{kWatchItemConfigKeyPaths : @[ @"a" ]}, data_policies,
                                           proc_policies, &err));
  XCTAssertEqual(data_policies.size(), 1);
  XCTAssertEqual(
      *data_policies[0].get(),
      DataWatchItemPolicy("rule", kVersion, "a", kWatchItemPolicyDefaultPathType,
                          kWatchItemPolicyDefaultAllowReadAccess, kWatchItemPolicyDefaultAuditOnly,
                          kWatchItemPolicyDefaultRuleType));
}

- (void)testParseConfigSingleWatchItemPolicies {
  std::vector<std::shared_ptr<DataWatchItemPolicy>> data_policies;
  santa::ProcessWatchItemPolicySet proc_policies;
  NSError *err;

  // Data FAA - Test multiple paths, options, and processes
  data_policies.clear();
  proc_policies.clear();
  std::vector<WatchItemProcess> procs = {
      WatchItemProcess("pa", "", "", {}, "", std::nullopt),
      WatchItemProcess("pb", "", "", {}, "", std::nullopt),
  };

  NSMutableDictionary *singleWatchItemConfig = [@{
    kWatchItemConfigKeyPaths : @[
      @"a", @{kWatchItemConfigKeyPathsPath : @"b", kWatchItemConfigKeyPathsIsPrefix : @(YES)}
    ],
    kWatchItemConfigKeyOptions : [@{
      kWatchItemConfigKeyOptionsAllowReadAccess : @(YES),
      kWatchItemConfigKeyOptionsAuditOnly : @(NO),
      kWatchItemConfigKeyOptionsEnableSilentMode : @(YES),
      kWatchItemConfigKeyOptionsEnableSilentTTYMode : @(NO),
      kWatchItemConfigKeyOptionsCustomMessage : @"",
    } mutableCopy],
    kWatchItemConfigKeyProcesses : @[
      @{kWatchItemConfigKeyProcessesBinaryPath : @"pa"},
      @{kWatchItemConfigKeyProcessesBinaryPath : @"pb"}
    ]
  } mutableCopy];

  singleWatchItemConfig[kWatchItemConfigKeyOptions][kWatchItemConfigKeyOptionsRuleType] =
      @"PathsWithDeniedProcesses";
  XCTAssertTrue(ParseConfigSingleWatchItem(@"rule", kVersion, singleWatchItemConfig, data_policies,
                                           proc_policies, &err));

  XCTAssertEqual(proc_policies.size(), 0);
  XCTAssertEqual(data_policies.size(), 2);
  XCTAssertEqual(*data_policies[0].get(),
                 DataWatchItemPolicy("rule", kVersion, "a", kWatchItemPolicyDefaultPathType, true,
                                     false, santa::WatchItemRuleType::kPathsWithDeniedProcesses,
                                     true, false, "", nil, nil, procs));
  XCTAssertEqual(*data_policies[1].get(),
                 DataWatchItemPolicy("rule", kVersion, "b", WatchItemPathType::kPrefix, true, false,
                                     santa::WatchItemRuleType::kPathsWithDeniedProcesses, true,
                                     false, "", nil, nil, procs));

  // Proc FAA - Test multiple paths, options, and processes
  data_policies.clear();
  proc_policies.clear();

  singleWatchItemConfig[kWatchItemConfigKeyOptions][kWatchItemConfigKeyOptionsRuleType] =
      @"ProcessesWithDeniedPaths";
  XCTAssertTrue(ParseConfigSingleWatchItem(@"rule", kVersion, singleWatchItemConfig, data_policies,
                                           proc_policies, &err));

  XCTAssertEqual(proc_policies.size(), 1);
  XCTAssertEqual(data_policies.size(), 0);
}

- (void)testState {
  NSString *configPath = @"my_config_path";
  NSTimeInterval startTime = [[NSDate date] timeIntervalSince1970];

  NSMutableDictionary *config = WrapWatchItemsConfig(@{
    @"rule1" : @{kWatchItemConfigKeyPaths : @[ @"abc" ]},
    @"rule2" : @{kWatchItemConfigKeyPaths : @[ @"xyz" ]}
  });

  WatchItemsPeer watchItems(configPath, NULL, NULL);

  // If no policy yet exists, nullopt is returned
  std::optional<WatchItemsState> optionalState = watchItems.State();
  XCTAssertFalse(optionalState.has_value());

  watchItems.ReloadConfig(config);

  optionalState = watchItems.State();
  XCTAssertTrue(optionalState.has_value());
  WatchItemsState state = optionalState.value();

  XCTAssertEqual(state.rule_count, [config[kWatchItemConfigKeyWatchItems] count]);
  XCTAssertCStringEqual(state.policy_version.UTF8String, kVersion.data());
  XCTAssertEqual(state.config_path, configPath);
  XCTAssertGreaterThanOrEqual(state.last_config_load_epoch, startTime);
}

- (void)testPathPatternExpectations {
  NSMutableDictionary *config = WrapWatchItemsConfig(@{
    @"rule1" : @{kWatchItemConfigKeyPaths : @[ @"abc", @"xyz*" ]},
  });

  WatchItemsPeer watchItems(@"my_fake_config_path", NULL, NULL);
  watchItems.ReloadConfig(config);

  // Ensure that non-glob patterns are watched
  WatchItems::VersionAndPolicies policies = watchItems.FindPolciesForPaths({"abc"});
  XCTAssertCStringEqual(policies.second[0].value_or(MakeBadPolicy())->name.c_str(), "rule1");

  // Check that patterns with globs are not returned
  policies = watchItems.FindPolciesForPaths({"xyz"});
  XCTAssertFalse(policies.second[0].has_value());
  policies = watchItems.FindPolciesForPaths({"xyzbar"});
  XCTAssertFalse(policies.second[0].has_value());
}

- (void)testSetConfigAndSetConfigPath {
  // Test internal state when switching back and forth between path-based and
  // dictionary-based config options.
  WatchItemsPeer watchItems(@{}, NULL, NULL);

  XCTAssertNil(watchItems.config_path_);
  XCTAssertNotNil(watchItems.embedded_config_);

  watchItems.SetConfigPath(@"/path/to/a/nonexistent/file/so/nothing/is/opened");

  XCTAssertNotNil(watchItems.config_path_);
  XCTAssertNil(watchItems.embedded_config_);

  watchItems.SetConfig(@{});

  XCTAssertNil(watchItems.config_path_);
  XCTAssertNotNil(watchItems.embedded_config_);
}

@end
