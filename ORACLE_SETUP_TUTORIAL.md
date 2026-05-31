# DigiDollar Oracle Setup — Full Tutorial

> Originally written by **shenger** in the DigiDollar Gitter community.  
> Reproduced here for reference. All credit to the original author.  
> Gitter: https://app.gitter.im/#/room/#digidollar:gitter.im

For the quick-start checklist version, see [ORACLE_SETUP_QUICKSTART.md](./ORACLE_SETUP_QUICKSTART.md).

---

## What an Oracle Does

An oracle is a DigiByte node that reports the DGB/USD price to the network.

As an operator your job is to:

- Run a stable DigiByte node
- Create an oracle key in your wallet
- Get an oracle ID assigned by the DigiDollar team
- Start the oracle and keep it running reliably

---

## The Process at a Glance

1. Download and install the current RC release
2. Set up `digibyte.conf` for testnet
3. Start the node and confirm it runs normally
4. Contact the DigiDollar team and request an oracle ID
5. Create a wallet for the oracle
6. Create your oracle key with the assigned ID
7. Post your operator details and public key in Gitter
8. Wait for a new RC that includes your key
9. Install that RC
10. Start the oracle
11. Verify it is running

**Important:** You do not become an active oracle immediately after creating a key. You must wait for a new RC that includes your public key before running `startoracle`.

---

## Before You Begin

You need:

- A computer or VPS you can keep online long term
- A stable internet connection
- The current DigiByte RC release with DigiDollar/oracle support
- A wallet for storing your oracle key

Download the current RC release first:  
https://github.com/DigiByte-Core/digibyte/releases

---

## Step 1 — Install RC and Configure DigiByte Core

Download and install the current RC for your platform, then configure `digibyte.conf` before starting.

**Config file locations:**

| Platform | Location |
|----------|----------|
| Linux | `~/.digibyte/digibyte.conf` |
| Windows | `%APPDATA%\DigiByte\digibyte.conf` |
| macOS | `~/Library/Application Support/DigiByte/digibyte.conf` |

**Minimum testnet oracle config:**

```ini
testnet=1

[test]
server=1
listen=1
txindex=1
digidollar=1
addnode=oracle1.digibyte.io
rpcport=14026
debug=digidollar
debug=net
```

Start the node:

```bash
digibyted -testnet
```

Or launch DigiByte-Qt normally if using the desktop wallet.

---

## Step 2 — Request an Oracle ID

Contact the DigiDollar team in Gitter and ask for an assigned oracle ID:  
https://app.gitter.im/#/room/#digidollar:gitter.im

State that you are seriously interested in operating an oracle long term and that you have the technical requirements to run it reliably. Ask which oracle ID can be assigned to you.

**You need this ID before you can create your oracle key.**

---

## Step 3 — Create the Oracle Wallet

CLI:

```bash
digibyte-cli -testnet createwallet "oracle"
```

Qt wallet: Help → Debug Window → Console:

```
createwallet "oracle"
```

Your oracle private key is stored here. Back it up after setup. Never transfer DGB into this wallet.

---

## Step 4 — Create Your Oracle Key

Once the team assigns your ID:

```bash
digibyte-cli -testnet -rpcwallet=oracle createoraclekey <your_oracle_id>
```

Example for ID 18:

```bash
digibyte-cli -testnet -rpcwallet=oracle createoraclekey 18
```

Qt wallet: Help → Debug Window → Console:

```
createoraclekey <your_oracle_id>
```

The command returns a public key. That is what you post in Gitter.

**Never share your private key.**

---

## Step 5 — Post Your Details in Gitter

Post in https://app.gitter.im/#/room/#digidollar:gitter.im with:

```
Requested ID: 18
Oracle name: YourOracleName
Pubkey: 03abc...
Platform: Ubuntu VPS, 4 GB RAM, SSD, stable connection
Can reliably run 1–2 years: yes
```

---

## Step 6 — Wait for the New RC, Then Start the Oracle

The DigiDollar team must include your public key in a new release candidate. The order is:

1. Ask for an oracle ID
2. Create your oracle key
3. Post your details in Gitter
4. Wait for a new RC that includes your key
5. Download and install that RC
6. Start the oracle

Once the RC with your key is available:

```bash
digibyte-cli -testnet -rpcwallet=oracle startoracle <your_oracle_id>
```

If your wallet is encrypted, unlock it first:

```bash
digibyte-cli -testnet -rpcwallet=oracle walletpassphrase "your passphrase" 600
digibyte-cli -testnet -rpcwallet=oracle startoracle <your_oracle_id>
```

---

## Step 7 — Verify It Is Running

```bash
digibyte-cli -testnet listoracle
digibyte-cli -testnet getoraclepubkey <your_oracle_id>
digibyte-cli -testnet getoracles true
```

**Common reasons the oracle is not running:**

- Wrong wallet loaded
- Wallet is locked
- Not yet on the RC that includes your key
- Wrong oracle ID used

---

## Step 8 — Keep It Online

The real work of an oracle operator is reliability:

- Stable uptime
- Regular wallet backups
- Quick restarts after crashes or reboots
- A machine you can maintain long term

---

## Platform Notes

### Linux
Preferred for VPS hosting. Use `digibyted` + `digibyte-cli`. Manage via systemd or shell.

### Windows
Works. Use DigiByte-Qt or `digibyte-cli.exe`. Note: sleep mode, updates, or restarts interrupt oracle uptime. A Windows VPS avoids most of this.

### macOS
Works. Config at `~/Library/Application Support/DigiByte/digibyte.conf`. Use the debug console or `digibyte-cli`. Same uptime concerns as Windows desktop.

---

## Wallet Backup

```bash
digibyte-cli -testnet -rpcwallet=oracle backupwallet "/path/to/backup.dat"
```

Keep the backup somewhere safe. The oracle key lives in this wallet — losing it means losing your slot.

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Sharing the private key | Share only the public key returned by `createoraclekey` |
| Using the wrong wallet | Confirm the oracle wallet is open before running oracle commands |
| Picking your own oracle ID | Always request an assigned ID from the team |
| Assuming oracle runs forever | Monitor uptime, wallet, and node regularly |

---

## Quick Reference

```bash
# Create wallet
digibyte-cli -testnet createwallet "oracle"

# Create oracle key
digibyte-cli -testnet -rpcwallet=oracle createoraclekey <id>

# Unlock wallet
digibyte-cli -testnet -rpcwallet=oracle walletpassphrase "passphrase" 600

# Start oracle
digibyte-cli -testnet -rpcwallet=oracle startoracle <id>

# Check status
digibyte-cli -testnet listoracle

# Backup wallet
digibyte-cli -testnet -rpcwallet=oracle backupwallet "/path/to/backup.dat"
```

---

*For questions, ask in the DigiDollar Gitter:*  
https://app.gitter.im/#/room/#digidollar:gitter.im
