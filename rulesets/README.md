# Rulesets

The branch rulesets of every repository in the LFDT-Paladin organization, as
JSON, read from GitHub on 2026-11-25. GitHub does not read these files; they
are kept here so that a change to branch protection can be reviewed in a pull
request and then applied with [`apply.zsh`](apply.zsh).

Each directory is named for a repository and holds one file per ruleset
defined on that repository. [`_org`](_org) holds the two organization
rulesets, which repositories inherit. No repository has classic branch
protection, so these files are the whole picture.

Fields GitHub adds on export (`id`, `source`, `source_type`, timestamps,
links) are left out, as are two `pull_request` parameters the API returns but
does not publish in its schema (`dismissal_restriction`,
`require_extra_approval_for_unattributed_changes`).

## Applying

```sh
rulesets/apply.zsh                  # compare every directory with GitHub
rulesets/apply.zsh paladin zeto     # compare only these
rulesets/apply.zsh --apply paladin  # write the differences
```

Without `--apply` the script only reads. It prints one line per file: `same`,
`differs` (followed by a diff of live against the file) or `missing`. With
`--apply` it creates missing rulesets and updates differing ones. Rulesets are
matched to files by the `name` field, so renaming a ruleset in a file creates
a new one rather than renaming the old. A live ruleset that has no file is
reported as `no file` and left alone; the script never deletes.

It needs `gh` and `jq`, and a token with admin on the repository (organization
owner for `_org`).

To add a ruleset, write a new JSON file in the repository's directory. To
record a change made in the web UI, export the ruleset there (or
`gh api repos/LFDT-Paladin/<repo>/rulesets/<id>`), replace the file, and check
that `apply.zsh` reports `same`.

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
