# Opening the repository

The GitHub settings a maintainer applies once when the repository goes public, or to restore them on a new copy. The commands need a `gh` session with admin rights on the repository.

Each step gives its command and the check that proves it. Do not go on until the check passes.

1. Run the secret scan on the whole history.

   ```sh
   gitleaks git --log-opts="--all" --redact .
   ```

   Check: no leaks reported.

2. Flip the visibility.

   ```sh
   gh repo edit c4u-tech/c4u-telinhasegura-platform --visibility public --accept-visibility-change-consequences
   ```

   Check: `gh repo view --json visibility` returns `PUBLIC`.

3. Turn on the security settings: private vulnerability reporting, secret scanning and push protection.

   ```sh
   gh api -X PUT repos/c4u-tech/c4u-telinhasegura-platform/private-vulnerability-reporting
   gh api -X PATCH repos/c4u-tech/c4u-telinhasegura-platform -f 'security_and_analysis[secret_scanning][status]=enabled' -f 'security_and_analysis[secret_scanning_push_protection][status]=enabled'
   ```

   Check:

   ```sh
   gh api repos/c4u-tech/c4u-telinhasegura-platform --jq .security_and_analysis
   gh api repos/c4u-tech/c4u-telinhasegura-platform/private-vulnerability-reporting
   ```

   `secret_scanning.status` and `secret_scanning_push_protection.status` are `"enabled"`, and private vulnerability reporting returns `"enabled": true`.

4. Create the release GitHub App. A maintainer creates a GitHub App owned by the `c4u-tech` organization. It needs no webhook, and its repository permissions are Contents read/write and Pull requests read/write. Install it on this repository only. Then generate a private key and store the App's Client ID (shown on its settings page) and the key:

   ```sh
   gh variable set RELEASE_APP_CLIENT_ID --repo c4u-tech/c4u-telinhasegura-platform --body <client id>
   gh secret set RELEASE_APP_PRIVATE_KEY --repo c4u-tech/c4u-telinhasegura-platform < key.pem
   rm key.pem
   ```

   `release.yml` mints an installation token from them in both jobs, so the release and back-merge PRs start CI. Do not use a personal access token instead: its commits are not bot-authored, so `dco` would fail on them and `ci-ok` would block every release PR.

   Check: `gh variable list --repo c4u-tech/c4u-telinhasegura-platform` shows `RELEASE_APP_CLIENT_ID` and `gh secret list --repo c4u-tech/c4u-telinhasegura-platform` shows `RELEASE_APP_PRIVATE_KEY`.

5. Apply the rulesets. List them first, because POST is not idempotent: a second POST of the same ruleset fails or duplicates it. POST only the ones missing.

   ```sh
   gh api repos/c4u-tech/c4u-telinhasegura-platform/rulesets --jq '.[].name'
   gh api -X POST repos/c4u-tech/c4u-telinhasegura-platform/rulesets --input .github/rulesets/<branch>.json
   ```

   Run the POST for each of `dev`, `stg` and `prd` that the list lacks.

   Check: `gh api repos/c4u-tech/c4u-telinhasegura-platform/rulesets --jq '.[].name'` lists `dev`, `stg` and `prd`.

6. Keep the sign-offs in squash commits. The squashed commit then carries the PR commits' `Signed-off-by` trailers.

   ```sh
   gh api -X PATCH repos/c4u-tech/c4u-telinhasegura-platform -f squash_merge_commit_message=COMMIT_MESSAGES
   ```

   Check: `gh api repos/c4u-tech/c4u-telinhasegura-platform --jq .squash_merge_commit_message` returns `COMMIT_MESSAGES`.

7. Require a sign-off on commits made in GitHub's web editor.

   ```sh
   gh api -X PATCH repos/c4u-tech/c4u-telinhasegura-platform -F web_commit_signoff_required=true
   ```

   Check: `gh api repos/c4u-tech/c4u-telinhasegura-platform --jq .web_commit_signoff_required` returns `true`.

8. Make the default workflow token read-only and stop it approving pull requests. Every workflow declares its own permissions, so this changes no job; it keeps a future workflow without a `permissions` block from writing, and keeps any workflow from approving a PR.

   ```sh
   gh api -X PUT repos/c4u-tech/c4u-telinhasegura-platform/actions/permissions/workflow -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false
   ```

   Check: `gh api repos/c4u-tech/c4u-telinhasegura-platform/actions/permissions/workflow` returns `"default_workflow_permissions":"read"` and `"can_approve_pull_request_reviews":false`.
