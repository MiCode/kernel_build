#!/usr/bin/env python3

import argparse
import base64
import io
import os

MAGIC = "<!--RESOURCE_EMBED_HINT-->\n"


def main(infile, outfile, resources):
    """Embed resources into infile at the line `<!--RESOURCE_EMBED_HINT-->`."""
    inlines = infile.readlines()
    magic = inlines.index(MAGIC)

    outlines = inlines[:magic + 1]
    for resource_name in resources:
        outlines.append('<div hidden id="{}">\n'.format(os.path.basename(resource_name)))
        with open(resource_name, 'rb') as resource:
            # Resources needs to be base64 encoded. For example, the resource file may be in
            # markdown format:
            #    `<name>`
            # However, this is not valid HTML. So it cannot be embedded in the HTML file directly.
            # The HTML renderer converts it to
            #    <code><name></code>
            # This is valid HTML. See index.html.
            outlines.append(base64.b64encode(resource.read()).decode())
        outlines.append('</div>\n')
    outlines += inlines[magic + 1:]

    outfile.writelines(outlines)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=main.__doc__)
    parser.add_argument("--infile", required=True, type=argparse.FileType('r'), help="input file")
    parser.add_argument("--outfile", required=True, type=argparse.FileType('w'), help="output file")
    parser.add_argument("--resources", nargs='*', help="resource files")
    args = parser.parse_args()
    main(**vars(args))
