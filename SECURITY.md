# Security Policy

## Scope

Security reports are welcome for:

- unexpected privilege escalation
- unintended filesystem modification
- malicious or unexpected network behavior
- unsafe profile payloads
- command injection
- unsafe handling of user-controlled arguments
- UAF helper memory-safety or authorization issues

## Out of scope

Reports that Apple changes or removes private UAF APIs are compatibility
reports rather than security vulnerabilities, although they are still useful.

## Reporting

Please do not publish a potentially exploitable issue with detailed reproduction
steps in a public issue before the maintainer has had an opportunity to review it.

Use GitHub's private vulnerability reporting feature if it is enabled for the
repository. Otherwise, contact the repository maintainer privately.

Do not include personal data, credentials, or machine-specific secrets in a
report.
