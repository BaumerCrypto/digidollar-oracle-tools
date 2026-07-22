# digidollar-oracle-tools

Operator tools and monitoring scripts for [DigiByte](https://www.digibyte.org/) DigiDollar Oracle nodes.

Maintained by **digibyte-maxi** (Oracle Slot 17) — see contact at the bottom.

> **DigiDollar is live on mainnet.** The deployment activated at block **23,869,440** on **2026-07-17**. These tools monitor both mainnet and testnet26 oracles; everything below applies to both chains unless noted.

---

## What's in this repo

| File | Purpose |
|---|---|
| [oracle-monitor.sh](https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/oracle-monitor.sh) | Bash health monitor v2.7.0 — 13 checks (daemon, oracle, chain sync, peers, price freshness, consensus status, disk, **debug.log growth**, memory, swap pressure, version, NTP, quorum margin). Quorum tracking via `getdigidollardeploymentinfo` + `getoracles` with MuSig2 session health; anti-flap cooldown + hysteresis. **v2.7.0 disk-safety net:** debug.log watchdog that names enabled debug categories in the alert, safe auto-rotation (copy-then-truncate, default ON, announced on every rotation), a yellow disk-usage band ahead of the red floor, and `PRICE_CHECK_EVERY` to thin the loudest RPC. Dual-channel alerts: Discord webhooks (red/yellow/green/blue embeds, `NETWORK_LABEL` in titles, footer version stamp) + optional SMTP email. Daily self-update check and DigiByte Core release check. `--config /path` for dual-instance monitoring (testnet + mainnet). Auto-detects `digibyted` or `digibyte-qt`. External config, `--dry-run`, jq-based parsing, state files prevent repeat alerts. **v9.26.5-ready** (parses both the BIP9 and the new buried deployment shapes). |
| [oracle-network-status.sh](https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/oracle-network-status.sh) | Gitter network status bot v1.4 — posts automated oracle network health summaries to the DigiDollar Gitter channel every 12 hours via Matrix API. Network label in header (auto-detected or config override). Reports: fresh heartbeats, quorum health, consensus price, MuSig2 session, deployment activation, last bundle signers, software version adoption, stale/inactive oracle list with @ mention notifications. `--config /path` flag for dual-instance monitoring (testnet + mainnet). Bot account: `@digidollar-oracle-bot:matrix.org`. |
| [oracle-roster.template](https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/oracle-roster.template) | Template for the oracle-to-Gitter-handle mapping file used by the @ mention feature. Copy to `~/.oracle-monitor/oracle-roster.conf` and populate with real Matrix IDs. The populated file stays on your box only — never push to GitHub. |
| [config.template](https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/config.template) | Configuration template for oracle-monitor.sh and oracle-network-status.sh. Copy to `~/.oracle-monitor/config` and set your oracle ID, webhook URL, alert thresholds, the v2.7.0 disk/debug.log safety knobs, quorum margin thresholds, anti-flap settings, network label, email settings, and Matrix API credentials for the Gitter bot. Both scripts work without it using built-in defaults. |
| [ORACLE_SETUP_QUICKSTART.md](https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/ORACLE_SETUP_QUICKSTART.md) | Quick-start checklist for new oracle operators. Covers download, config, key generation, and posting to Gitter. |
| [ORACLE_SETUP_TUTORIAL.md](https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/ORACLE_SETUP_TUTORIAL.md) | Full step-by-step tutorial for all platforms (Linux, Windows, macOS). Posted by shenger in the DigiDollar Gitter community. |
| [ORACLE_HARDENING_GUIDE.md](https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/ORACLE_HARDENING_GUIDE.md) | VPS security hardening guide v1.5.0 — SSH, UFW, Fail2Ban, kernel hardening, systemd, resource isolation and OOM protection, plus **new in v1.5.0:** a full `debug.log` growth/rotation section (why `debug=digidollar` silently disables the daemon's auto-shrink, measured growth rates, safe rotation recipes) and hardware sizing (RAM floors, pruned-vs-full disk footprints). Step-by-step, based on my live oracle setup. |
| [HOME_ORACLE_HARDENING_GUIDE.md](https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/HOME_ORACLE_HARDENING_GUIDE.md) | Home network security hardening guide — Linux, Windows, macOS. Three tiers (Essential, Recommended, Advanced). Covers firewall, port forwarding, NTP, router hardening, UPS, VLANs, WireGuard. Network diagrams: [Tier 1](https://htmlpreview.github.io/?https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/network-tier1-essential.html) · [Tier 2](https://htmlpreview.github.io/?https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/network-tier2-recommended.html) · [Tier 3](https://htmlpreview.github.io/?https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/network-tier3-advanced.html). Community-requested by Aussie Epic. |
| [oracle-monitor.ps1](https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/oracle-monitor.ps1) | Windows PowerShell port v2.7.0-win.1 — full logic parity with Linux v2.7.0. PS 5.1 and PS 7 compatible, zero dependencies (native JSON parsing). Includes watch mode (`-Watch`) and `-Config` for dual-instance monitoring. Ships UTF-8 with BOM. |
| [config.template.ps1](https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/config.template.ps1) | Windows configuration template for oracle-monitor.ps1. |
| [oracle-monitor-macos.sh](https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/oracle-monitor-macos.sh) | macOS port v2.7.0-macos.1 — stock bash 3.2 compatible, jq is the only dependency. Includes watch mode (`--watch`) and `--config` for dual-instance monitoring. |
| [config-macos.template](https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/config-macos.template) | macOS configuration template for oracle-monitor-macos.sh. |
| [CROSS_PLATFORM_SETUP.md](https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/CROSS_PLATFORM_SETUP.md) | Setup guide for Windows and macOS ports — installation, config, Task Scheduler/cron, watch mode, the v2.7.0 knobs, platform truncation notes, troubleshooting. |

### Testing

The Windows and macOS ports ship with parallel isolated test harnesses for verifying `check_daemon` + `check_services` behavior on your box before scheduling the monitor. Nine scenarios each — auto-detect for headless vs Qt, override honored, service check appropriately skipped when Qt is the running daemon, and so on.

| Harness | Purpose |
|---|---|
| [test-macos-daemon-services.sh](https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/test-macos-daemon-services.sh) | Mocks pgrep, launchctl, and `$CLI` — runs 9 scenarios in isolation. Verifies parity with the Linux logic before you point the monitor at a live oracle. |
| [test-win-daemon-services.ps1](https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/test-win-daemon-services.ps1) | Mocks Get-Process, Get-Service, and Invoke-DGBCli — runs 9 scenarios under Windows PowerShell 5.1 or 7. Verifies PS-specific behavior including auto-detect candidate loop and Windows Service Qt-skip. Ships UTF-8 with BOM. |

Neither harness sends Discord alerts, touches state files, or runs against a real node — they're safe to run on any box, even without DigiByte installed.

**Roadmap:** See [open issues](https://github.com/BaumerCrypto/digidollar-oracle-tools/issues) for planned features — bundle signer detection, update announcements, and more.

---

## Platform support

The monitor runs natively on all three major platforms. Same 13 checks, same DigiDollar activation guard, same quorum state machine, same anti-flap logic, same Qt/headless auto-detect, same Discord card format, same disk-safety net — only the platform plumbing differs.

| Platform | Script | Config template | Version |
|---|---|---|---|
| Linux | [`oracle-monitor.sh`](https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/oracle-monitor.sh) | [`config.template`](https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/config.template) | 2.7.0 |
| Windows 10/11 | [`oracle-monitor.ps1`](https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/oracle-monitor.ps1) | [`config.template.ps1`](https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/config.template.ps1) | 2.7.0-win.1 |
| macOS | [`oracle-monitor-macos.sh`](https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/oracle-monitor-macos.sh) | [`config-macos.template`](https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/config-macos.template) | 2.7.0-macos.1 |

Windows needs no dependencies at all (PowerShell parses JSON natively). macOS needs only jq and runs on the stock bash 3.2 every Mac ships with. Setup for both is in [`CROSS_PLATFORM_SETUP.md`](https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/CROSS_PLATFORM_SETUP.md). The rest of this README documents the Linux version; the ports behave identically (the one Windows divergence — file locking on the in-place log truncate — is documented in the setup guide).

---

## `oracle-monitor.sh`

### What it checks (every 5 minutes by default)

- `digibyted` daemon process alive (auto-detects headless `digibyted` or Qt wallet `digibyte-qt` — configurable via `DAEMON_PROCESS` override)
- Oracle is `running` in `listoracle`
- Chain sync (`verificationprogress`)
- Peer count (default min: 3)
- Price freshness (`is_stale` flag on `getoracleprice`) — gate with `PRICE_CHECK_EVERY` to run this on every Nth pass (v2.7.0)
- Degraded consensus detection (`status` != `ok` on `getoracleprice`)
- Disk space — red floor at `MIN_DISK_GB` free, **plus a v2.7.0 yellow band at `DISK_USED_PCT_WARN` (default 80%) so you get a calm heads-up long before the cliff**
- **debug.log size + growth (v2.7.0, Check 13)** — tracks size and MB/day, and names any enabled debug categories (via the `logging` RPC) right in the alert. Enabling a debug category (the old setup docs said `debug=digidollar`) silently disables the daemon's automatic startup log-shrink; measured on my own box that's **~374 MB/day** with `digidollar`+`net` on vs **~8 MB/day** default. This is driven by your *config*, not the network: a mainnet daemon with `debug=digidollar` set grows just as fast, and a testnet daemon on default logging stays small. The alert's category list is how you tell which case you're in — if it names a category and you're not actively debugging, that daemon is filling its disk for nothing, on either network. Paired with **safe auto-rotation** (default ON): at `DEBUG_LOG_MAX_MB` (2 GB) the monitor copies to `debug.log.1` and truncates the live file in place — the daemon keeps writing, nothing is lost until a second rotation, every rotation posts a blue card, and rotation is skipped (with a red card) if free space can't hold the safety copy. Full background in the [hardening guide](https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/ORACLE_HARDENING_GUIDE.md#debuglog-growth-rotation-and-the-disappearing-disk).
- Memory usage
- **Swap pressure** — alerts when swap usage exceeds threshold (default 100 MB) *and* there is current memory pressure (PSI or RAM headroom — stale fills from a past reindex show as an ℹ️ line instead of a false alarm)
- `digibyted.service` and oracle process status via `listoracle` RPC — systemd unit check auto-skips with an INFO line when the Qt wallet is the running daemon; `SERVICE_NAME="none"` opts out for tmux/Docker/runit setups
- Binary version drift detection via RPC (`getnetworkinfo` → `.subversion`) — with a daily check against the latest DigiByte Core release (✅ when current, ℹ️ "vX.Y.Z available" when not)
- NTP time synchronization
- **Quorum margin tracking** — counts online oracles via `getoracles true` using `heartbeat_status` (stable across MuSig2 round transitions, matches the dashboard's "Online Heartbeats" metric), compares against the on-chain quorum threshold from `getdigidollardeploymentinfo`, reports MuSig2 session health. Anti-flap: cooldown timer throttles recovery alerts during volatile periods, hysteresis buffer prevents oscillation at band boundaries

### DigiDollar activation status handling

The monitor runs a `check_digidollar_active` pre-flight on every pass, reads `getdigidollardeploymentinfo`, and sets a `DD_ACTIVE` global that the four oracle-dependent checks (`check_oracle`, `check_price`, `check_services`, `check_quorum`) consult before deciding whether to alert.

When `DD_ACTIVE=false` (a chain where the deployment hasn't activated — a fresh testnet reset, for example), those four checks downgrade "no data" to a blue ℹ️ standby INFO line instead of a red alert. The other checks (daemon, chain, peers, disk, debug.log, memory, swap, service, NTP, version) continue to alert normally on real problems. The moment the deployment reads active, the monitor automatically switches to full oracle alerting.

**On mainnet this guard has been in the "active" state since block 23,869,440 (2026-07-17)** — so a healthy mainnet monitor shows full oracle data, not standby lines. The guard remains in place for future chains and testnet resets.

**v9.26.5 note:** the upcoming release buries the DigiDollar deployment (BIP90) and reshapes `getdigidollardeploymentinfo`. v2.7.0 parses **both** shapes — the v9.26.4 BIP9 form and the v9.26.5 buried form — so you can upgrade the daemon and the monitor in either order.

### What it sends

Discord embeds — color-coded:

- 🔴 **Red** — critical (daemon down, oracle stopped, chain stuck, quorum at edge or lost, low disk, rotation blocked by low free space)
- 🟡 **Yellow** — warnings (low peers, disk over the warn band, debug.log growing large, stale price, degraded consensus, NTP desync, quorum getting thin, swap pressure)
- 🟢 **Green** — recovery confirmations (quorum healthy, disk back under band, debug.log back under threshold, margin improving)
- 🔵 **Blue** — 12-hour status summary, ℹ️ INFO lines for standby state, and **one card per debug.log rotation** (rotations are never silent)
- **Card titles** carry the `NETWORK_LABEL` from your config on *every* alert — health summaries (`Testnet26 Health Summary`), individual checks (`Mainnet — 🔴 Node Down`), and the `--test` alert — so dual-instance operators can tell which daemon fired an alert at a glance without opening the card
- **Footer** stamps the monitor version and your oracle identity on every card (e.g. `Oracle Monitor v2.7.0 — digibyte-maxi (ID 17)`), and gains a second line when a newer published version of the monitor exists

The same triggers can also fire **email** (curl SMTP — no mailx/postfix needed; `EMAIL_ENABLED=true` plus SMTP settings in the config; Gmail wants an App Password).

State files in `~/.oracle-monitor/` prevent the same alert firing every 5 minutes — you get notified once when something breaks and once again when it recovers. Quorum tracking uses a single `quorum_state` file with cooldown and hysteresis to prevent alert flapping during network volatility.

All timestamps inside alerts are in UTC for unambiguous reading across timezones. Discord's footer time auto-converts to each viewer's local time.

### Discord alert examples

**Health summary with quorum tracking and MuSig2 session status:**

[![Oracle Health Summary](https://github.com/BaumerCrypto/digidollar-oracle-tools/raw/main/Discord_alert-Quorum1.jpg)](/BaumerCrypto/digidollar-oracle-tools/blob/main/Discord_alert-Quorum1.jpg)

**Quorum state transition alerts — red/yellow/green as oracle count changes:**

[![Quorum Alerts](https://github.com/BaumerCrypto/digidollar-oracle-tools/raw/main/Discord_alert-Quorum2.jpg)](/BaumerCrypto/digidollar-oracle-tools/blob/main/Discord_alert-Quorum2.jpg)

*Both images predate mainnet activation and will be refreshed with post-activation mainnet cards — see [issue #29](https://github.com/BaumerCrypto/digidollar-oracle-tools/issues/29). They still show the day-to-day healthy-oracle card format accurately.*

### Requirements

- Linux (tested on Ubuntu 24.04 LTS) — for Windows and macOS, see [Platform support](#platform-support) above
- DigiByte Core **v9.26.4** (also compatible with v9.26.2, v9.26.3, and RC44–RC46; **v9.26.5-ready** — uses `listoracle`, `getoracleprice`, `getdigidollardeploymentinfo`, `getoracles`, `logging` RPCs)
- `jq` (for JSON parsing — install with `sudo apt install jq`)
- `curl`
- A Discord webhook URL — create one at: *Server Settings → Integrations → Webhooks → New Webhook*

### Setup

1. Download the script and config template to your oracle VPS:

```
wget https://raw.githubusercontent.com/BaumerCrypto/digidollar-oracle-tools/main/oracle-monitor.sh
wget https://raw.githubusercontent.com/BaumerCrypto/digidollar-oracle-tools/main/config.template
chmod +x oracle-monitor.sh
```

2. Create your config file from the template:

```
mkdir -p ~/.oracle-monitor
cp config.template ~/.oracle-monitor/config
```

3. Edit the config file with your settings:

```
nano ~/.oracle-monitor/config
```

Set your Discord webhook URL, oracle ID, and oracle name. For mainnet, change `CLI="digibyte-cli"`.

4. Test with `--dry-run` (runs all checks, prints to terminal, skips Discord):

```
./oracle-monitor.sh --dry-run
```

5. Test the webhook:

```
./oracle-monitor.sh --test
```

You should see a test alert appear in your Discord channel.

6. Test a full health summary:

```
./oracle-monitor.sh --summary
```

7. Add to cron (`crontab -e`):

```
*/5 * * * * $HOME/oracle-monitor.sh 2>/dev/null
0 */12 * * * $HOME/oracle-monitor.sh --summary 2>/dev/null
```

### Flags

| Flag | What it does |
|---|---|
| *(none)* | Normal health check — alerts only on problems or recovery |
| `--summary` | Full status summary — always sends to Discord (and email if enabled) |
| `--dry-run` | Runs all checks, prints to terminal, skips Discord + email, no state changes — and never rotates |
| `--test` | Sends a test embed to Discord to verify webhook |
| `--test-email` | Sends a test email to verify SMTP settings |
| `--config /path` | Use alternate config file — enables dual-instance monitoring |

### Configuration options

All thresholds are configurable in `~/.oracle-monitor/config`. The script uses built-in defaults if a value isn't set. The most important ones:

| Setting | Default | Description |
|---|---|---|
| `DISCORD_WEBHOOK` | *(empty)* | Discord webhook URL for alerts |
| `ORACLE_ID` | `0` | Your oracle slot ID |
| `ORACLE_NAME` | `my-oracle` | Your oracle name (shown in Discord embeds) |
| `CLI` | `digibyte-cli -testnet` | RPC command. Use `digibyte-cli` for mainnet |
| `WALLET_FLAG` | `-rpcwallet=oracle` | Wallet flag for RPC calls |
| `MIN_PEERS` | `3` | Minimum peer count before alerting |
| `MIN_DISK_GB` | `5` | Minimum free disk space (GB) — the red floor |
| `DISK_USED_PCT_WARN` | `80` | **v2.7.0** — yellow warning at this used-%. `0` disables the band |
| `DISK_PATH` | `/home` | Filesystem watched for free space (set to your datadir's mount) |
| `DATADIR` | `$HOME/.digibyte` | Datadir named in disk alerts and watched by the debug.log checks — dual-instance operators set it per config |
| `DEBUG_LOG_WARN_MB` | `1024` | **v2.7.0** — yellow alert when debug.log reaches this many MB; alert names any enabled debug categories |
| `DEBUG_LOG_ROTATE` | `"yes"` | **v2.7.0** — safe auto-rotation, **on by default**. Copy-then-truncate, announced on every rotation, skipped when free space can't hold the copy |
| `DEBUG_LOG_MAX_MB` | `2048` | **v2.7.0** — rotation threshold |
| `DEBUG_LOG_KEEP` | `1` | **v2.7.0** — rotated copies to retain (`debug.log.1`, …). `0` is treated as `1` — never truncate without a copy |
| `PRICE_CHECK_EVERY` | `1` | **v2.7.0** — run the `getoracleprice` freshness check every Nth pass (that RPC writes ~4,780 log lines per call with `debug=digidollar` on) |
| `MEM_THRESHOLD` | `90` | Memory usage % above which to alert |
| `SWAP_THRESHOLD_MB` | `100` | Swap usage in MB above which the pressure-gated swap check engages |
| `MAX_CHAIN_BEHIND` | `10` | Blocks behind before alerting |
| `QUORUM_GREEN` | `12` | Oracles reporting at/above this = healthy (no alert) |
| `QUORUM_YELLOW` | `10` | Below green but at/above this = "getting thin" warning |
| `QUORUM_COOLDOWN` | `30` | Minutes between quorum recovery alerts. Escalation (worse) always fires immediately. `0` disables |
| `QUORUM_HYSTERESIS` | `3` | Recovery buffer — must exceed threshold by this many oracles to recover. `0` disables |

The template also carries the email knobs (`EMAIL_ENABLED`, `SMTP_*`), the self-update check (`UPDATE_CHECK`), and the DigiByte release check (`DIGIBYTE_UPDATE_CHECK`) — all documented inline.

The quorum minimum (`oracle_consensus_required`, 7 on mainnet) comes from the chain itself via `getdigidollardeploymentinfo` — it's not configurable. Below that threshold, DigiDollar signing halts regardless of your config settings.

### Quorum alert bands (defaults, 35-slot mainnet roster)

| Active oracles | Status | Escalation alert | Recovery alert |
|---|---|---|---|
| 🟢 12+ | Comfortable | — | `✅ Quorum Healthy` |
| 🟡 10–11 | Getting thin | `⚠️ Quorum Getting Thin` | `✅ Quorum Improved` |
| 🔴 7–9 | At quorum edge | `🚨 Quorum at Edge` | `✅ Quorum Improved` |
| 💀 Below 7 | DD signing halted | `🚨 QUORUM LOST` | `✅ Quorum Recovered` |

**Escalation** (count drops into a worse band) always fires immediately. **Recovery** (count rises into a better band) is throttled by `QUORUM_COOLDOWN` and requires the count to exceed the threshold by `QUORUM_HYSTERESIS` oracles. This prevents a single oracle bouncing around a boundary from generating a stream of alerts.

### Hysteresis recovery thresholds (default QUORUM_HYSTERESIS=3)

| Recovery to | Threshold | Required count |
|---|---|---|
| 🟢 Healthy | `QUORUM_GREEN` (12) | 12 + 3 = **15** |
| 🟡 Getting thin | `QUORUM_YELLOW` (10) | 10 + 3 = **13** |
| 🔴 At edge | `oracle_consensus_required` (7) | 7 + 3 = **10** |

With `QUORUM_HYSTERESIS=0`, recovery fires at the exact threshold.

### RPC field reference

Both scripts parse specific fields from DigiByte Core RPCs. If a future release renames a field, these scripts may need updates. Known field names as of v9.26.4:

| RPC | Field used |
|---|---|
| `listoracle` | `running` *(not `is_running`)* |
| `listoracle` | `price_usd` *(not `last_price_usd`)* |
| `getoracleprice` | `price_usd`, `is_stale`, `status`, `oracle_count` |
| `getdigidollardeploymentinfo` | `status`, `oracle_consensus_required`, `oracle_total_slots`, `musig2_session.state`, `musig2_session.epoch`, `musig2_session.nonce_count`, `musig2_session.partial_sig_count` — **v9.26.5 buried shape** (`type`, `active`, `activation_height`) is also parsed by v2.7.0 |
| `getoracles true` | `last_price_usd`, `status`, `heartbeat_status` *("fresh" = online within 30 min)*, `heartbeat_age_seconds`, `heartbeat_timestamp`, `software_version` *(used by oracle-network-status.sh)* |
| `logging` | category → enabled map *(v2.7.0: names enabled debug categories in the debug.log alert)* |
| `getblockchaininfo` | `chain` *(network label auto-detection)* |
| `getoraclesigners` | `bundle_count`, `bundles[].height`, `bundles[].signer_count`, `bundles[].signer_ids` *(used by oracle-network-status.sh)* |

Wallet-context oracle key RPCs (`exportoracleprivkey` / `importoracleprivkey`) exist since RC45 for backup/restore — not used by these scripts.

---

## `oracle-network-status.sh`

Community-facing Gitter bot that posts oracle network health summaries to the [DigiDollar Gitter channel](https://app.gitter.im/#/room/#digidollar:gitter.im) every 12 hours. Unlike `oracle-monitor.sh` (which watches your own node and alerts you privately via Discord), this script monitors the entire oracle network and reports publicly.

### What it reports

- **Network label** — which chain the report covers (e.g. "Testnet26" or "Mainnet"), auto-detected from `getblockchaininfo` or set via `NETWORK_LABEL` in config
- **Fresh Heartbeats** — active oracle count vs roster size, quorum health status (healthy / thin / critical / lost)
- **Consensus price** — current DGB/USD price and oracle price feed status
- **MuSig2 session** — current epoch, signing state, nonce and signature counts
- **Deployment activation** — status and signaling bit
- **Last bundle** — most recent on-chain price bundle block height and signer count
- **Software versions** — dominant version among active operators (✅ current vs 🔄 outdated during upgrades)
- **Stale oracles** (⚠️) — were running, went down (liveness concern). Operators are @ mentioned in Gitter for up to 6 cycles (3 days), then suppressed but still listed.
- **Inactive oracles** (❌) — have key or wallet issues. Same @ mention behavior as stale.

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
|---|---|
| `getblockchaininfo` | Chain identification — auto-detects "test" → Testnet, "main" → Mainnet for header label |
| `getoracles true` | Per-oracle heartbeat status — active, stale, and offline lists |
| `getoracleprice` | Consensus price, feed status, oracle count |
| `getdigidollardeploymentinfo` | Activation status, quorum config, MuSig2 session state |
| `getoraclesigners 50` | Recent bundle signer participation (50-block window covers at least one full 40-block round) |

### Requirements

- Linux (tested on Ubuntu 24.04 LTS)
- DigiByte Core v9.26.x
- `jq`, `curl`
- A [Matrix](https://matrix.org) bot account joined to `#digidollar:gitter.im`

### Setup

1. Create a Matrix bot account at [Element](https://app.element.io/#/register) (e.g. `@digidollar-oracle-bot:matrix.org`)
2. Join `#digidollar:gitter.im` from the bot account
3. Generate an access token on the VPS:

```
curl -s -X POST "https://matrix.org/_matrix/client/v3/login" \
  -H "Content-Type: application/json" \
  -d '{"type":"m.login.password","identifier":{"type":"m.id.user","user":"YOUR_BOT_USERNAME"},"password":"YOUR_PASSWORD"}' \
  | jq -r '.access_token'
```

4. Get the room ID (Element → Room Settings → Advanced → Internal room ID)
5. Add to `~/.oracle-monitor/config`:

```
MATRIX_ACCESS_TOKEN="your_token_here"
MATRIX_ROOM_ID="!your_room_id:gitter.im"
```

6. Set the network label (optional — auto-detected from chain if not set):

```
NETWORK_LABEL="Testnet26"
```

7. For @ mentions (optional): populate the roster mapping file:

```
wget https://raw.githubusercontent.com/BaumerCrypto/digidollar-oracle-tools/main/oracle-roster.template
cp oracle-roster.template ~/.oracle-monitor/oracle-roster.conf
nano ~/.oracle-monitor/oracle-roster.conf
# Fill in oracle ID to Gitter Matrix ID mappings — see template for format
```

8. Test: `./oracle-network-status.sh --dry-run`
9. Test: `./oracle-network-status.sh --test`
10. Test mentions: `./oracle-network-status.sh --test-mention`
11. Add to cron: `5 */12 * * * /home/YOUR_USER/oracle-network-status.sh 2>/dev/null`

### Flags

| Flag | What it does |
|---|---|
| *(none)* | Collect data and post to Gitter |
| `--dry-run` | Collect data, print to terminal, skip Gitter post |
| `--test` | Send a test message to Gitter to verify Matrix API |
| `--test-mention` | Send a test @ mention to verify Gitter notifications work |
| `--config /path` | Use alternate config file — enables dual-instance monitoring |

### Dual-instance monitoring (testnet + mainnet)

You can run two independent instances from the same script using `--config`:

```
# Testnet (default config)
5 */12 * * * /home/YOUR_USER/oracle-network-status.sh 2>/dev/null
# Mainnet (custom config)
10 */12 * * * /home/YOUR_USER/oracle-network-status.sh --config ~/.oracle-monitor-mainnet/config 2>/dev/null
```

Each instance uses its own config file and tracks mention state independently. The roster file is shared by default (same 35 operators on both networks). Setup:

```
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
|---|---|
| OS | Linux (Ubuntu 24.04 LTS), Windows 10/11 (PowerShell 5.1+), macOS (bash 3.2+) |
| DigiByte Core | v9.26.4 (also compatible with v9.26.2, v9.26.3, and RC44/RC45/RC46; **v9.26.5-ready**) |
| Chain | mainnet (DigiDollar active since block 23,869,440) + testnet26 |
| Oracle protocol | v0x03 MuSig2 bundle |
| oracle-monitor.sh | v2.7.0 |
| oracle-monitor.ps1 | v2.7.0-win.1 |
| oracle-monitor-macos.sh | v2.7.0-macos.1 |
| oracle-network-status.sh | v1.4 |

If you're running a different release and something breaks, please open an issue.

---

## Contributing

Pull requests welcome. If you spot a bug, run into a field-name change on a newer release, or want to add a check, open an issue or PR.

---

## Author

**digibyte-maxi** — DigiDollar oracle operator (Slot 17)

- GitHub: [BaumerCrypto](https://github.com/BaumerCrypto) (display name: BaumerCrypto2.0)
- X/Twitter: [@BaumerCrypto2_0](https://x.com/BaumerCrypto2_0)
- Gitter: `digibyte-maxi` in [#digidollar](https://app.gitter.im/#/room/#digidollar:gitter.im)

---

## License

[MIT](https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/LICENSE) — use, fork, modify, share. Credit appreciated but not required.

## Disclaimer

These scripts are provided as-is for the DigiByte community. **DigiDollar activated on mainnet at block 23,869,440 on 2026-07-17** — the tools now monitor live mainnet oracles as well as testnet26. Always test on testnet first and back up your oracle wallet.
