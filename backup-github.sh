#!/usr/bin/env bash
#
# backup-github.sh — mirror-clone (or update) every repo owned by a GitHub
# user or organization, optionally including gists, into local bare mirrors.
#
# Requires: gh (authenticated: `gh auth login`), git, jq
#
# Usage:
#   ./backup-github.sh -o wmar [-d ./backups] [-g] [-a] [-w WORKDIR]
#
# Options:
#   -o OWNER   GitHub user or org login to back up (required)
#   -d DIR     Destination directory (default: ./backups)
#   -g         Also back up the owner's gists
#   -a         Create a timestamped tar.gz archive and prune archives older
#              than 30 days. With -a, the git mirrors themselves are kept in
#              WORKDIR (local, for fast incremental updates) and only the
#              resulting .tar.gz (+ log) is written to DEST — so a remote/
#              network DEST only ever holds the compressed archive, not the
#              raw .git mirrors. Without -a, DEST holds the mirrors directly.
#   -w DIR     Local working directory for git mirrors when -a is used
#              (default: ~/.cache/github-backup)
#   -h         Show this help

set -euo pipefail

DEST="./backups"
WORKDIR="$HOME/.cache/github-backup"
INCLUDE_GISTS=0
MAKE_ARCHIVE=0
OWNER=""

usage() { sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while getopts ":o:d:w:gah" opt; do
  case "$opt" in
    o) OWNER="$OPTARG" ;;
    d) DEST="$OPTARG" ;;
    w) WORKDIR="$OPTARG" ;;
    g) INCLUDE_GISTS=1 ;;
    a) MAKE_ARCHIVE=1 ;;
    h) usage 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage 1 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage 1 ;;
  esac
done

[[ -z "$OWNER" ]] && { echo "Error: -o OWNER is required" >&2; usage 1; }

for bin in gh git jq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "Error: '$bin' is required but not installed" >&2; exit 1; }
done

gh auth status >/dev/null 2>&1 || { echo "Error: not authenticated. Run 'gh auth login' first." >&2; exit 1; }

# With -a, mirrors live locally in WORKDIR and only the archive goes to DEST
# (useful when DEST is a slow/remote mount). Without -a, DEST holds mirrors
# directly, as before.
if [[ "$MAKE_ARCHIVE" -eq 1 ]]; then
  BASE_DIR="$WORKDIR"
else
  BASE_DIR="$DEST"
fi

REPO_DIR="$BASE_DIR/$OWNER/repos"
GIST_DIR="$BASE_DIR/$OWNER/gists"
LOG_FILE="$BASE_DIR/$OWNER/backup-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$REPO_DIR"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

log "Starting backup of '$OWNER' into $BASE_DIR"

# --- Repos ------------------------------------------------------------
REPO_LIST_FILE="$(mktemp)"
gh repo list "$OWNER" --source --limit 1000 --json nameWithOwner \
  --jq '.[].nameWithOwner' >"$REPO_LIST_FILE" 2>/dev/null || true

repo_count=$(wc -l <"$REPO_LIST_FILE" | tr -d ' ')
log "Found ${repo_count:-0} repo(s)."

FAILED=()

while IFS= read -r name_with_owner; do
  [[ -z "$name_with_owner" ]] && continue
  repo_name="${name_with_owner#*/}"
  target="$REPO_DIR/$repo_name.git"
  url="https://github.com/$name_with_owner.git"

  if [[ -d "$target" ]]; then
    log "Updating $name_with_owner"
    if ! git --git-dir="$target" remote update --prune >>"$LOG_FILE" 2>&1; then
      log "  FAILED to update $name_with_owner"
      FAILED+=("$name_with_owner")
    fi
  else
    log "Cloning $name_with_owner"
    if ! git clone --mirror "$url" "$target" >>"$LOG_FILE" 2>&1; then
      log "  FAILED to clone $name_with_owner"
      FAILED+=("$name_with_owner")
      rm -rf "$target"
    fi
  fi
done <"$REPO_LIST_FILE"
rm -f "$REPO_LIST_FILE"

# --- Gists --------------------------------------------------------------
if [[ "$INCLUDE_GISTS" -eq 1 ]]; then
  mkdir -p "$GIST_DIR"
  GIST_LIST_FILE="$(mktemp)"
  gh api "users/$OWNER/gists" --paginate --jq '.[].id' >"$GIST_LIST_FILE" 2>/dev/null || true
  gist_count=$(wc -l <"$GIST_LIST_FILE" | tr -d ' ')
  log "Found ${gist_count:-0} gist(s)."
  while IFS= read -r gist_id; do
    [[ -z "$gist_id" ]] && continue
    target="$GIST_DIR/$gist_id.git"
    url="https://gist.github.com/$gist_id.git"
    if [[ -d "$target" ]]; then
      log "Updating gist $gist_id"
      git --git-dir="$target" remote update --prune >>"$LOG_FILE" 2>&1 || { log "  FAILED to update gist $gist_id"; FAILED+=("gist:$gist_id"); }
    else
      log "Cloning gist $gist_id"
      git clone --mirror "$url" "$target" >>"$LOG_FILE" 2>&1 || { log "  FAILED to clone gist $gist_id"; FAILED+=("gist:$gist_id"); rm -rf "$target"; }
    fi
  done <"$GIST_LIST_FILE"
  rm -f "$GIST_LIST_FILE"
fi

# --- Archive --------------------------------------------------------------
if [[ "$MAKE_ARCHIVE" -eq 1 ]]; then
  mkdir -p "$DEST"
  archive_name="$DEST/$OWNER-$(date +%Y%m%d-%H%M%S).tar.gz"
  log "Creating archive $archive_name (from local $BASE_DIR/$OWNER)"
  tar -czf "$archive_name" -C "$BASE_DIR/$OWNER" repos $([[ "$INCLUDE_GISTS" -eq 1 ]] && echo gists)
  find "$DEST" -maxdepth 1 -name "$OWNER-*.tar.gz" -mtime +30 -print -delete | while read -r f; do
    log "Pruned old archive $f"
  done
fi

if [[ ${#FAILED[@]} -gt 0 ]]; then
  log "Completed with ${#FAILED[@]} failure(s): ${FAILED[*]}"
  [[ "$MAKE_ARCHIVE" -eq 1 ]] && cp "$LOG_FILE" "$DEST/"
  exit 1
fi

log "Backup complete."
[[ "$MAKE_ARCHIVE" -eq 1 ]] && cp "$LOG_FILE" "$DEST/"
