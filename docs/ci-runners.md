# CI runners

The `test` workflow uses the Engine Box Linux pool for pushes and manual runs on
`main` when the repository Actions variable `ENGINEBOX_CI_ENABLED` is `true`.
Both Linux jobs use a fresh disposable VM in the organization's `enginebox-ci`
runner group. macOS and pull-request checks continue on GitHub-hosted runners.
The runner group permits only approved repositories and workflow refs, including
this repository's `.github/workflows/test.yml@refs/heads/main`.

The shared pool allows two concurrent jobs, each with 4 CPUs and 4 GiB RAM.
Jobs may queue while other projects use both slots. Each plugin job has a
ten-minute timeout; the pool's worker has a separate thirty-minute bound for
larger application suites. The disposable guest supports passwordless `sudo`.
There is no automatic failover for an already queued job.

To return future runs to GitHub-hosted Linux, set the repository variable
`ENGINEBOX_CI_ENABLED` to `false` under **Settings → Secrets and variables →
Actions → Variables**, cancel affected queued runs, and start a new run through
**Actions → test → Run workflow**. Restore `true` to enable Engine Box again.
The variable contains no secret. A run's job details identify its runner and
group; Engine Box's GitHub panel records allocation and cleanup status.
