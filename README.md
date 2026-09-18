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
./backup-github.sh -o <user-or-org> [-d DIR] [-g] [-a] [-w WORKDIR]
```

| Flag | Description |
|------|-------------|
| `-o OWNER` | GitHub user or org login to back up (required) |
| `-d DIR`   | Destination directory (default: `./backups`) |
| `-g`       | Also back up the owner's gists |
| `-a`       | Create a timestamped `.tar.gz` archive and prune archives older than 30 days. See below for what this does to `-d`. |
| `-w DIR`   | Local working directory for the git mirrors when `-a` is used (default: `~/.cache/github-backup`) |
| `-h`       | Show help |

### `-a` and a remote/network `-d`

Without `-a`, `-d` holds the live `.git` mirrors directly, and reruns update
them in place — good for a local disk or external drive.

With `-a`, the mirrors are cloned/updated in `-w` (local, fast, persists
across runs) and only the compressed `.tar.gz` archive (plus a copy of the
run's log) is written to `-d`. This keeps a slow or remote `-d` (a network
share, NAS mount, etc.) from having to hold thousands of loose git objects —
it only ever receives the finished archive. Point `-w` at fast local disk and
`-d` at wherever you want the durable copy to land:

```sh
./backup-github.sh -o wmar-dev -w ~/github-mirrors -d /Volumes/Backups/github -a
```

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

### From a live mirror directory (no `-a`, or from `-w`)

```sh
git clone /path/to/backups/<owner>/repos/<repo-name>.git restored-repo
```

### From a `.tar.gz` archive (`-a`)

1. Extract the archive:

   ```sh
   tar -xzf wmar-dev-20260918-084938.tar.gz -C /path/to/extract
   ```

   This produces `/path/to/extract/repos/<repo-name>.git` (and
   `/path/to/extract/gists/<gist-id>.git` if gists were included) — the same
   bare mirrors as the non-archived layout.

2. Clone out the repo you need:

   ```sh
   git clone /path/to/extract/repos/<repo-name>.git restored-repo
   ```

Because these are mirrors, the clone comes back with every branch and tag
intact — not just the default branch.

To restore *everything* rather than one repo, skip step 2 and just keep the
extracted `repos/` directory; each `<name>.git` inside it is already a
complete bare repo, so `git clone` any (or all) of them as needed.

## Scheduling

To run automatically (e.g. nightly), add a cron or launchd job that calls
the script, for example via crontab:

```
0 2 * * * /Users/wmar/Developer/github-backup/backup-github.sh -o wmar-dev -w ~/github-mirrors -d /Volumes/Backups/github -g -a >> /Users/wmar/Developer/github-backup/cron.log 2>&1
```
