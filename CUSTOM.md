# Downstream maintenance

`sakiori-oss/react-native-screens` is a downstream fork of
[react-native-screens](https://github.com/software-mansion/react-native-screens)
as T3 Code's mobile client takes it: it follows the branch of
[PixPMusic/react-native-screens](https://github.com/PixPMusic/react-native-screens)
that T3 Code's `5.0.0-t3.N` tarballs are built from. Sakiori's mobile client
installs the package from a tarball kept in its own repository and changes that
tarball only through this fork, never with a package-manager patch, which the
next tarball would drop without a trace. The fork carries its fixes in the
package's own code and sends nothing upstream; a downstream change is dropped
only when upstream fixes the same thing itself. This file holds the rules for
maintaining the fork that the repository itself does not show. What a change
does and why is in its commit.

## Downstream changes

- **iOS form sheets wait for a running transition.** UIKit drops a presentation
  or dismissal asked of a view controller that is still appearing or
  disappearing, without calling its completion, so a form sheet opened or
  closed during another transition, such as a sheet that follows a
  confirmation sheet or one being swiped away, never appeared or never went
  away. The presentation manager now asks again once that transition ends.
- **The tarball names this fork as its source.** `scripts/pack-t3.mjs` writes
  this repository into `t3-fork.json`; an update keeps that line.

## The tarball

The fork publishes no npm package and no releases. A consumer installs a
tarball built from a commit of `main`, which is never rewritten. The package
keeps upstream's `5.0.0-t3.N` version, which changes only with upstream
updates, so the file name carries the source commit instead:

1. Check out the commit of `main` to package, with nothing uncommitted.
2. With Node 24 and the repository's pinned Yarn, run
   `yarn pack:t3 <output directory>`. It installs the locked dependencies,
   builds the JavaScript and declarations, writes `t3-fork.json` with this
   repository, the source commit, the upstream base in `t3Fork.upstreamCommit`
   of `package.json` and the version, packs the package with `npm pack` and
   compresses it in one pass, so one commit always gives the same bytes. It
   prints the archive's SHA-256.
3. Rename the archive to
   `react-native-screens-<version>-<first eight characters of the commit>.tgz`,
   so each build has a distinct dependency path.

The merge request pipeline's `pack` job runs the same build on every change.

## Merging into `main`

`main` changes only through merge requests and is never force-pushed or
rewritten. The project merges by fast-forward, with _Squash commits_ ticked by
default.

- A downstream change is one merge request from a branch off `main`, carrying
  one logical change. It lands squashed, as the project ticks by default, as one
  commit on `main`, with the merge request's title as its subject and its
  description as its body, so the description says what changed and why. Do not
  squash or rewrite the branch by hand first. A merged branch is not reused.
- A downstream merge request lands through the merge queue: once it is ready, a
  Maintainer assigns it to the `sakiori-merge` service account
  (`glab mr update <id> --ready --assignee sakiori-merge`), keeping the
  project's squash default; only a Maintainer queues one, since the bot merges
  it as a Maintainer. The bot takes the queue one merge request at a time: it
  rebases each onto `main`, waits for its pipeline and merges it. Apart from the
  two kinds below, never merge a merge request yourself, set auto-merge on it,
  or rebase one that is queued: a merge outside the queue sends every queued
  merge request back to a new pipeline. When the bot cannot merge one, it
  assigns it back with a comment that says why; after a conflict, rebase it onto
  `main`, the only rewrite allowed, and assign it again.
- A merge request from a fork outside the group stays out of the queue, since
  GitLab runs its pipeline in this project only when a Maintainer starts it. The
  Maintainer holds the queue by unassigning the queued merge requests, runs the
  pipeline on the merge request rebased onto the current `main`, merges it
  squashed, and assigns the held ones again once the merge has landed.
- The upstream update's merge request, from `git-intake/update`, stays out of
  the queue too and lands **without squashing and without rebasing**: its merge
  commit carries upstream's history and the sync record git intake reads. git
  intake opens it with squashing off; leave it unticked. `git intake land`, with
  `GITLAB_TOKEN` holding a Maintainer's token with the `api` scope, brings it to
  `main`: it waits for its pipeline, and when `main` moved meanwhile it pauses
  the merge queue `.git-intake.toml` names, catches the update up and waits for
  the new pipeline; then it merges it and returns the paused merge requests in
  their order. `git intake land --resume` returns them after an interruption.

Verify a change against the current `main` before queuing it. A change to the
native code is also built and tried in the consuming app on the platform it
touches, since the pipeline builds no native code.

## Upstream updates

[git intake](https://gitlab.com/sakiori-oss/git-intake) takes upstream in,
configured in `.git-intake.toml`. The daily schedule's `git-intake-sync` job
opens the update's merge request, or catches an open one up with `main`. A
conflict fails the job; resolve it in a clone:

```bash
git intake sync       # meets the same conflict, in an update worktree
git intake continue   # after resolving and staging it
git intake verify     # optional: the install and checks of .git-intake.toml
git intake finish     # pushes the update to the merge request
```

Conflicts are expected in `ios/modals/form-sheet/` and in the repository line
of `scripts/pack-t3.mjs`. Resolve each on its merits, keeping what upstream's
change intends and what the downstream change guarantees. When upstream fixes a
defect a downstream change fixes, the update takes upstream's fix and drops the
downstream code.

The followed branch is the one that carries T3 Code's `t3-v5.0.0-t3.N` release
tags. When T3 Code's tarballs come from another branch, change `branch` in
`.git-intake.toml` on its own merge request; `git intake branches` lists the
upstream's branches.

The checks run the JavaScript steps of upstream's `.github/workflows/lint.yml`
and the tarball build. When an update changes those steps, the Node version
T3 Code's packaging names, or the packaging script, change `.git-intake.toml`
and `.gitlab-ci.yml`, with `NODE_IMAGE`, in the same update. Upstream's
`.github/` stays as upstream has it; it does not run on GitLab.

## Project settings

- Merge method _Fast-forward merge_; _Squash commits when merging_
  _Encourage_, never _Require_, which git intake refuses; squash commit template
  `%{title}`, a blank line, `%{description}`; _Pipelines must succeed_ on,
  _Skipped pipelines are considered successful_ off, automatic rebase and merge
  trains off.
- `main` protected: push No one, merge Maintainers, force push off. No rule
  matches `git-intake/update`, and merge request pipelines get no protected
  variables or runners.
- Pipeline variables allowed to no one.
- `GITLAB_TOKEN`: the group release bot's personal access token (`api`,
  `write_repository`), protected, masked and hidden, environment `git-intake`.
  Replace it before it expires.
- One daily pipeline schedule on `main`, owned by the release bot.

## Runners

Jobs run on the group's Linux runner (`sakiori-oss-linux`), which also runs the
update's merge request pipelines with upstream's code, so it is unprivileged
and holds no credentials. A merge request from a fork outside the group finds
no runner; a Maintainer runs its pipeline here.

The repository is MIT-licensed; keep upstream's `LICENSE` unchanged.
