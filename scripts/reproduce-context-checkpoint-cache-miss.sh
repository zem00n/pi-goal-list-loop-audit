#!/usr/bin/env bash
set -euo pipefail

# End-to-end reproduction for goal-event checkpoint projection cache misses.
#
# Requirements:
#   - pi on PATH
#   - shell-use on PATH
#   - authenticated github-copilot access to gpt-5.6-luna
#   - the repository checkout containing this script
#
# This intentionally runs a real LLM session. Keep the objective small and stop
# the session after the first or second visible cache-miss banner.

projection=${1:-true}
model=${PI_REPRO_MODEL:-github-copilot/gpt-5.6-luna}
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
run_id="glla-repro-$(date +%s)"
workspace="${TMPDIR:-/tmp}/${run_id}"
shell_session="${run_id}"
cast_path="${repo_root}/${run_id}.cast"

case "$projection" in
  true|false) ;;
  *) echo "usage: $0 [true|false]" >&2; exit 2 ;;
esac

cleanup() {
  shell-use --session "$shell_session" signal INT >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

mkdir -p "$workspace/.pi-glla"
cd "$workspace"
git init -q
git config user.email repro@example.invalid
git config user.name glla-repro
echo "# goal-list-loop-audit cache reproduction" > README.md
git add README.md
git commit -qm init

cat > "$workspace/.pi-glla/settings.json" <<EOF
{
  "contextCheckpointProjection": $projection
}
EOF

shell-use --session "$shell_session" open --cwd "$workspace" --cols 220 --rows 50 >/dev/null
shell-use --session "$shell_session" submit \
  "pi --no-extensions -e '$repo_root/extensions/loops/goal.ts' --model '$model' --name '$run_id'" >/dev/null

# Pi may need one extra submit while the extension finishes loading.
sleep 2
goal='/goal start "Create files a.txt, b.txt, c.txt in this repo, one per turn, each containing only its own filename as text, then commit each with git. Done when: all three files exist with correct contents and are committed."'
shell-use --session "$shell_session" submit "$goal" >/dev/null
sleep 3
shell-use --session "$shell_session" submit "$goal" >/dev/null 2>&1 || true

cat <<EOF
Interactive reproduction started.
  projection: $projection
  model:      $model
  workspace:  $workspace
  session:    $shell_session

Watch the pane and stop it after the first or second cache-miss banner:
  shell-use --session $shell_session text --full
  shell-use --session $shell_session signal INT

The recording will be saved to:
  $cast_path
EOF

# Allow a few continuation ticks, then stop automatically as a cost guard.
sleep "${PI_REPRO_SECONDS:-75}"
shell-use --session "$shell_session" signal INT >/dev/null 2>&1 || true
shell-use --session "$shell_session" get-recording > "$cast_path"
echo "Saved recording: $cast_path"
