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

## Secrets That Must Never Be Committed

This repo is public — every file is visible to anyone who clones, forks, or web-views it. The codebase ships sanitized by design. The following must never appear in any commit, issue body, PR, or discussion thread:

- **Discord webhook URLs** — any token of the form `https://discord.com/api/webhooks/<id>/<token>`
- **Real `~/.oracle-monitor/config` files** — only [`config.template`](https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/config.template) lives in the repo. The real config holds your webhook, `ORACLE_ID`, and `CLI` path and stays on your server.
- **`wallet.dat`** in any form, encrypted or not — and never any passphrase or mnemonic
- **API keys, RPC passwords** — none are needed by the tooling here
- **Private IP addresses** of operator infrastructure — placeholders only (`<YOUR_VPS_IP>`)
- **Operator real names**, home addresses, employer info, or other personal identifiers

If you accidentally commit a webhook URL to any public repo: **rotate the webhook in your Discord server first** (delete it server-side), then rewrite git history with `git filter-repo` or BFG and force-push. Deleting it from the latest commit alone is not enough — GitHub indexes history.

Before pushing, I run leak sweeps on anything destined for this repo:

```bash
# Webhook leak sweep — must return ZERO:
grep -nE 'discord\.com/api/webhooks/[0-9]' <file>

# Personal-info sweep — must return ZERO:
grep -inE 'sask|saskatchewan|baumg|kevin|<my_real_ip>' <file>
```

## Supported Versions

I maintain the latest version of all files on the `main` branch. There are no older supported versions — always use the latest.

— digibyte-maxi (Oracle Slot 17)
