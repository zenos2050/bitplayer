#!/usr/bin/env bash
# Pushes this job's ci-logs/ folder to the branch ci-logs/<job> (one orphan
# commit, force-pushed) so build output can be read with plain git.
set -u
JOB="$1"
[ -d ci-logs ] || { echo "no logs"; exit 0; }
TMP=$(mktemp -d)
cp -R ci-logs/. "$TMP/"
{
  echo "job=$JOB"
  echo "sha=${GITHUB_SHA:-}"
  echo "run=${GITHUB_RUN_NUMBER:-}"
  echo "status=${JOB_STATUS:-unknown}"
  date -u
} > "$TMP/info.txt"
cd "$TMP"
git init -q -b logs
git config user.name "ci-bot"
git config user.email "ci-bot@users.noreply.github.com"
git add -A
git commit -qm "ci logs: $JOB run ${GITHUB_RUN_NUMBER:-?} (${GITHUB_SHA:-?})"
git push -q -f "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" "logs:refs/heads/ci-logs/$JOB" \
  && echo "Published logs to ci-logs/$JOB" || echo "Could not publish logs"
