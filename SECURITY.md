# Security policy

## Supported versions

We fix vulnerabilities only in the latest release of each component
(`app-v*` and `backend-v*`) and in `dev`.

## Reporting a vulnerability

Never report a vulnerability in a public issue. Use GitHub private
vulnerability reporting:
[report a vulnerability](https://github.com/c4u-tech/c4u-telinhasegura-platform/security/advisories/new).

Include the steps to reproduce, the impact and the affected version.

We aim to acknowledge your report within 5 business days and triage it
within 10.
We then agree a disclosure date with you: 90 days by default, sooner once a
fix ships.

## Scope

The API, the app, the web app, and the CI and release workflows.

**Child safety is in scope and has top priority.** We want to hear about:

- leaving kid mode without the guardian PIN;
- playing a video that is not in the curated catalogue;
- reaching another family's data;
- any leak of a minor's data (nickname, avatar, age band, viewing history);
- breaking the guardian's session or account protections.

## Out of scope

- A video you find unsuitable. That is not a vulnerability: report it in
  the app, so the community reviews it again.
- Findings that need a rooted or jailbroken device the attacker controls.
- Volumetric denial of service.
- Missing headers without a demonstrated impact.
- Third-party services (YouTube, the app stores).

## Safe harbour

Research in good faith within this policy is welcome, and we will not
pursue it. Do not access other people's data beyond what proves the issue,
do not degrade the service, and use your own test accounts.
