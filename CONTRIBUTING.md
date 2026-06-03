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
- No real webhook URLs, IP addresses, or credentials in committed code

## What I'm Not Looking For

- Windows or macOS ports of the monitoring scripts (tracked separately as [#11](https://github.com/BaumerCrypto/digidollar-oracle-tools/issues/11))
- Features that require changes to DigiByte Core itself — those belong in [DigiByte-Core/digibyte](https://github.com/DigiByte-Core/digibyte)

## Contact

- **Gitter:** digibyte-maxi in [#digidollar:gitter.im](https://app.gitter.im/#/room/#digidollar:gitter.im)
- **X/Twitter:** [@BaumerCrypto2_0](https://x.com/BaumerCrypto2_0)
- **GitHub:** [@BaumerCrypto](https://github.com/BaumerCrypto)

— digibyte-maxi (Oracle Slot 17)
