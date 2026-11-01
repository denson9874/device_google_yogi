#!/usr/bin/env bash
# Apply the yogi patches to an Evolution X cnb checkout (idempotent).
#   apply-patches.sh [evolution-top]
# Same convention as ExpressiveOS evolution-husky/apply.sh:
# patches/<project_path_with_underscores>/*.patch
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
top="$(cd "${1:-$here/../../..}" && pwd)"
failed=()
for dir in "$here"/patches/*/; do
    [[ -d "$dir" ]] || continue
    project="$(basename "$dir")"            # e.g. build_make
    path="$top/${project//_//}"             # -> build/make
    for patch in "$dir"*.patch; do
        # Subjects longer than ~70 chars are folded onto continuation lines.
        subject="$(awk '/^Subject: /{s=substr($0,10); while ((getline l) > 0 && l ~ /^ /) s = s l; print s; exit}' "$patch" | sed 's/^\[PATCH[^]]*\] //')"
        # Not grep -q: exiting at the first match would kill git log with SIGPIPE, and with
        # pipefail the check would then fail for patches near the top of the log.
        # The reverse check catches a patch that's in the code but not in the log: picked
        # under another subject, or a shallow clone (repo init --depth=1).
        if git -C "$path" log --format=%s | grep -xF "$subject" >/dev/null ||
                git -C "$path" apply --reverse --check "$patch" 2>/dev/null; then
            echo "already applied: $project: $subject"
        # --keep-cr: some SystemUI sources have CRLF line endings, and git am would strip
        # the CRs from the patch's context lines.
        elif git -C "$path" am -q --3way --keep-cr "$patch"; then
            echo "applied: $project: $subject"
        else
            # Don't leave the project in the middle of git am, and go on with the rest.
            git -C "$path" am --abort
            echo "NOT APPLIED: $project: $subject"
            failed+=("$project: $subject")
        fi
    done
done
if (( ${#failed[@]} )); then
    echo "These patches don't apply to this tree and were skipped:"
    printf '  %s\n' "${failed[@]}"
    exit 1
fi
