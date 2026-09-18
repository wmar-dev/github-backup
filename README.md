# github-backup

Mirror-clones every repository (and optionally every gist) owned by a
GitHub user or organization into local bare mirrors, so you have a full,
offline backup of your GitHub-hosted git history.

## Requirements

- [`gh`](https://cli.github.com/) (GitHub CLI), authenticated via `gh auth login`
- `git`
- `jq`

Tested against the macOS system shell (bash 3.2) — no dependency on a
newer bash.

## Usage

```sh
./backup-github.sh -o <user-or-org> [-d DIR] [-g] [-a]
```

| Flag | Description |
|------|-------------|
| `-o OWNER` | GitHub user or org login to back up (required) |
| `-d DIR`   | Destination directory (default: `./backups`) |
| `-g`       | Also back up the owner's gists |
| `-a`       | Create a timestamped `.tar.gz` archive of the backup afterward, and prune archives older than 30 days |
| `-h`       | Show help |

### Examples

Back up all repos owned by `wmar-dev`:

```sh
./backup-github.sh -o wmar-dev
```

Back up repos and gists, then archive:

```sh
./backup-github.sh -o wmar-dev -g -a
```

Back up into a custom location (e.g. an external drive):

```sh
./backup-github.sh -o wmar-dev -d /Volumes/Backups/github
```

## How it works

- Lists repos with `gh repo list <owner> --source` (only repos the owner
  actually owns, not forks) and gists with `gh api users/<owner>/gists`.
- Each repo/gist is cloned with `git clone --mirror`, which captures all
  branches, tags, and refs — not just the default branch.
- On subsequent runs, existing mirrors are updated in place with
  `git remote update --prune` instead of being re-cloned, so backups are
  fast and idempotent.
- Progress and errors are logged to `<DIR>/<owner>/backup-<timestamp>.log`.
  The script exits non-zero if any repo/gist failed.

## Output layout

```
backups/
  <owner>/
    repos/
      <repo-name>.git/       # bare mirror
      ...
    gists/                   # only with -g
      <gist-id>.git/
    backup-YYYYMMDD-HHMMSS.log
  <owner>-YYYYMMDD-HHMMSS.tar.gz   # only with -a
```

## Restoring a repo

```sh
git clone /path/to/backups/<owner>/repos/<repo-name>.git restored-repo
```

Because these are mirrors, the clone comes back with every branch and tag
intact.

## Scheduling

To run automatically (e.g. nightly), add a cron or launchd job that calls
the script, for example via crontab:

```
0 2 * * * /Users/wmar/Developer/github-backup/backup-github.sh -o wmar-dev -d /Users/wmar/Developer/github-backup/backups -g -a >> /Users/wmar/Developer/github-backup/cron.log 2>&1
```
