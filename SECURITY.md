# Security Policy

## Reporting a Vulnerability

If you find a security vulnerability in any script or guide in this repo, **please do not open a public issue.** Instead, contact me directly:

- **Email:** Report via [GitHub private vulnerability reporting](https://github.com/BaumerCrypto/digidollar-oracle-tools/security/advisories/new)
- **Gitter DM:** digibyte-maxi in [#digidollar:gitter.im](https://app.gitter.im/#/room/#digidollar:gitter.im)

I'll acknowledge your report within 48 hours and work with you on a fix before any public disclosure.

## Scope

This policy covers:

- `oracle-monitor.sh` — health monitoring script
- `ORACLE_HARDENING_GUIDE.md` — security hardening guide
- Any other scripts or configuration examples in this repo

This policy does **not** cover:

- DigiByte Core software — report those to [DigiByte-Core/digibyte](https://github.com/DigiByte-Core/digibyte)
- The DigiDollar protocol itself — report those to the DigiByte Core team

## What Counts as a Vulnerability

- A script that leaks credentials, wallet data, or private keys
- Hardening guide advice that weakens security instead of strengthening it
- Commands or configurations that could cause unintended exposure of oracle infrastructure
- Webhook URLs, IP addresses, or other sensitive data accidentally committed

## Supported Versions

I maintain the latest version of all files on the `main` branch. There are no older supported versions — always use the latest.

— digibyte-maxi (Oracle Slot 17)
