# digidollar-oracle-tools

Operator tools and monitoring scripts for [DigiByte](https://www.digibyte.org/) DigiDollar Oracle nodes.

Maintained by **digibyte-maxi** (Oracle Slot 17) — see contact at the bottom.

---

## What's in this repo

| File | Purpose |
|------|---------|
| [oracle-monitor.sh](oracle-monitor.sh) | Bash health monitor v2.0 — 12 checks (daemon, oracle, chain sync, peers, consensus price, disk, memory, services, version, NTP, quorum margin). Quorum tracking via `getdigidollardeploymentinfo` + `getoracles` with MuSig2 session health. Discord webhook alerts with red/yellow/green embeds. External config file, `--dry-run` mode, jq-based JSON parsing. State files prevent repeat alerts. |
| [config.template](config.template) | Configuration template for oracle-monitor.sh. Copy to `~/.oracle-monitor/config` and set your oracle ID, webhook URL, alert thresholds, and quorum margin thresholds. Script works without it using built-in defaults. |
| [ORACLE_SETUP_QUICKSTART.md](./ORACLE_SETUP_QUICKSTART.md) | Quick-start checklist for new oracle operators. Covers download, config, key generation, and posting to Gitter. |
| [ORACLE_SETUP_TUTORIAL.md](./ORACLE_SETUP_TUTORIAL.md) | Full step-by-step tutorial for all platforms (Linux, Windows, macOS). Posted by shenger in the DigiDollar Gitter community. |
| [ORACLE_HARDENING_GUIDE.md](ORACLE_HARDENING_GUIDE.md) | VPS security hardening guide — SSH, UFW, Fail2Ban, kernel hardening, systemd. Step-by-step, based on my live oracle setup. |
| [HOME_ORACLE_HARDENING_GUIDE.md](HOME_ORACLE_HARDENING_GUIDE.md) | Home network security hardening guide — Linux, Windows, macOS. Three tiers (Essential, Recommended, Advanced). Covers firewall, port forwarding, NTP, router hardening, UPS, VLANs, WireGuard. Network diagrams: [Tier 1](https://htmlpreview.github.io/?https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/network-tier1-essential.html) · [Tier 2](https://htmlpreview.github.io/?https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/network-tier2-recommended.html) · [Tier 3](https://htmlpreview.github.io/?https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/network-tier3-advanced.html). Community-requested by Aussie Epic. |

More tools will be added as the DigiDollar testnet matures toward mainnet activation.
**Roadmap:** See [open issues](https://github.com/BaumerCrypto/digidollar-oracle-tools/issues) for planned features — mainnet migration, bundle signer detection, cross-platform support, and more.

---

## `oracle-monitor.sh`

### What it checks (every 5 minutes by default)

- `digibyted` daemon process alive
- Oracle is `running` in `listoracle`
- Chain sync (`verificationprogress`)
- Peer count (default min: 3)
- Price freshness (`is_stale` flag on `getoracleprice`)
- Degraded consensus detection (`status` != `ok` on `getoracleprice`)
- Disk space (default min: 5GB free)
- Memory usage
- `digibyted.service` and oracle process status via `listoracle` RPC
- Binary version drift detection
- NTP time synchronization
- **Quorum margin tracking** — counts active oracles via `getoracles true`, compares against on-chain quorum threshold from `getdigidollardeploymentinfo`, reports MuSig2 session health (v2.0)

### What it sends

Discord embeds — color-coded:

- 🔴 **Red** — critical (daemon down, oracle stopped, chain stuck, quorum at edge or lost)
- 🟡 **Yellow** — warnings (low peers, low disk, stale price, degraded consensus, NTP desync, quorum getting thin)
- 🟢 **Green** — recovery confirmations (quorum healthy, margin improving)
- 🔵 **Blue** — 12-hour status summary

State files in `~/.oracle-monitor/` prevent the same alert firing every 5 minutes — you get notified once when something breaks and once again when it recovers.

All timestamps inside alerts are in UTC for unambiguous reading across timezones. Discord's footer time auto-converts to each viewer's local time.

### Discord alert examples

**Health summary with quorum tracking and MuSig2 session status:**

![Oracle Health Summary](Discord_alert-Quorum1.jpg)

**Quorum state transition alerts — red/yellow/green as oracle count changes:**

![Quorum Alerts](Discord_alert-Quorum2.jpg)

### Requirements

- Linux (tested on Ubuntu 24.04 LTS)
- DigiByte Core **v9.26.0-rc44** or later (uses `listoracle`, `getoracleprice`, `getdigidollardeploymentinfo`, `getoracles` RPCs)
- `jq` (for JSON parsing — install with `sudo apt install jq`)
- `curl`
- A Discord webhook URL — create one at: *Server Settings → Integrations → Webhooks → New Webhook*

### Setup

1. Download the script and config template to your oracle VPS:
```bash
   wget https://raw.githubusercontent.com/BaumerCrypto/digidollar-oracle-tools/main/oracle-monitor.sh
   wget https://raw.githubusercontent.com/BaumerCrypto/digidollar-oracle-tools/main/config.template
   chmod +x oracle-monitor.sh
```

2. Create your config file from the template:
```bash
   mkdir -p ~/.oracle-monitor
   cp config.template ~/.oracle-monitor/config
```

3. Edit the config file with your settings:
```bash
   nano ~/.oracle-monitor/config
```
   Set your Discord webhook URL, oracle ID, and oracle name. For mainnet, change `CLI="digibyte-cli"`.

4. Test with `--dry-run` (runs all checks, prints to terminal, skips Discord):
```bash
   ./oracle-monitor.sh --dry-run
```

5. Test the webhook:
```bash
   ./oracle-monitor.sh --test
```
   You should see a test alert appear in your Discord channel.

6. Test a full health summary:
```bash
   ./oracle-monitor.sh --summary
```

7. Add to cron (`crontab -e`):
```cron
   */5 * * * * $HOME/oracle-monitor.sh 2>/dev/null
   0 */12 * * * $HOME/oracle-monitor.sh --summary 2>/dev/null
```

### Flags

| Flag | What it does |
|------|-------------|
| *(none)* | Normal health check — alerts only on problems or recovery |
| `--summary` | Full status summary — always sends to Discord |
| `--dry-run` | Runs all checks, prints to terminal, skips Discord, no state changes |
| `--test` | Sends a test embed to Discord to verify webhook |

### Configuration options

All thresholds are configurable in `~/.oracle-monitor/config`. The script uses built-in defaults if a value isn't set.

| Setting | Default | Description |
|---------|---------|-------------|
| `DISCORD_WEBHOOK` | *(empty)* | Discord webhook URL for alerts |
| `ORACLE_ID` | `0` | Your oracle slot ID |
| `ORACLE_NAME` | `my-oracle` | Your oracle name (shown in Discord embeds) |
| `CLI` | `digibyte-cli -testnet` | RPC command. Use `digibyte-cli` for mainnet |
| `WALLET_FLAG` | `-rpcwallet=oracle` | Wallet flag for RPC calls |
| `MIN_PEERS` | `3` | Minimum peer count before alerting |
| `MIN_DISK_GB` | `5` | Minimum free disk space (GB) |
| `MEM_THRESHOLD` | `90` | Memory usage % above which to alert |
| `MAX_CHAIN_BEHIND` | `10` | Blocks behind before alerting |
| `QUORUM_GREEN` | `20` | Oracles reporting at/above this = healthy (no alert) |
| `QUORUM_YELLOW` | `12` | Below green but at/above this = "getting thin" warning |

### Quorum alert bands

| Active oracles | Status | Alert |
|----------------|--------|-------|
| 🟢 20+ | Comfortable | No alert |
| 🟡 12–19 | Getting thin | Yellow warning |
| 🔴 7–11 | At quorum edge | Red alert |
| 💀 Below 7 | DD signing halted | Critical alert |

`QUORUM_GREEN` (20) and `QUORUM_YELLOW` (12) are configurable in your config file. The quorum minimum (`oracle_consensus_required`, currently 7) comes from the chain itself via `getdigidollardeploymentinfo` — it's not configurable. Below that threshold, DigiDollar signing halts regardless of your config settings.

### RPC field-name notes (RC44)

If you adapt this for a different release, double-check these field names — they have changed between RCs:

| RPC | Field used |
|-----|-----------|
| `listoracle` | `running` *(not `is_running`)* |
| `listoracle` | `price_usd` *(not `last_price_usd`)* |
| `getoracleprice` | `price_usd`, `is_stale`, `status`, `oracle_count` |
| `getdigidollardeploymentinfo` | `oracle_consensus_required`, `oracle_total_slots`, `musig2_session.state`, `musig2_session.epoch`, `musig2_session.nonce_count`, `musig2_session.partial_sig_count` |
| `getoracles true` | `last_price_usd`, `status` |

---

## Compatibility

| Component | Version |
|-----------|---------|
| OS | Ubuntu 24.04 LTS |
| DigiByte Core | v9.26.0-rc44 |
| Chain | testnet26 |
| Oracle protocol | v0x03 MuSig2 bundle |
| oracle-monitor.sh | v2.0 |

If you're running a different release and something breaks, please open an issue.

---

## Contributing

Pull requests welcome. If you spot a bug, run into a field-name change on a newer RC, or want to add a check, open an issue or PR.

---

## Author

**digibyte-maxi** — DigiDollar oracle operator (Slot 17)

- GitHub: [BaumerCrypto](https://github.com/BaumerCrypto) (display name: BaumerCrypto2.0)
- X/Twitter: [@BaumerCrypto2_0](https://x.com/BaumerCrypto2_0)
- Gitter: `digibyte-maxi` in [#digidollar](https://app.gitter.im/#/room/#digidollar:gitter.im)

---

## License

[MIT](LICENSE) — use, fork, modify, share. Credit appreciated but not required.

## Disclaimer

These scripts are provided as-is for the DigiByte community. The DigiDollar protocol is currently in testnet; mainnet activation is pending miner signaling (BIP9 bit 23, window opens June 1, 2026). Always test on testnet first and back up your oracle wallet.
