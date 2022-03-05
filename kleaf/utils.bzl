# Copyright (C) 2022 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

def reverse_dict(d):
    """Reverse a dictionary of {key: [value, ...]}

    Return {value: [key, ...]}.
    """
    ret = {}
    for k, values in d.items():
        for v in values:
            if v not in ret:
                ret[v] = []
            ret[v].append(k)
    return ret

def getoptattr(thing, attr, default_value = None):
    """Return attribute value if |thing| has attribute named |attr|, otherwise return |default_value|."""
    if hasattr(thing, attr):
        return getattr(thing, attr)
    return default_value

def find_file(name, files, what, required = False):
    """Find a file named |name| in the list of |files|. Expect zero or one match."""
    result = []
    for file in files:
        if file.basename == name:
            result.append(file)
    if len(result) > 1 or (not result and required):
        fail("{what} contains {actual_len} file(s) named {name}, expected {expected_len}{files}".format(
            what = what,
            actual_len = len(result),
            name = name,
            expected_len = "1" if required else "0 or 1",
            files = ":\n  " + ("\n  ".join(result)) if result else "",
        ))
    return result[0] if result else None

def find_files(files, what, suffix = None):
    """Find files with given condition. The following conditions are accepted:

    - Looking for files ending with a given suffix.
    """
    result = []
    for file in files:
        if suffix != None and file.basename.endswith(suffix):
            result.append(file)
    return result
