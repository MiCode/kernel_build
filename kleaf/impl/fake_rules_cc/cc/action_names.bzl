"""Copied from rules_cc."""

load(
    "@bazel_tools//tools/build_defs/cc:action_names.bzl",
    _ACTION_NAMES = "ACTION_NAMES",
)

ACTION_NAMES = _ACTION_NAMES

# Names of actions that parse or compile C++ code.
ALL_CPP_COMPILE_ACTION_NAMES = [
    ACTION_NAMES.linkstamp_compile,
    ACTION_NAMES.cpp_compile,
    ACTION_NAMES.cpp_header_parsing,
    ACTION_NAMES.cpp_module_compile,
    ACTION_NAMES.cpp_module_codegen,
    ACTION_NAMES.lto_backend,
    ACTION_NAMES.clif_match,
]

# Names of actions that parse or compile C, C++ and assembly code.
ALL_CC_COMPILE_ACTION_NAMES = ALL_CPP_COMPILE_ACTION_NAMES + [
    ACTION_NAMES.c_compile,
    ACTION_NAMES.preprocess_assemble,
    ACTION_NAMES.assemble,
]

# Names of actions that link C, C++ and assembly code.
ALL_CC_LINK_ACTION_NAMES = [
    ACTION_NAMES.cpp_link_executable,
    ACTION_NAMES.cpp_link_dynamic_library,
    ACTION_NAMES.cpp_link_nodeps_dynamic_library,
    ACTION_NAMES.lto_index_for_executable,
    ACTION_NAMES.lto_index_for_dynamic_library,
    ACTION_NAMES.lto_index_for_nodeps_dynamic_library,
]
