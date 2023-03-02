# Copyright (C) 2022 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
Generate a DDK module Makefile
"""

import absl.flags.argparse_flags
import argparse
import json
import logging
import os
import pathlib
import shlex
import sys
import textwrap
from typing import Optional, TextIO

_SOURCE_SUFFIXES = (
    ".c",
    ".rs",
    ".s",
)


class DieException(SystemExit):
    def __init__(self, *args, **kwargs):
        super().__init__(1)
        self.args = args
        self.kwargs = kwargs

    @property
    def msg(self):
        return self.args[0] % tuple(self.args[1:])

    @staticmethod
    def handle(die_exception: Optional["DieException"], msg: Optional[str]):
        if msg:
            if die_exception is None:
                logging.error(f"Expect build failure %s, but there's no failure", msg)
                sys.exit(1)
            if die_exception.msg != msg:
                logging.error(*die_exception.args, **die_exception.kwargs)
                logging.error(f"Expect build failure %s, but got a different failure", msg)
                sys.exit(1)
            return

        if die_exception is not None:
            logging.error(*die_exception.args, **die_exception.kwargs)
            sys.exit(1)


def die(*args, **kwargs):
    raise DieException(*args, **kwargs)


def _gen_makefile(
        package: pathlib.Path,
        module_symvers_list: list[pathlib.Path],
        output_makefile: pathlib.Path,
):
    # kernel_module always executes in a sandbox. So ../ only traverses within
    # the sandbox.
    rel_root = os.path.join(*([".."] * len(package.parts)))

    content = ""

    for module_symvers in module_symvers_list:
        content += textwrap.dedent(f"""\
            # Include symbol: {module_symvers}
            EXTRA_SYMBOLS += $(OUT_DIR)/$(M)/{rel_root}/{module_symvers}
            """)

    content += textwrap.dedent("""\
        modules modules_install clean:
        \t$(MAKE) -C $(KERNEL_SRC) M=$(M) $(KBUILD_OPTIONS) KBUILD_EXTRA_SYMBOLS="$(EXTRA_SYMBOLS)" $(@)
        """)

    os.makedirs(output_makefile.parent, exist_ok=True)
    with open(output_makefile, "w") as out_file:
        out_file.write(content)


def _write_ccflag(out_file, object_file, ccflag):
    out_file.write(textwrap.dedent(f"""\
        CFLAGS_{object_file} += {shlex.quote(ccflag)}
        """))


def _merge_directories(output_makefiles: pathlib.Path, submodule_makefile_dir: pathlib.Path):
    """Merges the content of submodule_makefile_dir into output_makefiles.

    File of the same relative path are concatenated.
    """

    if not submodule_makefile_dir.is_dir():
        die("Can't find directory %s", submodule_makefile_dir)

    for root, dirs, files in os.walk(submodule_makefile_dir):
        for file in files:
            submodule_file = pathlib.Path(root) / file
            file_rel = submodule_file.relative_to(submodule_makefile_dir)
            dst_path = output_makefiles / file_rel
            dst_path.parent.mkdir(parents=True, exist_ok=True)
            with open(dst_path, "a") as dst, \
                    open(submodule_file, "r") as src:
                dst.write(f"# {submodule_file}\n")
                dst.write(src.read())
                dst.write("\n")


def gen_ddk_makefile(
        output_makefiles: pathlib.Path,
        module_symvers_list: list[pathlib.Path],
        package: pathlib.Path,
        produce_top_level_makefile: Optional[bool],
        submodule_makefiles: list[pathlib.Path],
        kernel_module_out: Optional[pathlib.Path],
        **kwargs
):
    if produce_top_level_makefile:
        _gen_makefile(
            package=package,
            module_symvers_list=module_symvers_list,
            output_makefile=output_makefiles / "Makefile",
        )

    if kernel_module_out:
        _gen_ddk_makefile_for_module(
            output_makefiles=output_makefiles,
            package=package,
            kernel_module_out=kernel_module_out,
            **kwargs
        )

    for submodule_makefile_dir in submodule_makefiles:
        _merge_directories(output_makefiles, submodule_makefile_dir)


def _gen_ddk_makefile_for_module(
        output_makefiles: pathlib.Path,
        package: pathlib.Path,
        kernel_module_out: pathlib.Path,
        kernel_module_srcs_json: TextIO,
        include_dirs: list[pathlib.Path],
        linux_include_dirs: list[pathlib.Path],
        local_defines: list[str],
        copt_file: Optional[TextIO],
        **unused_kwargs
):
    kernel_module_srcs_json_content = json.load(kernel_module_srcs_json)
    rel_srcs = []
    for kernel_module_srcs_json_item in kernel_module_srcs_json_content:
        rel_item = dict(kernel_module_srcs_json_item)
        rel_item["files"] = [pathlib.Path(src).relative_to(package)
                             for src in rel_item["files"]
                             if pathlib.Path(src).is_relative_to(package)]
        rel_srcs.append(rel_item)

    if kernel_module_out.suffix != ".ko":
        die("Invalid output: %s; must end with .ko", kernel_module_out)

    kbuild = output_makefiles / kernel_module_out.parent / "Kbuild"
    os.makedirs(kbuild.parent, exist_ok=True)

    copts = json.load(copt_file) if copt_file else None

    with open(kbuild, "w") as out_file:
        out_file.write(textwrap.dedent(f"""\
            # Build {package / kernel_module_out}
            obj-m += {kernel_module_out.with_suffix('.o').name}
            """))
        out_file.write("\n")

        #    //path/to/package:target/name/foo.ko
        # =>   path/to/package/target/name
        rel_root_reversed = pathlib.Path(package) / kernel_module_out.parent
        rel_root = pathlib.Path(*([".."] * len(rel_root_reversed.parts)))

        _handle_linux_includes(out_file, linux_include_dirs, rel_root)

        for src_item in rel_srcs:
            config = src_item.get("config")
            value = src_item.get("value")

            if config is not None:
                conditional = f"ifeq ($({config}),{value})"
                out_file.write(f"{conditional}\n")

            for src in src_item["files"]:
                _handle_src(
                    src=src,
                    out_file=out_file,
                    kernel_module_out=kernel_module_out,
                    package=package,
                    local_defines=local_defines,
                    include_dirs=include_dirs,
                    rel_root=rel_root,
                    copts=copts,
                )

            if config is not None:
                out_file.write(textwrap.dedent(f"""\
                    endif # {conditional}
                """))

    top_kbuild = output_makefiles / "Kbuild"
    if top_kbuild != kbuild:
        os.makedirs(output_makefiles, exist_ok=True)
        with open(top_kbuild, "w") as out_file:
            out_file.write(textwrap.dedent(f"""\
                # Build {package / kernel_module_out}
                obj-y += {kernel_module_out.parent}/
                """))


def _handle_src(
        src: pathlib.Path,
        out_file: TextIO,
        kernel_module_out: pathlib.Path,
        package: pathlib.Path,
        local_defines: list[str],
        include_dirs: list[pathlib.Path],
        rel_root: pathlib.Path,
        copts: Optional[list[dict[str, str | bool]]],
):
    # Ignore non-exported headers specified in srcs
    if src.suffix.lower() in (".h",):
        return
    if src.suffix.lower() not in _SOURCE_SUFFIXES:
        die("Invalid source %s", src)
    if not src.is_relative_to(kernel_module_out.parent):
        die("%s is not a valid source because it is not under %s",
            src, kernel_module_out.parent)

    out = src.with_suffix(".o").relative_to(kernel_module_out.parent)
    # Ignore self (don't omit obj-foo += foo.o)
    if src.with_suffix(".ko") == kernel_module_out:
        out_file.write(textwrap.dedent(f"""\
                        # The module {kernel_module_out} has a source file {src}
                    """))
    else:
        out_file.write(textwrap.dedent(f"""\
                        # Source: {package / src}
                        {kernel_module_out.with_suffix('').name}-y += {out}
                    """))

        out_file.write("\n")

    # At this time of writing (2022-11-01), this is the order how cc_library
    # constructs arguments to the compiler.
    _handle_defines(out_file, out, local_defines)
    _handle_includes(out_file, out, include_dirs, rel_root)
    _handle_copts(out_file, out, copts, rel_root)

    out_file.write("\n")


def _handle_linux_includes(out_file: TextIO,
                           linux_include_dirs: list[pathlib.Path],
                           rel_root: pathlib.Path):
    if not linux_include_dirs:
        return
    out_file.write("\n")
    out_file.write(textwrap.dedent("""\
        LINUXINCLUDE := \\
    """))
    for linux_include_dir in linux_include_dirs:
        out_file.write(f"  -I$(srctree)/$(src)/{rel_root}/{linux_include_dir} \\")
        out_file.write("\n")
    out_file.write("  $(LINUXINCLUDE)")
    out_file.write("\n\n")


def _handle_defines(out_file: TextIO,
                    object_file: pathlib.Path,
                    local_defines: list[str]):
    if not local_defines:
        return
    out_file.write("\n")
    out_file.write(textwrap.dedent("""\
        # local defines
        """))
    for local_define in local_defines:
        _write_ccflag(out_file, object_file, f"-D{local_define}")


def _handle_includes(out_file: TextIO,
                     object_file: pathlib.Path,
                     include_dirs: list[pathlib.Path],
                     rel_root: pathlib.Path):
    for include_dir in include_dirs:
        out_file.write(textwrap.dedent(f"""\
            # Include {include_dir}
            """))
        _write_ccflag(out_file, object_file, f"-I$(srctree)/$(src)/{rel_root}/{include_dir}")


def _handle_copts(out_file: TextIO,
                  object_file: pathlib.Path,
                  copts: Optional[list[dict[str, str | bool]]],
                  rel_root: pathlib.Path):
    if not copts:
        return

    out_file.write("\n")
    out_file.write(textwrap.dedent("""\
        # copts
        """))

    for d in copts:
        expanded: str = d["expanded"]
        is_path: bool = d["is_path"]

        if is_path:
            expanded = str(rel_root / expanded)

        _write_ccflag(out_file, object_file, expanded)


if __name__ == "__main__":
    # argparse_flags.ArgumentParser only accepts --flagfile if there
    # are some DEFINE'd flags
    # https://github.com/abseil/abseil-py/issues/199
    absl.flags.DEFINE_string("flagfile_hack_do_not_use", "", "")

    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")

    parser = absl.flags.argparse_flags.ArgumentParser(description=__doc__)
    parser.add_argument("--package", type=pathlib.Path)
    parser.add_argument("--kernel-module-out", type=pathlib.Path)
    parser.add_argument("--kernel-module-srcs-json", type=argparse.FileType("r"), required=True)
    parser.add_argument("--output-makefiles", type=pathlib.Path)
    parser.add_argument("--linux-include-dirs", type=pathlib.Path, nargs="*", default=[])
    parser.add_argument("--include-dirs", type=pathlib.Path, nargs="*", default=[])
    parser.add_argument("--module-symvers-list", type=pathlib.Path, nargs="*", default=[])
    parser.add_argument("--local-defines", nargs="*", default=[])
    parser.add_argument("--copt-file", type=argparse.FileType("r"))
    parser.add_argument("--produce-top-level-makefile", action="store_true")
    parser.add_argument("--submodule-makefiles", type=pathlib.Path, nargs="*", default=[])
    parser.add_argument("--internal-target-fail-message", default=None)

    args = parser.parse_args()

    die_exception = None
    try:
        gen_ddk_makefile(**vars(args))
    except DieException as exc:
        die_exception = exc
    finally:
        DieException.handle(die_exception, args.internal_target_fail_message)
