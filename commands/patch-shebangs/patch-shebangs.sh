#!/bin/bash -e

patchShebang()
{
    local f="$1"
    local oldPath
    local newPath
    local arg0
    local args
    local oldInterpreterLine
    local newInterpreterLine

    if [ "$(head -1 "$f" | head -c+2)" != '#!' ]; then
        # missing shebang => not a script
        continue
    fi

    oldInterpreterLine=$(head -1 "$f" | tail -c+3)
    read -r oldPath arg0 args <<< "$oldInterpreterLine"

    if $(echo "$oldPath" | grep -q "/bin/env$"); then
        # Check for unsupported 'env' functionality:
        # - options: something starting with a '-'
        # - environment variables: foo=bar
        if $(echo "$arg0" | grep -q -- "^-.*\|.*=.*"); then
            echo "unsupported interpreter directive \"$oldInterpreterLine\" (set dontPatchShebangs=1 and handle shebang patching yourself)"
            exit 1
        fi
        newPath="$(command -v "$arg0" || true)"
    else
        if [ "$oldPath" = "" ]; then
            # If no interpreter is specified linux will use /bin/sh. Set
            # oldpath="/bin/sh" so that we get /nix/store/.../sh.
            oldPath="/bin/sh"
        fi
        newPath="$(command -v "$(basename "$oldPath")" || true)"
        args="$arg0 $args"
    fi

    # Strip trailing whitespace introduced when no arguments are present
    newInterpreterLine="$(echo "$newPath $args" | sed 's/[[:space:]]*$//')"

    if [ -n "$oldPath" -a "${oldPath:0:${#NIX_STORE}}" != "$NIX_STORE" ]; then
        if [ -n "$newPath" -a "$newPath" != "$oldPath" ]; then
            echo "$f: interpreter directive changed from \"$oldInterpreterLine\" to \"$newInterpreterLine\""
            # escape the escape chars so that sed doesn't interpret them
            escapedInterpreterLine=$(echo "$newInterpreterLine" | sed 's|\\|\\\\|g')
            # Preserve times, see: https://github.com/NixOS/nixpkgs/pull/33281
            touch -r "$f" "$f.timestamp"
            sed -i -e "1 s|.*|#\!$escapedInterpreterLine|" "$f"
            touch -r "$f.timestamp" "$f"
            rm "$f.timestamp"
        fi
    fi
}

target="$1"

if [ "$target" = "" ]
then
    echo "No target provided!"
    exit 1
elif [ -f "$target" ]
then
    patchShebang "$target"
elif [ -d "$target" ]
then
    echo "patching script interpreter paths in $target"

    find "$target" -type f -perm -0100 | while read f; do
        patchShebang "$f"
    done
fi
