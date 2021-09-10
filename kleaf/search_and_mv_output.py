#!/usr/bin/env python3

import argparse
import collections
import os
import shutil


def handle_outputs_with_slash(srcdir, dstdir, outputs):
  for out in outputs:
    shutil.copy(os.path.join(srcdir, out), dstdir)
    shutil.move(os.path.join(srcdir, out), os.path.join(dstdir, out))


def handle_outputs_without_slash(srcdir, dstdir, outputs):
  unhandled = []
  for out in outputs:
    if os.path.exists(os.path.join(srcdir, out)):
      shutil.move(os.path.join(srcdir, out), dstdir)
    else:
      unhandled.append(out)
  search_and_mv_output_real(srcdir, dstdir, unhandled)


def search_and_mv_output_real(srcdir, dstdir, outputs):
  """Implements the search and move logic for outputs that need to be located.

  For each output in <outputs>, searches <output> within <srcdir>, and moves it
  to <dstdir>/<output>. There must be exactly one match.

  An error is thrown if there are multiple matches.
  """
  found = collections.defaultdict(list)
  for root, dirs, files in os.walk(srcdir):
    for f in files + dirs:
      if f in outputs:
        found[f].append(os.path.join(root, f))

  missing_error = lambda \
        out: f"In {os.path.realpath(srcdir)}, no files match {out}, expected 1"
  multiple_error = lambda out, matches: \
    f"In {os.path.realpath(srcdir)}, multiple files match '{out}', expected 1:\n  " + (
        "\n  ".join(matches))
  errors = []
  for out in outputs:
    num_matches = len(found[out])
    if num_matches == 0:
      errors.append(missing_error(out))
    elif num_matches > 1:
      errors.append(multiple_error(out, found[out]))
  if errors:
    raise Exception("\n".join(errors))

  for out in outputs:
    shutil.move(found[out][0], dstdir)


def main(srcdir, dstdir, outputs):
  """Locates and moves outputs matching multiple naming conventions.

  If <output> contains a slash:

    copy <srcdir>/<output> to <dstdir>/$(basename <output>)
    move <srcdir>/<output> to <dstdir>/<output>.

  If <output> does not contain a slash:
    If the file exists at the top level of <srcdir>, it is always chosen.
    Otherwise, searches <output> under <srcdir>, and
    move it to <dstdir>/<output>. There must be exactly one match. An error is
    thrown if there are multiple matches.
  """
  if not os.path.isdir(srcdir):
    raise Exception(f"srcdir {srcdir} is not a directory.")
  if not os.path.isdir(dstdir):
    raise Exception(f"dstdir {dstdir} is not a directory.")

  with_slash = [out for out in outputs if "/" in out]
  handle_outputs_with_slash(srcdir, dstdir, with_slash)

  without_slash = [out for out in outputs if "/" not in out]
  handle_outputs_without_slash(srcdir, dstdir, without_slash)


if __name__ == "__main__":
  parser = argparse.ArgumentParser(description=main.__doc__)
  parser.add_argument("--srcdir", required=True, help="source directory")
  parser.add_argument("--dstdir", required=True, help="destination directory")
  parser.add_argument(
      "outputs",
      nargs="+",
      metavar="output_file_name",
      help="A list of output file names. Must not contain slashes.")
  args = parser.parse_args()
  main(**vars(args))
