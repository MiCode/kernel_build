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
import collections
import json
import logging
import os
import pathlib
import re
import shlex
import shutil
import sys
import textwrap
from typing import Optional, TextIO, Any

_SOURCE_SUFFIXES = (
    ".c",
    ".rs",
    ".S",
    ".o_shipped",
    ".cmd_shipped",
)

# Example:
# -key=$(execpath thing)
_KEY_VALUE_OPT_RE = re.compile(r"^(?P<key>[^$]+)(?P<sep>=)(?P<value>\$\([^)]+\))$")
# $(execpath thing)
_VALUE_OPT_RE = re.compile(r"^\$\([^)]+\)$")

# hyp-obj-y builds hypervisor code
_PKVM_EL2_OBJ = "hyp-obj"

_DDK_MODINFO_SOURCE = "ddk_modinfo.c"

Opts = list[dict[str, str | bool]]

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
                logging.error(
                    "Expect build failure %s, but there's no failure", msg)
                sys.exit(1)
            if die_exception.msg != msg:
                logging.error(*die_exception.args, **die_exception.kwargs)
                logging.error(
                    "Expect build failure %s, but got a different failure", msg)
                sys.exit(1)
            return

        if die_exception is not None:
            logging.error(*die_exception.args, **die_exception.kwargs)
            sys.exit(1)


def die(*args, **kwargs):
    raise DieException(*args, **kwargs)


def _get_license_str():
    return textwrap.dedent("""\
        # SPDX-License-Identifier: GPL-2.0

    """)

def _gen_makefile(
        module_symvers_list: list[pathlib.Path],
        output_makefile: pathlib.Path,
        is_library: bool,
        rel_srcs: list[dict[str, Any]],
        pkvm_el2_out: pathlib.Path | None,
):
    """Generates top-level Makefile.

    Args:
        module_symvers_list: list of Module.symvers from dependencies
        output_makefile: the top level Makefile to write into
        is_library: whether the module is ddk_library
        rel_srcs: list of relative path to source files
        pkvm_el2_out: If set, relative path to output .o for pKVM EL2
    """
    content = _get_license_str()

    content += """
        ifneq ($(origin EXTRA_SYMBOLS), undefined)
        $(error EXTRA_SYMBOLS cannot be set for DDK targets. Use the deps attribute instead.)
        endif
    """

    for module_symvers in module_symvers_list:
        if is_library:
            # TODO - b/395014894: Propagate Module.symvers to linking stage
            content += textwrap.dedent(f"""\
                # Skipping {module_symvers} for ddk_library
            """)
        else:
            content += textwrap.dedent(f"""\
                # Include symbol: {module_symvers}
                EXTRA_SYMBOLS += $(COMMON_OUT_DIR)/{module_symvers}
                """)

    if is_library:
        # ddk_library does not support conditional_srcs for now, because we can't get
        # the list of configs in Makefile.
        if pkvm_el2_out:
            objects = str(pkvm_el2_out)
        else:
            objects = " ".join(str(path.with_suffix(".o"))
                for src_item in rel_srcs for path in src_item["files"])
        content += textwrap.dedent(f"""\
            .PHONY: kleaf-objects

            kleaf-objects:
            \t$(MAKE) -C $(KERNEL_SRC) M=$(M) $(KBUILD_OPTIONS) \\
            \t    KBUILD_EXTRA_SYMBOLS="$(EXTRA_SYMBOLS)"       \\
            \t    {objects}
            """)
    else:
        content += textwrap.dedent("""\
            modules modules_install clean compile_commands.json:
            \t$(MAKE) -C $(KERNEL_SRC) M=$(M) $(KBUILD_OPTIONS) \\
            \t    KBUILD_EXTRA_SYMBOLS="$(EXTRA_SYMBOLS)"       \\
            \t    $(@)
            """)

    os.makedirs(output_makefile.parent, exist_ok=True)
    with open(output_makefile, "w") as out_file:
        out_file.write(content)


def _should_apply_cflags(src: pathlib.Path) -> bool:
    # TODO: b/389976463 - CFLAGS should only be applied to .c files. Change
    #   the list below to ".c" only.
    return src.suffix in (".c", ".rs", ".S")


def _merge_directories(
        output_makefiles: pathlib.Path,
        submodule_makefile_dir: pathlib.Path,
        ddk_modinfos: set[pathlib.Path],
    ):
    """Merges the content of submodule_makefile_dir into output_makefiles.

    File of the same relative path are concatenated.
    ddk_modinfos is modified during this keep track of where it' been copied.
    """

    if not submodule_makefile_dir.is_dir():
        die("Can't find directory %s", submodule_makefile_dir)

    for root, _, files in os.walk(submodule_makefile_dir):
        for file in files:
            submodule_file = pathlib.Path(root) / file
            file_rel = submodule_file.relative_to(submodule_makefile_dir)
            dst_path = output_makefiles / file_rel
            dst_path.parent.mkdir(parents=True, exist_ok=True)
            with open(dst_path, "a") as dst, \
                    open(submodule_file, "r") as src:
                if dst_path.suffix in (".c", ".rs", ".h"):
                    if dst_path.name == _DDK_MODINFO_SOURCE:
                        if file_rel in ddk_modinfos:
                            continue
                        ddk_modinfos.add(file_rel)
                    dst.write(f"// {submodule_file}\n")
                elif dst_path.suffix == ".S":
                    dst.write(f"/* {submodule_file} */\n")
                elif (dst_path.name in ("Kbuild", "Makefile") or
                      dst_path.suffix in (".cmd_shipped")):
                    dst.write(f"# {submodule_file}\n")
                dst.write(src.read())
                dst.write("\n")

def _append_submodule_linux_include_dirs(
        output_makefiles: pathlib.Path,
        linux_include_dirs: list[pathlib.Path],
        submodule_linux_include_dirs: dict[pathlib.Path, list[pathlib.Path]],
):
    """For top-level ddk_module, append LINUXINCLUDE from deps of submodules"""
    for dirname, linux_includes_of_dir in submodule_linux_include_dirs.items():
        kbuild_file = output_makefiles / dirname / "Kbuild"
        with open(kbuild_file, "a") as out_file:
            out_file.write(textwrap.dedent("""\
                # Common LINUXINCLUDE for all submodules in this directory
            """))

            combined_linux_includes = linux_includes_of_dir + linux_include_dirs
            combined_linux_includes = list(collections.OrderedDict.fromkeys(
                combined_linux_includes).keys())
            _handle_linux_includes(out_file, True, combined_linux_includes)


def generate_all_files(
        output_makefiles: pathlib.Path,
        module_symvers_list: list[pathlib.Path],
        package: pathlib.Path,
        produce_top_level_makefile: Optional[bool],
        submodule_makefiles: list[pathlib.Path],
        kernel_module_out: Optional[pathlib.Path],
        linux_include_dirs: list[pathlib.Path],
        submodule_linux_include_dirs: dict[pathlib.Path, list[pathlib.Path]],
        is_library: bool,
        pkvm_el2_out: pathlib.Path | None,
        **kwargs
):
    """Main entry point: generate all relevant files.

    Args:
        output_makefiles: Directory to put all generated files.
            Content of this directory will be copied to the source package when
            the outer target is built.
        module_symvers_list: List of Module.symvers from dependencies
        package: workspace_root / package
        produce_top_level_makefile: If true, generates output_makefiles / "Makefile"
        submodule_makefiles: List of directories from ddk_submodules()
        kernel_module_out: output .ko file
        is_library: Whether the outer target is a `ddk_library`
        pkvm_el2_out: If set, relative path to output .o for pKVM EL2
    """
    rel_srcs = []
    if kernel_module_out:
        rel_srcs = _generate_kbuild_and_extra(
            output_makefiles=output_makefiles,
            package=package,
            kernel_module_out=kernel_module_out,
            linux_include_dirs=linux_include_dirs,
            is_library=is_library,
            is_pkvm_el2=bool(pkvm_el2_out),
            **kwargs
        )

    if produce_top_level_makefile:
        _gen_makefile(
            module_symvers_list=module_symvers_list,
            output_makefile=output_makefiles / "Makefile",
            is_library=is_library,
            rel_srcs = rel_srcs,
            pkvm_el2_out=pkvm_el2_out,
        )

    ddk_modinfos: set[pathlib.Path] = set()
    for submodule_makefile_dir in submodule_makefiles:
        _merge_directories(
            output_makefiles, submodule_makefile_dir, ddk_modinfos)
    _append_submodule_linux_include_dirs(output_makefiles,
                                         linux_include_dirs,
                                         submodule_linux_include_dirs)


def _get_ddk_modinfo(
    output_dir: pathlib.Path,
) -> pathlib.Path:
    os.makedirs(output_dir, exist_ok=True)
    ddk_modinfo = output_dir / _DDK_MODINFO_SOURCE
    ddk_modinfo.write_text(textwrap.dedent("""\
        #include <linux/compiler.h>
        static const char __UNIQUE_ID(built_with)[] __used __section(".modinfo") __aligned(1) = "built_with=DDK";
        """))
    return ddk_modinfo


def _generate_kbuild_and_extra(
        output_makefiles: pathlib.Path,
        package: pathlib.Path,
        kernel_module_out: pathlib.Path,
        kernel_module_srcs_json: TextIO,
        include_dirs: list[pathlib.Path],
        linux_include_dirs: list[pathlib.Path],
        local_defines: list[str],
        copts: Opts | None,
        removed_copts: Opts | None,
        asopts: Opts | None,
        linkopts: Opts | None,
        kbuild_has_linux_include: bool,
        is_library: bool,
        is_pkvm_el2: bool,
        copy_rule_hack: bool,
        **unused_kwargs
):
    """Generates all relevant Kbuild files and extra flag files.

    Args:
        output_makefiles: top-level Makefile, used as an anchor to write
            the Kbuild files
        package: workspace root / package
        kernel_module_out: The output *.ko to build
        kernel_module_srcs_json: JSON containing info of sources
        include_dirs: list of -I
        linux_include_dirs: list of LINUXINCLUDE
        local_defines: list of -D
        copts: JSON containing cflags
        removed_copts: JSON containing removed cflags
        asopts: JSON containing asflags
        linkopts: JSON containing ldflags
        kbuild_has_linux_include: Whether to write LINUXINCLUDE to Kbuild files
        is_library: If set, outer target is a ddk_library
        is_pkvm_el2: If set, building pKVM EL2
        copy_rule_hack: Employ hack for COPY rule
        **unused_kwargs: unused
    """
    kernel_module_srcs_json_content = json.load(kernel_module_srcs_json)
    # List of JSON objects (dictionaries) with keys like "file", "config",
    #  "value", etc.
    rel_srcs = []
    for kernel_module_srcs_json_item in kernel_module_srcs_json_content:
        rel_item = dict(kernel_module_srcs_json_item)
        rel_item["files"] = [pathlib.Path(src).relative_to(package)
                             for src in rel_item.get("files", [])
                             if pathlib.Path(src).is_relative_to(package)]

        # Generated files example:
        #   short_path = package/file.c
        #   path = bazel-out/k8-fastbuild/bin/package/file.c
        #   rel_package_path = file.c
        for short_path, path in rel_item.get("gen", {}).items():
            short_path = pathlib.Path(short_path)
            path = pathlib.Path(path)
            if not short_path.is_relative_to(package):
                continue
            rel_package_path = short_path.relative_to(package)
            rel_item["files"].append(rel_package_path)
            dest = output_makefiles / rel_package_path
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(path, dest)

        rel_srcs.append(rel_item)

    if kernel_module_out.suffix != ".ko":
        die("Invalid output: %s; must end with .ko", kernel_module_out)

    _check_srcs_valid(rel_srcs, kernel_module_out)

    kbuild = output_makefiles / kernel_module_out.parent / "Kbuild"
    os.makedirs(kbuild.parent, exist_ok=True)

    # rel to this package
    gen_cflags_subpath = kernel_module_out.with_suffix(".cflags_shipped")
    gen_asflags_subpath = kernel_module_out.with_suffix(".asflags_shipped")
    gen_ldflags_subpath = kernel_module_out.with_suffix(".ldflags_shipped")

    # Output flags file path
    out_cflags_path = output_makefiles / gen_cflags_subpath
    out_asflags_path = output_makefiles / gen_asflags_subpath
    out_ldflags_path = output_makefiles / gen_ldflags_subpath

    if not is_library:
        # For modinfo tagging
        _handle_ddk_modinfo(rel_srcs, kernel_module_out,
            out_cflags_path, package / gen_cflags_subpath.parent)

    with open(kbuild, "w") as out_file, \
         open(out_cflags_path, "a") as out_cflags, \
         open(out_asflags_path, "a") as out_asflags, \
         open(out_ldflags_path, "a") as out_ldflags:
        out_file.write(_get_license_str())

        if not is_library:
            out_file.write(textwrap.dedent(f"""\
                # Build {package / kernel_module_out}
                obj-m += {kernel_module_out.with_suffix('.o').name}
                """))
            out_file.write("\n")

        for src_item in rel_srcs:
            config = src_item.get("config")
            value = src_item.get("value")
            obj_suffix = "y"

            if config is not None:
                if value == True: # pylint: disable=singleton-comparison
                    # The special value True means y or m.
                    obj_suffix = f"$({config})"
                else:
                    conditional = f"ifeq ($({config}),{value})"
                    out_file.write(f"{conditional}\n")

            for src in src_item["files"]:
                _handle_src(
                    src=src,
                    out_file=out_file,
                    kernel_module_out=kernel_module_out,
                    is_pkvm_el2=is_pkvm_el2,
                    obj_suffix=obj_suffix,
                    dep_type = src_item.get("type", "srcs"),
                    copy_rule_hack=copy_rule_hack
                )

            if config is not None and value != True: # pylint: disable=singleton-comparison
                out_file.write(textwrap.dedent(f"""\
                    endif # {conditional}
                """))

        out_file.write(f"\n# Common flags for {kernel_module_out.with_suffix('.o').name}\n")
        _handle_linux_includes(out_file, kbuild_has_linux_include,
                               linux_include_dirs)
        # At this time of writing (2022-11-01), this is the order how cc_library
        # constructs arguments to the compiler.
        _handle_defines(out_cflags, local_defines)
        _handle_includes(out_cflags, include_dirs)
        _handle_opts(out_cflags, copts, "copts")
        _handle_defines(out_asflags, local_defines)
        _handle_includes(out_asflags, include_dirs)
        _handle_opts(out_asflags, asopts, "asopts")
        _handle_opts(out_ldflags, linkopts, "linkopts")

        out_files_with_cflags = set()
        out_files_with_asflags = set()
        for src_item in rel_srcs:
            config = src_item.get("config")
            value = src_item.get("value")

            if config is not None and value != True: # pylint: disable=singleton-comparison
                conditional = f"ifeq ($({config}),{value})"
                out_file.write(f"{conditional}\n")

            for src in src_item["files"]:

                # Adjustment needed to build nVHE object.
                # See $(srctree)/arch/arm64/kvm/hyp/nvhe/Makefile.module
                out = src.with_suffix(".nvhe.o" if is_pkvm_el2 else ".o")
                out = out.relative_to(kernel_module_out.parent)

                if (out not in out_files_with_cflags and
                        _should_apply_cflags(src)):
                    out_files_with_cflags.add(out)
                    # kernel_module() copies makefiles and .cflags files to
                    # $(ROOT_DIR)/<package> (aka $ROOT_DIR/<ext_mod>) and fix up
                    # .cflags files there before building.
                    out_file.write(textwrap.dedent(f"""\
                        CFLAGS_{out} += @$(obj)/{gen_cflags_subpath.with_suffix(".cflags").name}
                        $(obj)/{out}: $(obj)/{gen_cflags_subpath.with_suffix(".cflags").name}
                        """))
                    _handle_opts_kbuild(out_file, "CFLAGS_REMOVE", out,
                                        removed_copts, "removed_copts")

                if ((local_defines or include_dirs or asopts) and
                        src.suffix == ".S" and
                        out not in out_files_with_asflags):
                    out_files_with_asflags.add(out)
                    out_file.write(textwrap.dedent(f"""\
                        AFLAGS_{out} += @$(obj)/{gen_asflags_subpath.with_suffix(".asflags").name}
                        $(obj)/{out}: $(obj)/{gen_asflags_subpath.with_suffix(".asflags").name}
                        """))

            if config is not None and value != True: # pylint: disable=singleton-comparison
                out_file.write(f"endif # {conditional}\n\n")

        if linkopts:
            out_file.write(textwrap.dedent(f"""\
                LDFLAGS_{kernel_module_out.with_suffix('.o').name} += @$(obj)/{gen_ldflags_subpath.with_suffix(".ldflags").name}
                $(obj)/{kernel_module_out.with_suffix('.o').name}: $(obj)/{gen_ldflags_subpath.with_suffix(".ldflags").name}
            """))

    top_kbuild = output_makefiles / "Kbuild"
    if top_kbuild != kbuild:
        os.makedirs(output_makefiles, exist_ok=True)
        with open(top_kbuild, "w") as out_file:
            out_file.write(_get_license_str())
            out_file.write(textwrap.dedent(f"""\
                # Build {package / kernel_module_out}
                obj-y += {kernel_module_out.parent}/
                """))
    if is_pkvm_el2:
        with open(top_kbuild, "a") as out_file:
            out_file.write("include $(srctree)/arch/$(SRCARCH)/kvm/hyp/nvhe/Makefile.module")

    return rel_srcs

def _get_rel_srcs_flat(rel_srcs: list[dict[str, Any]]) -> list[pathlib.Path] :
    """List of source file paths(minus headers)."""
    rel_srcs_flat: list[pathlib.Path] = []
    for rel_item in rel_srcs:
        files = rel_item["files"]
        rel_srcs_flat.extend(
            file for file in files if file.suffix in _SOURCE_SUFFIXES)
    return list(set(rel_srcs_flat))

def _check_srcs_valid(rel_srcs: list[dict[str, Any]],
                      kernel_module_out: pathlib.Path):
    """Checks that the list of srcs is valid.

    Args:
        rel_srcs: Like content in kernel_module_srcs_json, but only includes
         files relative to the current package.
        kernel_module_out: The `out` attribute.
    """
    rel_srcs_flat = _get_rel_srcs_flat(rel_srcs)

    source_files_with_name_of_kernel_module = \
        [src for src in rel_srcs_flat if src.with_suffix(
            ".ko") == kernel_module_out]

    if source_files_with_name_of_kernel_module and len(rel_srcs_flat) > 1:
        die("Source files %s are not allowed to build %s when multiple source"
            " files exist."
            " Please change the name of the output file.",
            [str(e) for e in source_files_with_name_of_kernel_module],
            kernel_module_out)


def _handle_ddk_modinfo(
        rel_srcs: list[dict[str, Any]],
        kernel_module_out: pathlib.Path,
        out_cflags_path: pathlib.Path,
        package: pathlib.Path
):
    """Adds ddk_modinfo.c or implicitly include it."""
    rel_srcs_flat = _get_rel_srcs_flat(rel_srcs)
    # Avoid possible collisions if there is an existing ddk_modinfo.c file.
    #  or if the output .ko is named ddk_modinfo.ko
    if any([src.name == _DDK_MODINFO_SOURCE for src in rel_srcs_flat]):
        die("%s is not allowed to be a source file", _DDK_MODINFO_SOURCE)
    if kernel_module_out.with_suffix(".c") == _DDK_MODINFO_SOURCE:
        die("%s is not allowed to be the output file", kernel_module_out)

    ddk_modinfo = _get_ddk_modinfo(out_cflags_path.parent)
    # Depending on the number of files, choose an appropriate path for tagging.
    if len(rel_srcs_flat) > 1:
        rel_srcs.append(
            {"files": [kernel_module_out.parent / ddk_modinfo.name]})
    else:
        with open(out_cflags_path, "w") as out_cflags:
            out_cflags.write("\n")
            out_cflags.write(textwrap.dedent(f"""\
                    -include $(ROOT_DIR)/{str(package / ddk_modinfo.name)}
                """))
            out_cflags.write("\n")

def _handle_src(
        src: pathlib.Path,
        out_file: TextIO,
        kernel_module_out: pathlib.Path,
        is_pkvm_el2: bool,
        obj_suffix: str,
        dep_type: str,
        copy_rule_hack: bool,
):
    """Writes rules to build a single source file.

    Args:
        src: the source file to build
        out_file: The output Kbuild file
        kernel_module_out: The final .ko file, used as an anchor for checks
        is_pkvm_el2: If true, builds pKVM EL2 code
        obj_suffix: Suffix to `obj-`
        dep_type: Type of the dependency:
            * srcs
            * crate_root
            * library, for deps with DdkLibraryInfo
        copy_rule_hack: Employ hack for COPY rule
    """
    if src.suffix not in _SOURCE_SUFFIXES:
        die("Invalid source %s", src)
    if not src.is_relative_to(kernel_module_out.parent):
        die("%s is not a valid source because it is not under %s",
            src, kernel_module_out.parent)

    # Ignore non-crate-root .rs. Only crate-root .rs is added.
    if src.suffix == ".rs" and dep_type != "crate_root":
        return

    if src.suffix == ".cmd_shipped":
        abs_out = src.with_suffix(".cmd")
    else:
        abs_out = src.with_suffix(".o")

    out = abs_out.relative_to(kernel_module_out.parent)
    # Ignore self (don't omit obj-foo += foo.o)
    if src.with_suffix(".ko") == kernel_module_out:
        out_file.write(textwrap.dedent(f"""\
                        # The module {kernel_module_out} has a source file {src}
                    """))
    else:
        if src.suffix == ".cmd_shipped":
            object_to_build = "always"
        elif is_pkvm_el2:
            object_to_build = _PKVM_EL2_OBJ
        else:
            object_to_build = kernel_module_out.with_suffix('').name

        out_file.write(textwrap.dedent(f"""\
                        {object_to_build}-{obj_suffix} += {out}
                    """))

        # HACK: http://b/402888498 - COPY rule doesn't work, so hack it up.
        # TODO: http://b/402888498 - Figure out why it doesn't work, and remove
        #   this hack to use the pattern rule provided by Kbuild.
        if copy_rule_hack and src.suffix in (".o_shipped", ".cmd_shipped"):
            out_file.write(textwrap.dedent(f"""\
                $(obj)/{out}: $(src)/{src.relative_to(kernel_module_out.parent)}
                \t$(call cmd,copy)
            """))


def _handle_linux_includes(out_file: TextIO, kbuild_has_linux_include: bool,
                           linux_include_dirs: list[pathlib.Path]):
    """Writes LINUXINCLUDE to Kbuild.

    Args:
        out_file: Kbuild
        kbuild_has_linux_include: whether to add LINUXINCLUDE to Kbuild at all
        linux_include_dirs: List of paths to write
    """
    if not linux_include_dirs:
        return
    if not kbuild_has_linux_include:
        out_file.write(
            "# Skipping LINUXINCLUDE for submodules; they are added later\n")
        return
    out_file.write("\n")
    out_file.write(textwrap.dedent("""\
        LINUXINCLUDE := \\
    """))
    for linux_include_dir in linux_include_dirs:
        out_file.write(f"  -I$(ROOT_DIR)/{linux_include_dir} \\")
        out_file.write("\n")
    out_file.write("  $(LINUXINCLUDE)")
    out_file.write("\n\n")


def _handle_defines(out_cflags: TextIO,
                    local_defines: list[str]):
    """Writes -D... to .cflags.

    Args:
        out_cflags: the .cflags file
        local_defines: The list of defines
    """
    if not local_defines:
        return
    for local_define in local_defines:
        out_cflags.write(textwrap.dedent(f"""\
            {shlex.quote(f"-D{local_define}")}
            """))


def _handle_includes(out_cflags: TextIO,
                     include_dirs: list[pathlib.Path]):
    """Writes -I... to .cflags.

    Args:
        out_cflags: the .cflags file
        include_dirs: The list of include search paths
    """

    for include_dir in include_dirs:
        out_cflags.write(textwrap.dedent(f"""\
            -I$(ROOT_DIR)/{shlex.quote(str(include_dir))}
            """))


def _handle_opts(out_flags: TextIO,
                 opts: Opts | None,
                 attr_name: str):
    """Writes opts into out_flags.

    Args:
        out_flags: The .?flags file to write to
        opts: list of flags
        attr_name: The relevant Bazel attribute name
    """
    if not opts:
        return

    for d in opts:
        expanded: str = d["expanded"]
        orig: str = d["orig"]

        out_flags.write(textwrap.dedent(f"""\
            {_quote_transform_opt(orig, expanded, attr_name)}
            """))


def _handle_opts_kbuild(out_file: TextIO, flag_type: str, out: str,
                        removed_opts: Opts | None,
                        attr_name: str):
    """Writes removed opts into Kbuild out_file.

    Args:
        out_file: The Kbuild file
        flag_type: CFLAGS_REMOVE
        out: output .o file stem
        removed_opts: the JSON dictionary provided by gen_makefiles.bzl
    """

    # CFLAGS_REMOVE_ etc. needs to be written to Kbuild directly because
    # it is implemented with $(filter-out).
    if not removed_opts:
        return

    for d in removed_opts:
        expanded: str = d["expanded"]
        orig: str = d["orig"]

        out_file.write(textwrap.dedent(f"""\
            {flag_type}_{out} += {_quote_transform_opt(orig, expanded, attr_name)}
        """))


def _quote_transform_opt(orig: str, expanded: str, attr_name: str):
    """Quote and transform a given flag.

    Paths are properly fixed.

    Args:
        orig: original text in the Bazel target attribute
        expanded: expanded paths after ctx.expand_location()
        attr_name: The relevant Bazel target attribute name.
    """
    if expanded == orig:
        return shlex.quote(expanded)

    mo = _VALUE_OPT_RE.match(orig)
    if mo:
        return f"$(ROOT_DIR)/{shlex.quote(expanded)}"

    mo = _KEY_VALUE_OPT_RE.match(orig)
    if mo:
        prefix = f"{mo.group('key')}{mo.group('sep')}"
        if not expanded.startswith(prefix):
            die("Invalid %s: %s. Expected %s to start with %s",
                attr_name, orig, expanded, prefix)
        expanded_value = expanded.removeprefix(prefix)
        return f"{prefix}$(ROOT_DIR)/{shlex.quote(expanded_value)}"

    die("Invalid %s: %s. $(location) expressions must be its own token, or "
        "part of -key=$(location target)", attr_name, orig)


class SubmoduleLinuxIncludeDirAction(argparse.Action):
    def __call__(self, parser, namespace, values, option_string=None):
        if not values:
            raise argparse.ArgumentTypeError(
                "--submodule-linux-include-dirs requires at least one value")
        dirname = values[0]
        if not hasattr(namespace, self.dest):
            setattr(namespace, self.dest, {})
        getattr(namespace, self.dest)[dirname] = values[1:]


def _load_opts(path: str) -> Opts:
    """Loads JSON opts from a given Path."""
    with pathlib.Path(path).open() as fp:
        return json.load(fp)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO,
                        format="%(levelname)s: %(message)s")

    parser = absl.flags.argparse_flags.ArgumentParser(description=__doc__)
    parser.add_argument("--package", type=pathlib.Path)
    parser.add_argument("--kernel-module-out", type=pathlib.Path)
    parser.add_argument("--kernel-module-srcs-json",
                        type=argparse.FileType("r"), required=True)
    parser.add_argument("--output-makefiles", type=pathlib.Path)
    parser.add_argument("--linux-include-dirs",
                        type=pathlib.Path, nargs="*", default=[])
    parser.add_argument("--include-dirs", type=pathlib.Path,
                        nargs="*", default=[])
    parser.add_argument("--module-symvers-list",
                        type=pathlib.Path, nargs="*", default=[])
    parser.add_argument("--local-defines", nargs="*", default=[])
    parser.add_argument("--copts-file", type=_load_opts, dest="copts")
    parser.add_argument("--removed-copts-file", type=_load_opts, dest="removed_copts")
    parser.add_argument("--asopts-file", type=_load_opts, dest="asopts")
    parser.add_argument("--linkopts-file", type=_load_opts, dest="linkopts")
    parser.add_argument("--produce-top-level-makefile", action="store_true")
    parser.add_argument("--kbuild-has-linux-include", action="store_true")
    parser.add_argument("--kbuild-add-submodule-linux-include",
                        action="store_true")
    parser.add_argument("--submodule-makefiles",
                        type=pathlib.Path, nargs="*", default=[])
    parser.add_argument("--internal-target-fail-message", default=None)
    parser.add_argument("--submodule-linux-include-dirs",
                        type=pathlib.Path, nargs="+", default={},
                        action=SubmoduleLinuxIncludeDirAction)
    parser.add_argument("--is-library", action="store_true")
    parser.add_argument("--pkvm-el2-out", type=pathlib.Path)
    parser.add_argument("--copy-rule-hack", action="store_true")
    args = parser.parse_args()

    die_exception = None
    try:
        generate_all_files(**vars(args))
    except DieException as exc:
        die_exception = exc
    finally:
        DieException.handle(die_exception, args.internal_target_fail_message)
