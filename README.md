# digidollar-oracle-tools

Operator tools and monitoring scripts for [DigiByte](https://www.digibyte.org/) DigiDollar Oracle nodes.

Maintained by **digibyte-maxi** (Oracle Slot 17) — see contact at the bottom.

---

## What's in this repo

| File | Purpose |
|------|---------|
| [oracle-monitor.sh](oracle-monitor.sh) | Bash health monitor v2.2 — 11 checks (daemon, oracle, chain sync, peers, price freshness, consensus status, disk, memory, version, NTP, quorum margin). Quorum tracking via `getdigidollardeploymentinfo` + `getoracles` with MuSig2 session health. Counts online oracles by heartbeat (stable across round transitions). Anti-flap: cooldown timer + hysteresis buffer prevent alert spam during volatile periods. Discord webhook alerts with red/yellow/green embeds. External config file, `--dry-run` mode, jq-based JSON parsing. State files prevent repeat alerts. |
| [oracle-network-status.sh](oracle-network-status.sh) | Gitter network status bot v1.4 — posts automated oracle network health summaries to the DigiDollar Gitter channel every 12 hours via Matrix API. Network label in header (auto-detected or config override). Reports: fresh heartbeats, quorum health, consensus price, MuSig2 session, BIP9 activation, last bundle signers, software version adoption, stale/inactive oracle list with @ mention notifications. `--config /path` flag for dual-instance monitoring (testnet + mainnet). Bot account: `@digidollar-oracle-bot:matrix.org`. |
| [oracle-roster.template](oracle-roster.template) | Template for the oracle-to-Gitter-handle mapping file used by the @ mention feature. Copy to `~/.oracle-monitor/oracle-roster.conf` and populate with real Matrix IDs. The populated file stays on VPS only — never push to GitHub. |
| [config.template](config.template) | Configuration template for oracle-monitor.sh and oracle-network-status.sh. Copy to `~/.oracle-monitor/config` and set your oracle ID, webhook URL, alert thresholds, quorum margin thresholds, anti-flap settings, network label, and Matrix API credentials for the Gitter bot. Both scripts work without it using built-in defaults. |
| [ORACLE_SETUP_QUICKSTART.md](./ORACLE_SETUP_QUICKSTART.md) | Quick-start checklist for new oracle operators. Covers download, config, key generation, and posting to Gitter. |
| [ORACLE_SETUP_TUTORIAL.md](./ORACLE_SETUP_TUTORIAL.md) | Full step-by-step tutorial for all platforms (Linux, Windows, macOS). Posted by shenger in the DigiDollar Gitter community. |
| [ORACLE_HARDENING_GUIDE.md](ORACLE_HARDENING_GUIDE.md) | VPS security hardening guide — SSH, UFW, Fail2Ban, kernel hardening, systemd. Step-by-step, based on my live oracle setup. |
| [HOME_ORACLE_HARDENING_GUIDE.md](HOME_ORACLE_HARDENING_GUIDE.md) | Home network security hardening guide — Linux, Windows, macOS. Three tiers (Essential, Recommended, Advanced). Covers firewall, port forwarding, NTP, router hardening, UPS, VLANs, WireGuard. Network diagrams: [Tier 1](https://htmlpreview.github.io/?https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/network-tier1-essential.html) · [Tier 2](https://htmlpreview.github.io/?https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/network-tier2-recommended.html) · [Tier 3](https://htmlpreview.github.io/?https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/network-tier3-advanced.html). Community-requested by Aussie Epic. |
| [oracle-monitor.ps1](oracle-monitor.ps1) | Windows PowerShell port v2.2-win.1 — full logic parity with Linux v2.2. PS 5.1 and PS 7 compatible, zero dependencies. Includes watch mode (`-Watch`). Ships UTF-8 with BOM. |
| [config.template.ps1](config.template.ps1) | Windows configuration template for oracle-monitor.ps1. |
| [oracle-monitor-macos.sh](oracle-monitor-macos.sh) | macOS port v2.2-macos.1 — stock bash 3.2 compatible, jq is the only dependency. Includes watch mode (`--watch`). |
| [config-macos.template](config-macos.template) | macOS configuration template for oracle-monitor-macos.sh. |
| [CROSS_PLATFORM_SETUP.md](CROSS_PLATFORM_SETUP.md) | Setup guide for Windows and macOS ports — installation, config, Task Scheduler/cron, watch mode, troubleshooting. |

More tools will be added as the DigiDollar testnet matures toward mainnet activation.
**Roadmap:** See [open issues](https://github.com/BaumerCrypto/digidollar-oracle-tools/issues) for planned features — mainnet migration, bundle signer detection, cross-platform support, and more.

---

## Platform support

The monitor runs natively on all three major platforms. Same 11 checks, same quorum state machine, same anti-flap logic, same Discord alerts — only the plumbing underneath differs.

| Platform | Script | Config template | Version |
|---|---|---|---|
| Linux | [`oracle-monitor.sh`](oracle-monitor.sh) | [`config.template`](config.template) | 2.2 |
| Windows 10/11 | [`oracle-monitor.ps1`](oracle-monitor.ps1) | [`config.template.ps1`](config.template.ps1) | 2.2-win.1 |
| macOS | [`oracle-monitor-macos.sh`](oracle-monitor-macos.sh) | [`config-macos.template`](config-macos.template) | 2.2-macos.1 |

Windows needs no dependencies at all (PowerShell parses JSON natively). macOS needs only jq and runs on the stock bash 3.2 every Mac ships with. Setup for both is in [`CROSS_PLATFORM_SETUP.md`](CROSS_PLATFORM_SETUP.md). The rest of this README documents the Linux version; the ports behave identically.

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
- **Quorum margin tracking** — counts online oracles via `getoracles true` using `heartbeat_status` (stable across MuSig2 round transitions, matches dashboard's "Online Heartbeats" metric), compares against on-chain quorum threshold from `getdigidollardeploymentinfo`, reports MuSig2 session health. Anti-flap: cooldown timer throttles recovery alerts during volatile periods, hysteresis buffer prevents oscillation at band boundaries (v2.2)

### What it sends

Discord embeds — color-coded:

- 🔴 **Red** — critical (daemon down, oracle stopped, chain stuck, quorum at edge or lost)
- 🟡 **Yellow** — warnings (low peers, low disk, stale price, degraded consensus, NTP desync, quorum getting thin)
- 🟢 **Green** — recovery confirmations (quorum healthy, margin improving)
- 🔵 **Blue** — 12-hour status summary

State files in `~/.oracle-monitor/` prevent the same alert firing every 5 minutes — you get notified once when something breaks and once again when it recovers. Quorum tracking uses a single `quorum_state` file that stores the current band and timestamp, with cooldown and hysteresis to prevent alert flapping during network volatility.

All timestamps inside alerts are in UTC for unambiguous reading across timezones. Discord's footer time auto-converts to each viewer's local time.

### Discord alert examples

**Health summary with quorum tracking and MuSig2 session status:**

![Oracle Health Summary](Discord_alert-Quorum1.jpg)

**Quorum state transition alerts — red/yellow/green as oracle count changes:**

![Quorum Alerts](Discord_alert-Quorum2.jpg)

### Requirements

- Linux (tested on Ubuntu 24.04 LTS) — for Windows and macOS, see [Platform support](#platform-support) above
- DigiByte Core **v9.26.0-rc46** (also compatible with rc44 and rc45 — uses `listoracle`, `getoracleprice`, `getdigidollardeploymentinfo`, `getoracles` RPCs)
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
| `QUORUM_COOLDOWN` | `30` | Minutes between quorum recovery alerts. Escalation (worse) always fires immediately. Set to `0` to disable (v2.1+) |
| `QUORUM_HYSTERESIS` | `3` | Recovery buffer — must exceed threshold by this many oracles to recover. Prevents flapping at boundaries. Set to `0` to disable (v2.1+) |

The quorum minimum (`oracle_consensus_required`, currently 7) comes from the chain itself via `getdigidollardeploymentinfo` — it's not configurable. Below that threshold, DigiDollar signing halts regardless of your config settings.

### Quorum alert bands

| Active oracles | Status | Escalation alert | Recovery alert |
|----------------|--------|------------------|----------------|
| 🟢 20+ | Comfortable | — | `✅ Quorum Healthy` |
| 🟡 12–19 | Getting thin | `⚠️ Quorum Getting Thin` | `✅ Quorum Improved — Getting Thin → Healthy` |
| 🔴 7–11 | At quorum edge | `🚨 Quorum at Edge` | `✅ Quorum Improved — At Edge → Getting Thin` |
| 💀 Below 7 | DD signing halted | `🚨 QUORUM LOST` | `✅ Quorum Recovered — LOST → At Edge` |

**Escalation** (count drops into a worse band) always fires immediately. **Recovery** (count rises into a better band) is throttled by `QUORUM_COOLDOWN` and requires the count to exceed the threshold by `QUORUM_HYSTERESIS` oracles. This prevents a single oracle bouncing around a boundary from generating a stream of alerts.

### Hysteresis recovery thresholds (default QUORUM_HYSTERESIS=3)

| Recovery to | Threshold | Required count |
|-------------|-----------|----------------|
| 🟢 Healthy | `QUORUM_GREEN` (20) | 20 + 3 = **23** |
| 🟡 Getting thin | `QUORUM_YELLOW` (12) | 12 + 3 = **15** |
| 🔴 At edge | `oracle_consensus_required` (7) | 7 + 3 = **10** |

With `QUORUM_HYSTERESIS=0`, recovery fires at the exact threshold (v2.0 behavior).

### RPC field reference

Both scripts parse specific fields from DigiByte Core RPCs. If a future RC renames a field, these scripts may need updates. Known field names as of RC46:

| RPC | Field used |
|-----|-----------|
| `listoracle` | `running` *(not `is_running`)* |
| `listoracle` | `price_usd` *(not `last_price_usd`)* |
| `getoracleprice` | `price_usd`, `is_stale`, `status`, `oracle_count` |
| `getdigidollardeploymentinfo` | `oracle_consensus_required`, `oracle_total_slots`, `musig2_session.state`, `musig2_session.epoch`, `musig2_session.nonce_count`, `musig2_session.partial_sig_count` |
| `getoracles true` | `last_price_usd`, `status`, `heartbeat_status` *(v2.2: "fresh" = online within 30 min)*, `heartbeat_age_seconds`, `heartbeat_timestamp`, `software_version` *(used by oracle-network-status.sh)* |
| `getblockchaininfo` | `chain` *(used by oracle-network-status.sh v1.4 for network label auto-detection)* |
| `getoraclesigners` | `bundle_count`, `bundles[].height`, `bundles[].signer_count`, `bundles[].signer_ids` *(used by oracle-network-status.sh)* |

**RC45 new RPCs** (not used by these scripts yet but available):
| RPC | Purpose |
|-----|---------|
| `exportoracleprivkey` | Export oracle signing key from wallet (wallet-context, usable before activation) |
| `importoracleprivkey` | Import oracle signing key into wallet (wallet-context, usable before activation) |

---

## `oracle-network-status.sh`

Community-facing Gitter bot that posts oracle network health summaries to the [DigiDollar Gitter channel](https://app.gitter.im/#/room/#digidollar:gitter.im) every 12 hours. Unlike `oracle-monitor.sh` (which watches your own node and alerts you privately via Discord), this script monitors the entire oracle network and reports publicly.

### What it reports

- **Network label** — which chain the report covers (e.g. "Testnet26" or "Mainnet"), auto-detected from `getblockchaininfo` or set via `NETWORK_LABEL` in config (v1.4)
- **Fresh Heartbeats** — active oracle count vs roster size, quorum health status (healthy / thin / critical / lost)
- **Consensus price** — current DGB/USD price and oracle price feed status
- **MuSig2 session** — current epoch, signing state, nonce and signature counts
- **BIP9 activation** — deployment status and signaling bit
- **Last bundle** — most recent on-chain price bundle block height and signer count
- **Software versions** — dominant version among active operators (✅ current vs 🔄 outdated during upgrades)
- **Stale oracles** (⚠️) — were running, went down (liveness concern). Operators are @ mentioned in Gitter for up to 6 cycles (3 days), then suppressed but still listed.
- **Inactive oracles** (❌) — have key or wallet issues on this testnet. Same @ mention behavior as stale.

### Example output

```
🟢 Oracle Network Status — Testnet26 — 2026-06-21 23:25 UTC

Fresh Heartbeats: 25/35 (quorum healthy — threshold: 7)
Consensus price: $0.002718 (status: active)
MuSig2: epoch 1160, complete, 7/7 nonces, 7/7 sigs
BIP9: active (bit 23)
Last bundle: block 46399, signed by 7 oracles

Software:
  ✅ v9.26.0rc46-g873d6d068... : 21 operators
  ✅ v9.26.0rc46-873d6d068b9f : 2 operators

⚠️ Stale (8):
  — ID 5 Ycagel
  — ID 11 hallvardo @hallvardo:gitter.im
  — ID 13 DigiByteForce @digibyteforce:gitter.im
  — ID 22 LivingTheLife
  — ID 23 ChozenOne43 @chozenone43:gitter.im
  — ID 27 DennisPitallano
  — ID 30 DigibyteDaily @dailydgb:gitter.im
  — ID 32 3DogsKanab @3dogskanab:gitter.im

❌ Inactive (2):
  — ID 31 Peer2Peer
  — ID 34 Manu_DGB_oracle
```

### Data sources

| RPC | What it provides |
|-----|-----------------|
| `getblockchaininfo` | Chain identification — auto-detects "test" → Testnet, "main" → Mainnet for header label (v1.4) |
| `getoracles true` | Per-oracle heartbeat status — active, stale, and offline lists |
| `getoracleprice` | Consensus price, feed status, oracle count |
| `getdigidollardeploymentinfo` | BIP9 activation, quorum config, MuSig2 session state |
| `getoraclesigners 50` | Recent bundle signer participation (50-block window covers at least one full 40-block round) |

### Requirements

- Linux (tested on Ubuntu 24.04 LTS)
- DigiByte Core **v9.26.0-rc46** (also compatible with rc44 and rc45)
- `jq`, `curl`
- A [Matrix](https://matrix.org) bot account joined to `#digidollar:gitter.im`

### Setup

1. Create a Matrix bot account at [Element](https://app.element.io/#/register) (e.g. `@digidollar-oracle-bot:matrix.org`)
2. Join `#digidollar:gitter.im` from the bot account
3. Generate an access token on the VPS:
```bash
curl -s -X POST "https://matrix.org/_matrix/client/v3/login" \
  -H "Content-Type: application/json" \
  -d '{"type":"m.login.password","identifier":{"type":"m.id.user","user":"YOUR_BOT_USERNAME"},"password":"YOUR_PASSWORD"}' \
  | jq -r '.access_token'
```
4. Get the room ID (Element → Room Settings → Advanced → Internal room ID)
5. Add to `~/.oracle-monitor/config`:
```bash
MATRIX_ACCESS_TOKEN="your_token_here"
MATRIX_ROOM_ID="!your_room_id:gitter.im"
```
6. Set the network label (optional — auto-detected from chain if not set):
```bash
NETWORK_LABEL="Testnet26"
```
7. For @ mentions (optional): populate the roster mapping file:
```bash
wget https://raw.githubusercontent.com/BaumerCrypto/digidollar-oracle-tools/main/oracle-roster.template
cp oracle-roster.template ~/.oracle-monitor/oracle-roster.conf
nano ~/.oracle-monitor/oracle-roster.conf
# Fill in oracle ID to Gitter Matrix ID mappings — see template for format
```
8. Test: `./oracle-network-status.sh --dry-run`
9. Test: `./oracle-network-status.sh --test`
10. Test mentions: `./oracle-network-status.sh --test-mention`
11. Add to cron: `5 */12 * * * /home/dgboracle/oracle-network-status.sh 2>/dev/null`

### Flags

| Flag | What it does |
|------|-------------|
| *(none)* | Collect data and post to Gitter |
| `--dry-run` | Collect data, print to terminal, skip Gitter post |
| `--test` | Send a test message to Gitter to verify Matrix API |
| `--test-mention` | Send a test @ mention to verify Gitter notifications work |
| `--config /path` | Use alternate config file — enables dual-instance monitoring (v1.4) |

### Dual-instance monitoring (testnet + mainnet)

When mainnet launches, you can run two independent instances from the same script using `--config`:

```cron
# Testnet (default config)
5 */12 * * * /home/dgboracle/oracle-network-status.sh 2>/dev/null
# Mainnet (custom config)
10 */12 * * * /home/dgboracle/oracle-network-status.sh --config ~/.oracle-monitor-mainnet/config 2>/dev/null
```

Each instance uses its own config file and tracks mention state independently. The roster file is shared by default (same 35 operators on both networks). Setup:

```bash
mkdir -p ~/.oracle-monitor-mainnet
cp ~/.oracle-monitor/config ~/.oracle-monitor-mainnet/config
# Edit mainnet config: CLI="digibyte-cli", NETWORK_LABEL="Mainnet"
ln -s ~/.oracle-monitor/oracle-roster.conf ~/.oracle-monitor-mainnet/oracle-roster.conf
```

`--config` combines with action flags in any order: `--config /path --dry-run` or `--dry-run --config /path`.

### Important: single-operator bot

This script is designed for a **single designated community operator** to post to the shared DigiDollar Gitter channel. Running a second instance against the same channel will create duplicate posts. If you want to monitor your own oracle, use `oracle-monitor.sh` with a Discord webhook to your private channel.

---

## Compatibility

| Component | Version |
|-----------|---------|
| OS | Linux (Ubuntu 24.04 LTS), Windows 10/11 (PowerShell 5.1+), macOS (bash 3.2+) |
| DigiByte Core | v9.26.0-rc46 (also compatible with rc44 and rc45) |
| Chain | testnet26 |
| Oracle protocol | v0x03 MuSig2 bundle |
| oracle-monitor.sh | v2.2 |
| oracle-monitor.ps1 | v2.2-win.1 |
| oracle-monitor-macos.sh | v2.2-macos.1 |
| oracle-network-status.sh | v1.4 |

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
