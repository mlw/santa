"""This module defines some helper rules."""

load("@build_bazel_rules_apple//apple:macos.bzl", "macos_unit_test", "macos_command_line_application")
load("@build_bazel_rules_apple//apple:resources.bzl", "apple_resource_group")

def run_command(name, cmd, **kwargs):
    """A rule to run a command."""
    native.genrule(
        name = "%s__gen" % name,
        executable = True,
        outs = ["%s.sh" % name],
        cmd = "echo '#!/bin/bash' > $@ && echo '%s' >> $@" % cmd,
        **kwargs
    )
    native.sh_binary(
        name = name,
        srcs = ["%s.sh" % name],
    )

def santa_unit_test(
        name,
        srcs = [],
        deps = [],
        size = "medium",
        minimum_os_version = "10.15",
        resources = [],
        structured_resources = [],
        copts = [],
        data = [],
        **kwargs):
    apple_resource_group(
        name = "%s_resources" % name,
        resources = resources,
        structured_resources = structured_resources,
    )

    native.objc_library(
        name = "%s_lib" % name,
        testonly = 1,
        srcs = srcs,
        deps = deps,
        copts = copts,
        data = [":%s_resources" % name],
        **kwargs
    )

    macos_unit_test(
        name = "%s" % name,
        bundle_id = "com.google.santa.UnitTest.%s" % name,
        minimum_os_version = minimum_os_version,
        deps = [":%s_lib" % name],
        size = size,
        data = data,
        visibility = ["//:__subpackages__"],
    )

def santa_gtest_old(
        name,
        srcs = [],
        deps = [],
        size = "medium",
        minimum_os_version = "10.15",
        # resources = [],
        # structured_resources = [],
        copts = [],
        data = [],
        **kwargs):
    # apple_resource_group(
    #     name = "%s_resources" % name,
    #     resources = resources,
    #     structured_resources = structured_resources,
    # )

    native.objc_library(
        name = "%s_lib" % name,
        testonly = 1,
        srcs = srcs,
        deps = deps,
        copts = copts,
        data = [":%s_resources" % name],
        **kwargs
    )

    macos_command_line_application(
        name = "%s" % name,
        bundle_id = "com.google.santa.metricservice",
        codesignopts = [
            "--timestamp",
            "--force",
            "--options library,kill,runtime",
        ],
        infoplists = ["Info.plist"],
        minimum_os_version = "10.15",
        provisioning_profile = select({
            "//:adhoc_build": None,
            "//conditions:default": "//profiles:santa_dev",
        }),
        version = "//:version",
        visibility = ["//:__subpackages__"],
        deps = [":%s_lib" % name],
    )

def santa_gtest(
        name,
        srcs = [],
        deps = [],
        size = "medium",
        minimum_os_version = "10.15",
        # resources = [],
        # structured_resources = [],
        copts = [],
        # data = [],
        **kwargs):

    # print("Got here noice: %s | %s" % (name, srcs))
    # native.objc_library(
    #     name = "%s_lib" % name,
    #     testonly = 1,
    #     srcs = srcs,
    #     deps = deps,
    #     # copts = copts,
    #     **kwargs
    # )
    print("About to cc_test")
    #echo hdrs >> TestRunner.cc

    native.cc_test(
      name = "%s" % name,
      srcs = ["TestRunner.cc"],

      # hdrs = ["TestTest.mm"],
      deps = [
        # ":%s_lib" % name,
        # "//Source/common:TestTest.mm",
        "@com_google_googletest//:gtest_main",
      ]
    )

def santa_unit_gtest(
        name,
        hdrs,
        srcs = [],
        deps = [],
        # copts = [],
        **kwargs):

    native.objc_library(
        name = "%s_lib" % name,
        testonly = 1,
        srcs = srcs,
        alwayslink = 1,
        deps = deps,
        linkopts = [
          # "-r"
          # "-lgtest",
          # "-lgtest_main"
          # "-flat_namespace",
        ],
        # copts = copts,
        **kwargs
    )

    #echo hdrs >> TestRunner.cc

    native.cc_test(
      name = "%s" % name,
        srcs = [
            "TestRunner.cc",
            hdrs,
        ],
        # linkopts = ["-r"],
        # linkopts = ["-lgtest", "-lgtest_main"],
        deps = [
            ":%s_lib" % name,
            "@com_google_googletest//:gtest",
            # "@com_google_googletest//:gtest_main",
        ]
    )

# def santa_unit_gtest(
#         name,
#         hdrs,
#         srcs = [],
#         deps = [],
#         # copts = [],
#         **kwargs):

#     print("Got here noice: %s | %s" % (name, srcs))
#     # if not isinstance(hdrs, str):
#     #     #print("`hdrs` must be a string type")
#     #     fail("`hdrs` must be a string type")

#     # native.cc_library(
#     native.objc_library(
#         name = "%s_lib" % name,
#         testonly = 1,
#         srcs = srcs,

#         deps = deps,
#         linkopts = [
#           # "-r"
#           # "-lgtest",
#           # "-lgtest_main"
#           "-flat_namespace",
#         ],
#         # copts = copts,
#         **kwargs
#     )
#     print("About to cc_test")
#     #echo hdrs >> TestRunner.cc

#     native.cc_test(
#       name = "%s" % name,
#         srcs = [
#             "TestRunner.cc",
#             hdrs,
#         ],
#         # linkopts = ["-r"],
#         # linkopts = ["-lgtest", "-lgtest_main"],

#         # hdrs = ["TestTest.mm"],
#         deps = [
#             ":%s_lib" % name,
#             "@com_google_googletest//:gtest",
#             # "@com_google_googletest//:gtest_main",
#         ]
#     )
