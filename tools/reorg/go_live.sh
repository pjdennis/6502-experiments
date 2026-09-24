#!/bin/bash
# Go-live for the 2026-09 reorganization (docs/REORGANIZATION_PLAN.md).
#
#   tools/reorg/go_live.sh            dry run: check preconditions, print every step
#   tools/reorg/go_live.sh --apply    perform the steps
#
# Steps: tag every branch tip as archive/<branch>; add the milestone tags
# (tools/reorg/milestones.txt) and reorg/before + reorg/after; push the tags;
# fast-forward main to the trial branch; delete every other branch (each one is
# now reachable from main or from its archive tag). The trial branch is kept.
# Never force-pushes: main only moves if it is an ancestor of the trial branch.
set -euo pipefail

REMOTE=${REMOTE:-origin}
TRIAL_BRANCH=${TRIAL_BRANCH:-claude/repo-org-restructure-plan-e0got9}
MILESTONES=${MILESTONES:-$(cd "$(dirname "$0")" && pwd)/milestones.txt}
REORG_BEFORE=${REORG_BEFORE:-dd0cf45d773c9c48bd5ae6d01630d10ffbf210bf}  # claude/pld-hardware-memory-map-3hslxb tip
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

run() { echo "+ $*"; if [ "$APPLY" = 1 ]; then "$@"; fi; }
die() { echo "error: $*" >&2; exit 1; }

[ "$APPLY" = 1 ] || echo "DRY RUN: nothing will change. Re-run with --apply to perform these steps."

git fetch -q "$REMOTE" --prune
if [ "$(git rev-parse --is-shallow-repository)" = true ]; then git fetch -q --unshallow "$REMOTE"; fi

TRIAL=$(git rev-parse --verify "refs/remotes/$REMOTE/$TRIAL_BRANCH^{commit}") || die "no branch $REMOTE/$TRIAL_BRANCH"
MAIN=$(git rev-parse --verify "refs/remotes/$REMOTE/main^{commit}") || die "no branch $REMOTE/main"
git merge-base --is-ancestor "$MAIN" "$TRIAL" \
    || die "$REMOTE/main is not an ancestor of $TRIAL_BRANCH; merge main into the trial branch first"
echo "trial branch $TRIAL_BRANCH at $TRIAL; main at $MAIN (fast-forward ok)"

TAG_REFS=()
add_tag() {  # name commit message
    local name=$1 commit=$2 msg=$3 existing
    git cat-file -e "$commit^{commit}" 2>/dev/null || die "tag $name: commit $commit not found"
    if existing=$(git rev-parse -q --verify "refs/tags/$name^{commit}"); then
        [ "$existing" = "$(git rev-parse "$commit^{commit}")" ] || die "tag $name already exists at another commit"
        echo "  (tag $name already exists)"
    else
        run git tag -a "$name" "$commit" -m "$msg"
    fi
    TAG_REFS+=("refs/tags/$name")
}

echo "== 1. archive tags for every branch tip"
BRANCHES=()
while read -r ref; do
    b=${ref#refs/remotes/$REMOTE/}
    [ "$b" = HEAD ] && continue
    [ "$b" = "$TRIAL_BRANCH" ] && continue
    BRANCHES+=("$b")
    add_tag "archive/$b" "$ref" "Tip of branch $b before the 2026-09 reorganization"
done < <(git for-each-ref --format='%(refname)' "refs/remotes/$REMOTE")

echo "== 2. milestone tags"
while read -r name commit msg; do
    case "$name" in ''|'#'*) continue ;; esac
    add_tag "$name" "$commit" "$msg"
done < "$MILESTONES"
add_tag reorg/before "$REORG_BEFORE" "State before the 2026-09 reorganization"
add_tag reorg/after "$TRIAL" "The 2026-09 reorganization (trial branch $TRIAL_BRANCH)"

echo "== 3. push tags"
run git push "$REMOTE" "${TAG_REFS[@]}"

echo "== 4. fast-forward main"
run git push "$REMOTE" "$TRIAL:refs/heads/main"

echo "== 5. delete branches now covered by main or an archive tag"
for b in "${BRANCHES[@]}"; do
    [ "$b" = main ] && continue
    run git push "$REMOTE" --delete "$b"
done

[ "$APPLY" = 1 ] && echo "done." || echo "DRY RUN complete."
