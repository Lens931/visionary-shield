# Security policy

## Supported branch

The `main` branch is the active open-source branch.

## Reporting vulnerabilities

Please open a private security advisory on GitHub when possible, or contact the maintainer through the official project channels.

Do not publish exploit details publicly before the issue has been reviewed.

## Scope

Reports are welcome for:

- privilege escalation
- admin bypasses
- unsafe event exposure
- webhook leakage
- remote crash paths
- NUI focus or input issues that can disrupt gameplay
- screenshot/evidence flow failures

## Responsible disclosure

Please include:

- affected version or commit
- reproduction steps
- server context
- expected behavior
- actual behavior
- minimal proof of concept when safe

## Operational advice

- never commit real webhooks;
- limit admin identifiers;
- review third-party resources;
- test on staging before production;
- do not treat any anti-cheat as a single point of trust.
