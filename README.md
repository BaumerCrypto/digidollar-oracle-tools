# digidollar-oracle-tools

Operator tools and monitoring scripts for [DigiByte](https://www.digibyte.org/) DigiDollar oracle nodes.

Maintained by **digibyte-maxi** (Oracle Slot 17) — see contact at the bottom.

---

## What's in this repo

| File | Purpose |
|------|---------|
| [`oracle-monitor.sh`](oracle-monitor.sh) | Bash health monitor with Discord webhook alerts. Runs from cron, checks daemon/oracle/sync/peers/disk/memory and sends red/yellow/green embeds to a Discord channel. State files prevent repeat alerts on persistent conditions. |
| [ORACLE_SETUP_QUICKSTART.md](./ORACLE_SETUP_QUICKSTART.md) | Quick-start checklist for new oracle operators. Covers download, config, key generation, and posting to Gitter. |
| [ORACLE_SETUP_TUTORIAL.md](./ORACLE_SETUP_TUTORIAL.md) | Full step-by-step tutorial for all platforms (Linux, Windows, macOS). Posted by shenger in the DigiDollar Gitter community. |

More tools will be added as the DigiDollar testnet matures toward mainnet activation.

---

## `oracle-monitor.sh`

### What it checks (every 5 minutes by default)

- `digibyted` daemon process alive
- Oracle is `running` in `listoracle`
- Chain sync (`verificationprogress`)
- Peer count (default min: 3)
- Price freshness (`is_stale` flag on `getoracleprice`)
- Disk space (default min: 5GB free)
- Memory usage
- `digibyted.service` and `dgb-oracle.service` systemd status
- Binary version drift detection

### What it sends

Discord embeds — color-coded:

- 🔴 **Red** — critical (daemon down, oracle stopped, chain stuck)
- 🟡 **Yellow** — warnings (low peers, low disk, stale price)
- 🟢 **Green** — recovery confirmations
- 🔵 **Blue** — 12-hour status summary

State files in `~/.oracle-monitor/` prevent the same alert firing every 5 minutes — you get notified once when something breaks and once again when it recovers.

All timestamps inside alerts are in UTC for unambiguous reading across timezones. Discord's footer time auto-converts to each viewer's local time.

### Requirements

- Linux (tested on Ubuntu 24.04 LTS)
- DigiByte Core **v9.26.0-rc43** or later (uses `listoracle`, `getoracleprice` RPCs)
- `python3` (for JSON payload construction)
- `curl`
- A Discord webhook URL — create one at: *Server Settings → Integrations → Webhooks → New Webhook*

### Setup

1. Download the script to your oracle VPS:
```bash
   wget https://raw.githubusercontent.com/BaumerCrypto/digidollar-oracle-tools/main/oracle-monitor.sh
   chmod +x oracle-monitor.sh
```

2. Edit the script and set your Discord webhook URL near the top:
```bash
   DISCORD_WEBHOOK="https://discord.com/api/webhooks/..."
```

3. Set your oracle ID and name:
```bash
   ORACLE_ID=17
   ORACLE_NAME="your-oracle-name"
```

4. For mainnet, remove `-testnet` from the CLI variable:
```bash
   CLI="digibyte-cli"
```

5. Test the webhook:
```bash
   ./oracle-monitor.sh --test
```
   You should see a test alert appear in your Discord channel.

6. Test a full health check:
```bash
   ./oracle-monitor.sh --summary
```

7. Add to cron (`crontab -e`):
```cron
   */5 * * * * $HOME/oracle-monitor.sh 2>/dev/null
   0 */12 * * * $HOME/oracle-monitor.sh --summary 2>/dev/null
```

### RPC field-name notes (RC43)

If you adapt this for a different release, double-check these field names — they have changed between RCs:

| RPC | Field used |
|-----|-----------|
| `listoracle` | `running` *(not `is_running`)* |
| `listoracle` | `price_usd` *(not `last_price_usd`)* |
| `getoracleprice` | `price_usd`, `is_stale` |

---

## Compatibility

| Component | Version |
|-----------|---------|
| OS | Ubuntu 24.04 LTS |
| DigiByte Core | v9.26.0-rc43 |
| Chain | testnet25 |
| Oracle protocol | v0x03 MuSig2 bundle |

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
