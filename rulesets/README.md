# Rulesets

The branch rulesets of every repository in the LFDT-Paladin organization, as
JSON, read from GitHub on 2026-11-25. GitHub does not read these files; they
are kept here so that a change to branch protection can be reviewed in a pull
request and then applied with [`rules.zsh`](rules.zsh), which also reads
changes back out of GitHub into these files.

Each directory is named for a repository and holds one file per ruleset
defined on that repository. [`_org`](_org) holds the two organization
rulesets, which repositories inherit. No repository has classic branch
protection, so these files are the whole picture.

Fields GitHub adds on export (`id`, `source`, `source_type`, timestamps,
links) are left out, as are two `pull_request` parameters the API returns but
does not publish in its schema (`dismissal_restriction`,
`require_extra_approval_for_unattributed_changes`).

## Keeping the files and GitHub in step

```sh
rulesets/rules.zsh                         # compare every directory with GitHub
rulesets/rules.zsh paladin zeto            # compare only these
rulesets/rules.zsh --apply paladin         # write these files to GitHub
rulesets/rules.zsh --update-local          # write GitHub to these files
```

With no mode flag the script only reads. It prints one line per file: `same`,
`differs` (followed by a diff of live against the file) or `missing`, and
reports any live ruleset that has no file here.

`--apply` writes this directory to GitHub: it creates a missing ruleset and
updates a differing one. `--update-local` writes GitHub to this directory: it
updates a differing file, adds a file for a live ruleset that has none
(named after the ruleset, lower case, so check the name it picks) and, when no
directory arguments are given, adds a directory for a repository that has
grown rulesets of its own. Use it to record a change someone made in the web
UI, then describe the change in the tables below.

Rulesets are matched to files by the `name` field, so renaming a ruleset in a
file creates a new one rather than renaming the old. Neither mode deletes:
`--apply` leaves a live ruleset that has no file alone (`no file`), and
`--update-local` leaves a file whose ruleset is gone from GitHub alone
(`no live`). Delete those by hand.

A caller that cannot read bypass actors is shown an empty `bypass_actors` on
every ruleset, so a write in either direction could silently drop them. The
script skips any write that would empty a non-empty list and says so; use a
token that can read bypass actors, or pass `--allow-bypass-removal` when the
removal is meant. No ruleset here has a bypass actor today, so this should
stay quiet.

It needs `gh` and `jq`, and a token with admin on the repository (organization
owner for `_org`).

## Organization ([`_org`](_org))

| File | Ruleset | Applies to | Rules | Bypass |
| --- | --- | --- | --- | --- |
| [`dco.json`](_org/dco.json) | DCO, active | default branch of every repository | block deletion, block force pushes, required check `DCO` | none |
| [`clowarden.json`](_org/clowarden.json) | Clowarden, active | `governance` only, ref pattern `refs/heads/main/config.yaml` | block deletion, pull request with 0 approvals, required check `CLOWarden` | none |

The Clowarden ruleset's pattern names a ref, not a file: it matches a branch
called `main/config.yaml`, which does not exist, so today the ruleset matches
nothing. Protecting `config.yaml` on `main` would need either the ref
`refs/heads/main` here or a push ruleset with a file path restriction. It is
recorded as it stands.

## Repositories

Every repository inherits the DCO ruleset above, so each default branch
already has deletion and force pushes blocked and the `DCO` check required.
The tables list what each repository adds.

The `merge-queue` rulesets are all identical and all in `evaluate` mode: they
report what a merge queue would do without requiring one. Settings: rebase
merge, build up to 5 entries, merge 1 to 5 at a time after a wait of up to
5 minutes, all entries must be green, 60 minute check timeout.

No ruleset in any repository has a bypass actor.

### paladin

| File | Ruleset | Branches | Rules |
| --- | --- | --- | --- |
| [`default.json`](paladin/default.json) | default, active | default branch | block deletion and force pushes; pull request with 1 approval and code owner review, merge or rebase only; branch must be up to date (no named checks) |
| [`main.json`](paladin/main.json) | main, active | `main` | block deletion and force pushes; pull request with 1 approval and code owner review; required checks `DCO` and `build` |
| [`v1-develop.json`](paladin/v1-develop.json) | v1-develop, active | `v1-develop` | as `main`, and the branch must be up to date |
| [`java-sdk-main.json`](paladin/java-sdk-main.json) | java-sdk-main, active | `java-sdk-main` | as `main`, and the branch must be up to date |
| [`release-branches.json`](paladin/release-branches.json) | release-*, active | `release-*` | block deletion and force pushes; pull request with 1 approval and code owner review; branch must be up to date (no named checks) |
| [`merge-queue.json`](paladin/merge-queue.json) | merge-queue, evaluate | default branch | merge queue, see above |

`main` is the default branch, so `default`, `main` and the organization DCO
ruleset all apply to it, and GitHub enforces the strictest combination.
`default` requires the branch to be up to date before merging even though
`main` does not, and `default` leaves squash out of its allowed merge methods,
so squash is not available on `main`. The repository's own settings also have
squash merging turned off.

Every ruleset here except `default` skips its status checks when the branch
is created (`do_not_enforce_on_create`), so a new release branch can be
pushed directly.

### zeto

| File | Ruleset | Branches | Rules |
| --- | --- | --- | --- |
| [`main.json`](zeto/main.json) | main, active | `main` | block deletion and force pushes; pull request with 1 approval |
| [`merge-queue.json`](zeto/merge-queue.json) | merge-queue, evaluate | default branch | merge queue, see above |

### .github

| File | Ruleset | Branches | Rules |
| --- | --- | --- | --- |
| [`default.json`](.github/default.json) | default, active | default branch | block deletion and force pushes; pull request with 1 approval; branch must be up to date (no named checks) |

### smt

| File | Ruleset | Branches | Rules |
| --- | --- | --- | --- |
| [`merge-queue.json`](smt/merge-queue.json) | merge-queue, evaluate | default branch | merge queue, see above |

Nothing beyond the organization DCO ruleset is enforced: no pull request or
review is required to push to `main`.

### railgun

| File | Ruleset | Branches | Rules |
| --- | --- | --- | --- |
| [`merge-queue.json`](railgun/merge-queue.json) | merge-queue, evaluate | default branch | merge queue, see above |

As `smt`: only the organization DCO ruleset is enforced.

### governance

No rulesets of its own, so there is no `governance` directory. The
organization DCO ruleset applies to `main`. The Clowarden ruleset targets this
repository but, as noted above, matches no branch.

## Required checks

Required status checks are pinned to the app that must report them:

| Check | `integration_id` | App |
| --- | --- | --- |
| `DCO` | 974774 | `dco-2` |
| `CLOWarden` | 306394 | `clowarden` |
| `build` | 15368 | `github-actions` |
