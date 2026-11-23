// Copyright (C) 2024 The Android Open Source Project
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//       http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Helper wrapper for hermetic tools to wrap arguments.
//
// This roughly equivalent to:
// 1. mypath = $(readlink /proc/self/exe)
// 2. tool_name = basename(mypath)
// 3. internal_dir = dirname(mypath)/kleaf_internal_do_not_use
// 3. call <internal_dir>/<tool_name> $@ \\
//      $(cat <internal_dir>/<tool_name>_args.txt)
//
// This is a C++ binary instead of a shell / Python script so that
// /proc/self/exe is a proper anchor to find internal_dir. If this were a
// script, /proc/self/exe would be the path to the interpreter.
// This also avoids using any hermetic tools in order to determine the path to
// them.

#include <linux/limits.h>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>

#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

namespace {

// $(realpath /proc/self/exe)
std::filesystem::path get_my_path() {
  std::error_code ec;
  auto my_path = std::filesystem::read_symlink("/proc/self/exe", ec);
  if (ec.value() != 0) {
    std::cerr << "ERROR: read_symlink /proc/self/exe: " << ec.message()
              << std::endl;
    exit(EX_SOFTWARE);
  }
  return my_path;
}

// Loads <tool_name>_args.txt from hermetic_tools.extra_args
std::vector<std::string> load_arg_file(const std::filesystem::path& path) {
  std::ifstream ifs(path);
  if (!ifs) {
    int saved_errno = errno;
    std::cerr << "Unable to open " << path << ": " << strerror(saved_errno)
              << std::endl;
    exit(EX_SOFTWARE);
  }
  std::vector<std::string> args;
  for (std::string arg; std::getline(ifs, arg);) {
    args.push_back(arg);
  }
  return args;
}

}  // namespace

int main(int argc, char* argv[]) {
  auto my_path = get_my_path();
  auto internal_dir = my_path.parent_path() / "kleaf_internal_do_not_use";

  std::string tool_name(my_path.filename());

  // The actual executable we are going to call. Cast to string to use
  // in new_argv.
  std::string real_executable = internal_dir / tool_name;

  std::vector<char*> new_argv;
  new_argv.push_back(real_executable.data());

  if (argc < 1) {
    std::cerr << "ERROR: argc == " << argc << " < 1" << std::endl;
    return EX_SOFTWARE;
  }
  for (int i = 1; i < argc; i++) {
    new_argv.push_back(argv[i]);
  }

  auto extra_args_file = internal_dir / (tool_name + "_args.txt");
  auto preset_args = load_arg_file(extra_args_file);
  for (auto& preset_arg : preset_args) {
    new_argv.push_back(preset_arg.data());
  }
  new_argv.push_back(nullptr);

  if (-1 == execv(real_executable.c_str(), new_argv.data())) {
    int saved_errno = errno;
    std::cerr << "ERROR: execv: " << real_executable << ": "
              << strerror(saved_errno) << std::endl;
    return EX_SOFTWARE;
  }
  std::cerr << "ERROR: execv returns!" << std::endl;
  return EX_SOFTWARE;
}
