# Contributing

Thanks for your interest in contributing to digidollar-oracle-tools. I built this repo to share the monitoring and security tools I use on my own DigiDollar oracle node. Contributions that help other operators are welcome.

## How to Contribute

### Reporting Bugs

If something in the scripts or guides doesn't work as documented, open an [issue](https://github.com/BaumerCrypto/digidollar-oracle-tools/issues) with:

- What you were trying to do
- What happened instead
- Your OS and version (e.g., Ubuntu 24.04 LTS)
- Any relevant terminal output or error messages

### Suggesting Features

I track planned features as GitHub issues with the `enhancement` label. Check the [open issues](https://github.com/BaumerCrypto/digidollar-oracle-tools/issues?q=is%3Aissue+state%3Aopen+label%3Aenhancement) to see what's already on the roadmap before opening a new one.

If you have an idea that's not listed, open an issue describing:

- What the feature does
- Why it's useful for oracle operators
- Any implementation ideas (optional)

### Submitting Changes

1. Fork the repo
2. Create a branch for your change
3. Test your changes on a live or test environment
4. Submit a pull request with a clear description of what you changed and why

I'll review PRs as time allows. For large changes, open an issue first to discuss the approach before putting in the work.

### Documentation Fixes

Typos, unclear instructions, missing steps — if you spot something in the guides that could be better, PRs for documentation fixes are always welcome. No issue needed for small fixes.

## Code Style

- Shell scripts: Bash, `#!/bin/bash`, descriptive variable names, comments where intent isn't obvious
- Guides/docs: Markdown, first-person voice, step-by-step with verification commands
- UTF-8 encoding, Unix (LF) line endings — not CRLF
- `bash -n <file>` clean before commit
- No real webhook URLs, IP addresses, or credentials in committed code

## Sanitization Rule — Two Copies By Design

Every script in this repo exists in two places with different contents **by design**:

- **Private (deployed)** — on your oracle server. Real Discord webhook URL, real `ORACLE_ID`, real paths.
- **Public (this repo + your local fork)** — sanitized. Placeholders, no webhooks, no operator-specific values. The webhook and operator settings live in `~/.oracle-monitor/config` on your server — a separate file the script reads at startup. Only [`config.template`](https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/config.template) lives in the repo.

These two copies must stay diverged. The cardinal sin is blind-copying one to the other — pasting public over deployed breaks your monitor (placeholders don't resolve), and pasting deployed over public leaks your secrets to anyone who clones the repo.

Before any push to a public repo (this one or your fork), run leak sweeps:

```bash
# Webhook leak — must return ZERO:
grep -nE 'discord\.com/api/webhooks/[0-9]' <your_changed_files>

# Real config file — must not be staged (only config.template belongs):
git status | grep -E 'config$' | grep -v 'config\.template'
```

If either returns a hit, fix before committing. See [`SECURITY.md`](https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/SECURITY.md) for the full list of things that must never be committed and what to do if you accidentally leak one.

## Attribution — MMFP Solutions

GSS (GoSlimStratum) and GSSM (GoSlimStratum Miners Manager) are Scott's software from [MMFP Solutions](https://mmfpsolutions.com/). The cron + bash + Discord-webhook monitoring pattern in this repo is influenced by his work. If you add docs that reference GSS or GSSM, link the first mention to https://mmfpsolutions.com/.

## What I'm Not Looking For

- Windows or macOS ports of the monitoring scripts (tracked separately as [#11](https://github.com/BaumerCrypto/digidollar-oracle-tools/issues/11))
- Features that require changes to DigiByte Core itself — those belong in [DigiByte-Core/digibyte](https://github.com/DigiByte-Core/digibyte)

## Contact

- **Gitter:** digibyte-maxi in [#digidollar:gitter.im](https://app.gitter.im/#/room/#digidollar:gitter.im)
- **X/Twitter:** [@BaumerCrypto2_0](https://x.com/BaumerCrypto2_0)
- **GitHub:** [@BaumerCrypto](https://github.com/BaumerCrypto)

— digibyte-maxi (Oracle Slot 17)
