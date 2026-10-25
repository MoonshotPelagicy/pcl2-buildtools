# PCL2 Build Tools

This repository builds a patched release from the latest stable Release of [`Meloong-Git/PCL`](https://github.com/Meloong-Git/PCL).

The scheduled workflow runs once a day. It also supports `workflow_dispatch` for a manual check. It reads the latest Release from the upstream repository and the latest Release from this repository. A build starts only when this repository does not already have the generated tag `pcl-<upstream-tag>-patched` as its latest Release.

The workflow then checks out the exact upstream tag, including submodules, and applies these build-time changes:

- `RestrictMcDownload = True` becomes `RestrictMcDownload = False`.
- The existing environment-variable reads for `PCL_MS_CLIENT_ID` and `PCL_CURSEFORGE_API_KEY` remain in the source, with the repository secrets used as their build-time fallbacks.
- `CommitHash` is filled with the checked-out upstream commit, as in the upstream build workflow.

Each target is required to occur exactly once. If upstream changes the surrounding source so that a target is missing or ambiguous, the patch step fails before restore, compilation, or Release publication.

## Repository secrets

Add these two **repository secrets** under **Settings → Secrets and variables → Actions**:

| Secret | Value |
| --- | --- |
| `CLIENT_ID` | The Application (client) ID from a Microsoft Entra / Azure App Registration |
| `CURSEFORGE_API_KEY` | Your CurseForge API key, usually beginning with `$2a$10$` |

For `CLIENT_ID`, create an app registration that supports personal Microsoft accounts, then enable **Allow public client flows** under the authentication settings. The value needed by the workflow is the **Application (client) ID**; no client secret is required for the public-client/device-code login flow.

For CurseForge, create or copy the API key from your CurseForge account. Paste it directly into the GitHub secret field. If you ever put that value in a local PowerShell command, use a single-quoted string because `$2a$10$...` is otherwise interpreted as PowerShell syntax.

The CurseForge key is compiled into the published launcher because the upstream source uses a compile-time fallback. Treat the published binary as containing that credential and rotate the key if the release is exposed beyond the intended audience.

## Running it

1. Add the two secrets.
2. Ensure Actions has write permission for repository contents. The workflow requests `contents: write` so it can create Releases.
3. Run **Actions → Build patched PCL release → Run workflow** once to test it.
4. Later upstream Releases will be detected by the scheduled run.

The generated Release contains a zip of the Release build output and is tagged `pcl-<upstream-tag>-patched`.
