# Oracle Node Hardening Guide

**A step-by-step security hardening guide for DigiDollar oracle operators running Linux VPS.**

I wrote this guide based on the security setup running on my own DigiDollar oracle node. Every step here is tested, verified, and confirmed to survive reboots. If you're running an oracle on a Linux VPS, this guide will get your server locked down properly (server hardening).

---

## Table of Contents

1. [Before You Start](#before-you-start)
2. [Create a Dedicated User](#step-1--create-a-dedicated-user)
3. [SSH Hardening](#step-2--ssh-hardening)
4. [Generate SSH Keys](#step-3--generate-ssh-keys)
5. [Firewall (UFW)](#step-4--firewall-ufw)
6. [Fail2Ban](#step-5--fail2ban)
7. [Kernel Hardening (sysctl)](#step-6--kernel-hardening-sysctl)
8. [Shared Memory Hardening](#step-7--shared-memory-hardening)
9. [Disable Unnecessary Services](#step-8--disable-unnecessary-services)
10. [Automatic Security Updates](#step-9--automatic-security-updates)
11. [DigiByte-Specific Hardening](#step-10--digibyte-specific-hardening)
12. [Verify Everything](#step-11--verify-everything)
13. [Over-Hardening Warnings](#over-hardening-warnings)
14. [Optional Extras](#optional-extras)
15. [Maintenance](#maintenance)

---

## Before You Start

**This guide is for Linux VPS servers.** If you're running a DigiDollar oracle on a home Windows PC, I'd strongly recommend migrating to a Linux VPS before worrying about hardening. Oracle nodes need 24/7 uptime for a frozen roster — power outages, ISP instability, Windows Update reboots, no DDoS protection, and residential IP changes make home PCs a poor fit. Most major VPS providers (Vultr, Contabo, Hetzner, OVH, DigitalOcean) offer Ubuntu VPS plans for $5–15/month with built-in DDoS protection and near-perfect uptime.

**Tested on:** Ubuntu 24.04 LTS. Compatible with Ubuntu 26.04 LTS and other Debian-based distros. Minor differences between versions are noted throughout the guide where they apply.


**Prerequisites:**

- A VPS running Ubuntu 24.04 LTS (or similar)
- Root or sudo access
- DigiByte Core installed and synced (see [DIGIDOLLAR_ORACLE_SETUP.md](https://github.com/DigiByte-Core/digibyte/blob/feature/digidollar-v1/DIGIDOLLAR_ORACLE_SETUP.md))
- An SSH client on your local machine (PuTTY on Windows, Terminal on Mac/Linux)

**Important:** Before making SSH changes, always keep your current SSH session open and test the new config in a second session. If you lock yourself out, use your VPS provider's web console/VNC login to fix it.

---

## Step 1 — Create a Dedicated User

Don't run your oracle as root. I created a dedicated user with sudo access specifically for oracle operations.

```bash
# Create user (replace 'dgboperator' with your preferred username)
sudo adduser dgboperator

# Add to sudo group
sudo usermod -aG sudo dgboperator
```

Switch to the new user and verify:

```bash
su - dgboperator
sudo whoami
# Should output: root
```

From here on, everything runs as this user — never root directly.

---

## Step 2 — SSH Hardening

SSH is the front door to your VPS. I changed every default that matters.

### Move SSH Off Port 22

Every automated scanner on the internet hammers port 22. Moving to a custom port eliminates the vast majority of brute-force noise. Pick any unused port between 1024–65535.

Edit the SSH config:

```bash
sudo nano /etc/ssh/sshd_config
```

Find and set these values. Some may already exist and need changing, others you may need to add:

```
Port 5520                          # Pick your own port — not 22
LoginGraceTime 30                  # 30 seconds to authenticate, then disconnect
PermitRootLogin no                 # Never allow root login via SSH
MaxAuthTries 3                     # Lock out after 3 failed attempts per session
PubkeyAuthentication yes           # Allow key-based authentication
PasswordAuthentication no          # Disable password login entirely
KbdInteractiveAuthentication no    # Disable keyboard-interactive auth
X11Forwarding no                   # No GUI forwarding needed on a server
PrintMotd no                       # Suppress message of the day
ClientAliveInterval 300            # Send keepalive every 5 minutes
ClientAliveCountMax 2              # Disconnect after 2 missed keepalives (10 min idle timeout)
AllowUsers dgboperator             # ONLY this user can SSH in — whitelist
```

**`AllowUsers` is the most important line.** Even if someone guesses your port and has a valid key, they can't log in unless they're hitting the exact username on this whitelist.

### Test Before You Commit

**Do NOT close your current SSH session.** First, restart the SSH service:

```bash
sudo systemctl restart ssh

# If you can't connect after restarting, your system may use socket-activated SSH.
# In that case, run these instead:
sudo systemctl daemon-reload
sudo systemctl restart ssh.socket
```

Open a **second** terminal/PuTTY window and connect using your new port:

```bash
ssh -p 5520 dgboperator@your-vps-ip
```

If the new session works, you're good. If it doesn't, your original session is still open to fix things.

---

## Step 3 — Generate SSH Keys

Password authentication is disabled in Step 2, so you need SSH keys. Here's how I set mine up.

### Option A — RSA 4096 (Proven, Universal Compatibility)

**On your local machine** (not the VPS):

**PuTTY (Windows):**
1. Open **PuTTYgen**
2. Select **RSA** at the bottom
3. Set **Number of bits** to **4096**
4. Click **Generate** and move your mouse to create randomness
5. Add a passphrase (strongly recommended)
6. Click **Save private key** — save the `.ppk` file somewhere secure on your PC
7. Copy the entire contents of the **"Public key for pasting into OpenSSH authorized_keys file"** box

**Linux/macOS Terminal:**

```bash
ssh-keygen -t rsa -b 4096 -C "your-identifier"
```

### Option B — Ed25519 (Modern Best Practice)

Ed25519 is the current standard for new SSH keys. It's faster, smaller, and equally secure to RSA 4096 with just 256 bits. If you're setting up fresh and your SSH client supports it (all modern clients do), this is the recommended choice.

**PuTTY (Windows):**
1. Open **PuTTYgen**
2. Select **EdDSA** at the bottom
3. Ensure **255 bits** (Ed25519) is selected
4. Click **Generate**
5. Add a passphrase
6. Save the `.ppk` private key
7. Copy the public key from the box

**Linux/macOS Terminal:**

```bash
ssh-keygen -t ed25519 -C "your-identifier"
```

> **Note:** RSA 4096 is what I use on my oracle VPS and it's fully secure. Ed25519 is the newer algorithm and what I'd pick if starting fresh today. Either works — don't lose sleep over which one you chose. What matters is that you're using keys instead of passwords.

### Install the Public Key on Your VPS

On the VPS, as your oracle user:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
nano ~/.ssh/authorized_keys
```

Paste your public key (the long string starting with `ssh-rsa` or `ssh-ed25519`), save, and set permissions:

```bash
chmod 600 ~/.ssh/authorized_keys
```

Test the key login in a new session before closing your current one.

### Verify Your Key Size

To check what key type and size you're using:

```bash
ssh-keygen -l -f ~/.ssh/authorized_keys
```

Output looks like: `4096 SHA256:abc123... rsa-key-20260503 (RSA)` — the first number is your key size.

---

## Step 4 — Firewall (UFW)

I use UFW (Uncomplicated Firewall) to block everything except the ports my oracle actually needs.

### Install and Configure

```bash
sudo apt install ufw -y

# Default: deny all incoming, allow all outgoing
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH on your custom port (CRITICAL — do this before enabling UFW)
sudo ufw allow 5520/tcp comment 'SSH custom port'

# Allow DigiByte MainNet P2P
sudo ufw allow 12024/tcp comment 'DGB MainNet P2P'

# Enable the firewall
sudo ufw enable
```

**Warning:** If you enable UFW without allowing your SSH port first, you will lock yourself out. Always allow SSH before enabling.

### Verify

```bash
sudo ufw status verbose
```

Expected output:

```
Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), disabled (routed)

To                         Action      From
--                         ------      ----
5520/tcp                   ALLOW IN    Anywhere        # SSH custom port
12024/tcp                  ALLOW IN    Anywhere        # DGB MainNet P2P
```

### What About RPC?

**Don't open RPC ports in UFW.** DigiByte Core binds RPC to `127.0.0.1` (localhost) by default. This means only programs running on the VPS itself can talk to the RPC interface. There is no reason to expose RPC to the internet — and doing so is a serious security risk.

If your `digibyte.conf` doesn't have `rpcbind` or `rpcallowip` lines, you're already safe — the default is localhost-only. You can verify:

```bash
ss -tlnp | grep 14024
```

If the local address shows `127.0.0.1:14024` or `[::1]:14024`, RPC is not exposed. (Port number varies by network — 14024 for mainnet RPC, 14026 for testnet.)

---

## Step 5 — Fail2Ban

Fail2Ban monitors your SSH logs and automatically bans IPs that fail authentication too many times. On my VPS, it catches real brute-force attempts daily.

### Install

```bash
sudo apt install fail2ban -y
```

### Configure

Create a local config file (don't edit the defaults — they get overwritten on updates):

```bash
sudo nano /etc/fail2ban/jail.local
```

Add this:

```ini
[sshd]
enabled = true
port = 5520
filter = sshd
backend = systemd
maxretry = 3
bantime = 86400
findtime = 600

**What this means:**
- **maxretry = 3** — 3 failed attempts and you're banned
- **bantime = 86400** — banned for 24 hours (not the default 10 minutes)
- **findtime = 600** — the 3 attempts must happen within 10 minutes

I initially had `bantime = 3600` (1 hour) but found that attackers just waited an hour and tried again. 24 hours is much better for an oracle VPS where you're the only person who ever SSH's in.

### Start and Enable

```bash
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
```

### Verify

```bash
sudo fail2ban-client status sshd
```

You should see the jail active with `Currently banned` and `Total banned` counts. Give it a day and check back — you'll likely see bans already accumulating.

---

## Step 6 — Kernel Hardening (sysctl)

The Linux kernel has runtime parameters that control network behavior and security policies. Many defaults prioritize compatibility over security. I created a hardening config file that tightens the important ones.

```bash
sudo nano /etc/sysctl.d/99-oracle-hardening.conf
```

Add this:

```ini
# DigiDollar Oracle VPS Hardening

# Don't send ICMP redirects (this VPS is not a router)
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Disable Magic SysRq key (raw kernel access — not needed on a production server)
kernel.sysrq = 0

# Prevent core dumps from setuid programs (can leak sensitive data like wallet passphrases)
fs.suid_dumpable = 0
```

Apply immediately:

```bash
sudo sysctl --system
```

### What's Already Secure by Default (Ubuntu 24.04)

On a fresh Ubuntu 24.04 VPS, these are typically already set correctly — verify rather than assume:

```bash
sysctl net.ipv4.ip_forward              # Should be 0 (not a router)
sysctl net.ipv4.conf.all.accept_redirects    # Should be 0
sysctl net.ipv4.conf.all.accept_source_route # Should be 0
sysctl net.ipv4.tcp_syncookies          # Should be 1 (SYN flood protection)
```

If any of those are wrong, add them to `99-oracle-hardening.conf`.

### A Note on `log_martians`

Many hardening guides recommend enabling `net.ipv4.conf.all.log_martians = 1` to log packets with spoofed source addresses. I have it in my config, but on some cloud providers (including Contabo), the cloud networking stack resets this value on every boot. If it doesn't persist on your VPS, don't worry — the actual protection comes from `rp_filter` (reverse path filtering), which Ubuntu 24.04 enables by default in `/etc/sysctl.d/10-network-security.conf`. That's what drops the spoofed packets. `log_martians` just writes a note about packets that are already being blocked.

---

## Step 7 — Shared Memory Hardening

Shared memory (`/dev/shm`) can be used by attackers to stage and execute malicious code. I restrict it so nothing can be executed from there.

Check current state:

```bash
mount | grep shm
```

If the output doesn't include `noexec`, add it:

```bash
echo 'tmpfs /dev/shm tmpfs defaults,noexec,nosuid,nodev 0 0' | sudo tee -a /etc/fstab
sudo mount -o remount,noexec,nosuid,nodev /dev/shm
```

Verify:

```bash
mount | grep shm
```

Should now show: `tmpfs on /dev/shm type tmpfs (rw,nosuid,nodev,noexec,...)`

---

## Step 8 — Disable Unnecessary Services

### Apport (Ubuntu Crash Reporter)

Ubuntu's crash reporter (`apport`) overrides the `suid_dumpable` kernel setting on boot, which re-enables core dumps from privileged processes. An oracle VPS doesn't need to send crash reports to Canonical.

```bash
sudo systemctl disable apport
sudo systemctl stop apport
```

Verify it's gone:

```bash
systemctl is-enabled apport
# Should output: disabled
```

---

## Step 9 — Automatic Security Updates

I use Ubuntu's `unattended-upgrades` to automatically install security patches. This way, critical vulnerabilities get patched even if I don't log in for a few days.

### Install

```bash
sudo apt install unattended-upgrades -y
```

### Configure

```bash
sudo nano /etc/apt/apt.conf.d/20auto-upgrades
```

Should contain:

```
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
```

This checks for updates daily and installs security patches automatically.

### Manual Updates

Automatic updates only cover security patches. Periodically run full updates manually:

```bash
sudo apt update && sudo apt upgrade
```

If a kernel update is installed, reboot to load it:

```bash
sudo reboot
```

After rebooting, verify your oracle comes back up automatically (see [Verify Everything](#step-11--verify-everything)).

---

## Step 10 — DigiByte-Specific Hardening

These are security steps specific to running a DigiByte oracle node.

### Wallet Passphrase File Permissions

If you store your wallet passphrase in a file for automated oracle startup (which I do for systemd auto-start), lock the permissions:

```bash
chmod 600 /home/dgboperator/.oracle_passphrase
chown dgboperator:dgboperator /home/dgboperator/.oracle_passphrase
```

This means only your oracle user can read it — no other user or process on the system.

### Systemd Service Hardening

My `digibyted.service` includes these hardening flags in the `[Service]` section:

```ini
[Service]
Restart=on-failure
RestartSec=30
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
```

**What these do:**
- **Restart=on-failure / RestartSec=30** — if digibyted crashes, systemd waits 30 seconds and restarts it automatically
- **PrivateTmp=true** — gives digibyted its own `/tmp` directory, isolated from other processes
- **ProtectSystem=full** — makes `/usr`, `/boot`, and `/etc` read-only for the service
- **NoNewPrivileges=true** — prevents the process from gaining additional privileges after startup

### Wallet Backups

I keep encrypted wallet backups in multiple locations:

- On the VPS itself (the live copy)
- On my local machine (downloaded via SFTP/SCP)
- On an encrypted USB drive stored offline

Your oracle wallet contains the signing key that makes you an oracle operator. If you lose it, you lose your oracle slot. Back it up.

```bash
# Copy wallet from VPS to local machine (run from your local machine)
scp -P 5520 dgboperator@your-vps-ip:~/.digibyte/wallets/oracle/wallet.dat ./wallet-backup.dat
```

Or use WinSCP/FileZilla for a graphical transfer.

---

## Step 11 — Verify Everything

After completing all steps — and especially after every reboot — run this verification block:

```bash
echo "=== HARDENING VERIFY — $(date) ===" && \
echo "" && \
echo "=== SSH ===" && \
sudo systemctl status ssh --no-pager | head -3 && \
echo "" && \
echo "=== FAIL2BAN ===" && \
sudo systemctl status fail2ban --no-pager | head -3 && \
grep bantime /etc/fail2ban/jail.local && \
echo "" && \
echo "=== SYSCTL ===" && \
sysctl net.ipv4.conf.all.send_redirects && \
sysctl kernel.sysrq && \
sysctl fs.suid_dumpable && \
echo "" && \
echo "=== SHARED MEMORY ===" && \
mount | grep shm && \
echo "" && \
echo "=== UFW ===" && \
sudo ufw status | head -8 && \
echo "" && \
echo "=== ORACLE ===" && \
digibyte-cli listoracle 2>/dev/null | grep -E '"running"|"oracle_id"' || \
echo "RPC not ready — daemon may still be loading" && \
echo "" && \
echo "=== UPTIME ===" && \
uptime
```

**Expected results:**

| Check | Expected Value |
|-------|---------------|
| SSH | active (running) |
| Fail2Ban | active (running), bantime = 86400 |
| send_redirects | 0 |
| kernel.sysrq | 0 |
| suid_dumpable | 0 |
| /dev/shm | noexec,nosuid,nodev |
| UFW | active, deny incoming |
| Oracle | "running": true |
### Take a Snapshot

After completing all hardening steps and verifying with a reboot, take a snapshot through your VPS provider's control panel. This gives you a known-good restore point. If a future upgrade or config change breaks something, you can roll back to a fully hardened, working state. Most providers limit the number of snapshots (Contabo allows 2), so delete the oldest before creating a new one. I take a fresh snapshot after every major change — binary upgrades, hardening updates, or config migrations.
---

## Over-Hardening Warnings

Not every security recommendation from a generic hardening guide applies to an oracle node. Here are things I specifically **do not** do on my oracle VPS, and why.

### Don't Restrict Outbound Traffic

Your oracle **must** reach cryptocurrency exchange APIs (Binance, Coinbase, Kraken, etc.) over HTTPS port 443 to fetch price data. If you add outbound firewall rules, you will break your oracle's price feed and it will stop contributing to consensus.

### Don't Put AppArmor Profiles on digibyted

Unless you deeply understand AppArmor, a restrictive profile can silently block RPC calls, P2P connections, or file access. Your oracle goes down with no obvious error in the logs. The systemd hardening flags in Step 10 provide isolation without this risk.

### Don't Rate-Limit or Restrict the P2P Port

Your oracle needs to accept inbound peer connections on the DigiByte P2P port (12024 for mainnet). Don't add connection limits, geo-blocking, or rate limiting to this port. Other oracle nodes and network peers need to reach you.

### Don't Set Fail2Ban to Permanent Bans

Setting `bantime = -1` (permanent) means any banned IP stays banned forever — including potentially your own IP if your connection hiccups during authentication. Unless you have a guaranteed backup access method (like your VPS provider's web console), stick with 24-hour bans. It's enough to stop attackers without risking locking yourself out.

### Don't Disable ICMP Entirely

Some hardening guides recommend blocking all ICMP. This breaks path MTU discovery, which can cause silent packet drops and weird P2P networking issues. Leave ICMP at default settings.

### Don't Over-Restrict SSH MaxSessions

Some guides recommend `MaxSessions 2`. If you ever use SCP/SFTP to transfer files while you're also SSH'd in (which you will — wallet backups, script uploads), you need concurrent sessions. Leave it at the default or no lower than 4.

---

## Optional Extras

These aren't critical for oracle security but are worth knowing about.

### Lynis — Security Audit Tool

Lynis scans your system and gives a hardening score with specific recommendations. It's a good way to find things you might have missed.

```bash
sudo apt install lynis -y
sudo lynis audit system
```

Run it periodically (monthly or after major changes). Don't blindly implement every suggestion — some conflict with oracle node requirements.

### Rootkit Scanner

Lightweight tools to check for rootkits:

```bash
sudo apt install rkhunter -y
sudo rkhunter --check
```

Can be automated via cron for periodic scans. Not critical, but good hygiene.

### Login Banner

Some administrators add a legal warning banner to SSH login. It's cosmetic but some compliance frameworks require it:

```bash
sudo nano /etc/issue.net
```

Add something like:

```
Authorized access only. All activity is monitored and logged.
```

Then in `/etc/ssh/sshd_config`:

```
Banner /etc/issue.net
```

Restart SSH to apply (`sudo systemctl restart ssh`, or `sudo systemctl daemon-reload && sudo systemctl restart ssh.socket` on Ubuntu 26.04+).

---

## Maintenance

Security isn't a one-time setup. Here's what I do regularly:

### Weekly

- Check Fail2Ban status: `sudo fail2ban-client status sshd`
- Review failed SSH attempts: `sudo grep 'Failed' /var/log/auth.log | tail -20`
- - If `/var/log/auth.log` doesn't exist (Ubuntu 26.04+ journal-only), use: `journalctl -u ssh --no-pager --since "7 days ago" | grep 'Failed' | tail -20`
- Verify oracle is running: `digibyte-cli listoracle`

### Monthly

- Run full system updates: `sudo apt update && sudo apt upgrade`
- Reboot if kernel was updated, then verify oracle auto-starts
- Review UFW rules: `sudo ufw status verbose`

### After Every Reboot

- Run the verification block from Step 11
- Check Discord/monitoring alerts fired correctly
- Verify oracle is running and reporting price

### After Every DigiByte Binary Upgrade

- Verify systemd services restart correctly
- Check oracle is running: `digibyte-cli listoracle`
- If oracle shows `"running": false`, manually restart the oracle service:

```bash
sudo systemctl restart dgb-oracle.service
```

---

## Summary

Here's everything this guide covers, in one table:

| Layer | What | Why |
|-------|------|-----|
| User | Dedicated non-root user with sudo | Least privilege |
| SSH | Custom port, key-only auth, AllowUsers whitelist | Eliminates brute-force surface |
| SSH Keys | RSA 4096 or Ed25519 | Replaces password authentication |
| Firewall | UFW default deny, only required ports open | Blocks all unexpected traffic |
| Fail2Ban | 3 attempts → 24-hour ban | Stops brute-force attackers |
| Kernel | sysctl hardening (redirects, SysRq, core dumps) | Closes kernel-level attack vectors |
| Shared Memory | noexec on /dev/shm | Prevents code execution in shared memory |
| Services | Apport disabled | Stops crash reporter from weakening core dump protection |
| Updates | Unattended security upgrades | Patches vulnerabilities automatically |
| DigiByte | RPC localhost-only, wallet file permissions, systemd hardening | Protects oracle-specific assets |

My oracle VPS gets hammered daily by automated scanners and brute-force bots. With this setup, they hit a wall at every layer — wrong port, wrong username, no password to guess, banned after 3 tries, and firewall blocking everything else. The oracle keeps running through all of it.

If you follow this guide and verify with Step 11, your oracle node will be properly locked down/hardened for mainnet.

---

*Built by digibyte-maxi — Oracle Slot 17*
*[digidollar-oracle-tools](https://github.com/BaumerCrypto/digidollar-oracle-tools)*

Version: v1.2
