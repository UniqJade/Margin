# Security policy

## Prototype boundary

Margin currently uses bring-your-own-key directly from locally built Apple clients. Although the key is stored with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and does not synchronize, a compromised client device can still expose client-held credentials.

Do not publish or distribute a binary, or operate this as a multi-user service, without replacing direct provider calls with an authenticated relay that owns provider credentials, enforces per-user quotas, validates requests, and supports key rotation and abuse response. Apple Development signing of the fixed personal copy does not change this prototype boundary.

## Secret handling

- Never commit API keys, signing keys, provisioning profiles, or populated secret configuration files.
- Use a separate restricted provider project/key for Margin and configure conservative spend alerts.
- Rotate a key immediately if it appears in a commit, log, screenshot, issue, crash report, or distributed build.
- Provider error bodies are intentionally mapped to local error cases rather than shown or logged.

## Reporting

Report vulnerabilities through
[GitHub private vulnerability reporting](https://github.com/UniqJade/Margin/security/advisories/new).
Do not open a public issue containing a vulnerability, API key, private book
excerpt, provider response, signing file, or populated local configuration.
