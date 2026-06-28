#!/bin/bash
#
# proj_obtain.sh: obtain the QSOE components matching this tree's release tag.
#
# Determines the latest tag of the umbrella repository (os.git), looks up
# the section named after that tag in component.list ("[<tag>]" header,
# followed by one "<name> <version>" line per component; '#' comments and
# blank lines ignored), and clones every component listed there, detached
# at its v<version> tag.  Components whose directories already exist are
# skipped.  Stops with an error when component.list has no section for
# the tag: a release tag on os.git must always declare the component
# versions guaranteed to work with it.
#
# Copyright (c) 2026 Yuri Zaporozhets <yuriz@qsoe.net>
# SPDX-License-Identifier: Apache-2.0

set -e

COMPONENT_LIST=component.list
REMOTE_BASE=https://gitlab.com/qsoe

# The script lives in the umbrella root; operate there regardless of
# the directory it was invoked from.
cd "$(dirname "$0")"

tag=$(git describe --tags --abbrev=0 2>/dev/null) || {
    echo "$0: error: cannot determine the umbrella release tag (repository not tagged?)" >&2
    echo -n "Enter the version you want to build (in this form: vX.Y), or Ctrl-C to exit: "
    read tag
    [[ $tag ]] || exit 1
}
echo "==> umbrella release tag: $tag"

in_section=0
section_found=0
while read -r comp ver _rest; do
    case "$comp" in
        '' | \#*)
            continue
            ;;
        \[*\])
            # Section header: enter it when it names our tag, leave otherwise.
            if [ "$comp" = "[$tag]" ]; then
                in_section=1
                section_found=1
            else
                in_section=0
            fi
            continue
            ;;
    esac
    [ "$in_section" -eq 1 ] || continue
    if [ -z "$ver" ]; then
        echo "$0: error: malformed line '$comp' in section [$tag] of $COMPONENT_LIST" >&2
        exit 1
    fi
    if [ -d "$comp" ]; then
        echo "==> $comp: present, fetching latest changes and checking out v$ver"
        git -C "$comp" fetch origin
        git -C "$comp" checkout --force "v$ver"
        git -C "$comp" reset --hard "v$ver"
        git -C "$comp" clean -fd
    else
        echo "==> $comp: cloning + switching to v$ver"
        git clone "$REMOTE_BASE/$comp.git"
        ( cd "$comp" && git checkout "v$ver" )
    fi
done < "$COMPONENT_LIST"

if [ "$section_found" -eq 0 ]; then
    echo "$0: error: no [$tag] section in $COMPONENT_LIST" >&2
    exit 1
fi
