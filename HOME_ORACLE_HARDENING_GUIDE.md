# Home Oracle Hardening Guide

**For DigiByte DigiDollar oracle operators running from home**

Written by digibyte-maxi (Oracle Slot 17) — 2026-06-03

Covers: Linux (Ubuntu/Debian) · Windows · macOS

---

> **"We are as strong as the weakest link."** — Aussie Epic
>
> This guide exists because not every oracle operator can afford VPS hosting — but every operator can harden what they have. A hardened home setup isn't as reliable as a hardened VPS, and I'll be honest about that throughout this guide. But a hardened home oracle is infinitely better than an unhardened one, and every additional node strengthens the DigiDollar network.

---

## Who This Guide Is For

You're running a DigiByte DigiDollar oracle node on a physical or virtual machine at home. Your setup probably looks something like this:

- A Linux, Windows, or macOS machine on your home network (192.168.x.x or 10.x.x.x)
- Connected through a consumer modem/router from your ISP
- A UPS battery backup for power outages
- You access the machine via Remote Desktop (xRDP, Windows RDP, VNC) or by walking up to it — not SSH
- You've port-forwarded the DigiByte P2P port through your router so other nodes can reach you
- Your ISP gives you a dynamic IP address (it changes periodically)

If this sounds like your setup, this guide is for you.

**If you're running on a VPS** (Contabo, Hetzner, Vultr, DigitalOcean, etc.), use my [VPS Hardening Guide](https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/ORACLE_HARDENING_GUIDE.md) instead — it covers SSH hardening, Fail2Ban, and VPS-specific security that doesn't apply at home.

---

## Before You Start — An Honest Warning

I run my oracle on a VPS. I chose a VPS because oracle nodes need to be online 24/7/365, and the frozen roster means there's no on-chain mechanism to swap out a dead oracle until Stage 2 ships. A VPS gives me:

- Static IP address
- Provider-level DDoS protection
- 99.9%+ uptime SLA
- No power outage concerns
- No ISP maintenance windows
- No consumer router between my node and the internet

Home setups have real disadvantages for oracle operation: ISP outages, dynamic IPs, power cuts, router reboots, and the fact that your consumer router is the only thing between your oracle and the open internet.

**I'm not saying "don't run from home."** I'm saying: understand the trade-offs, harden what you can, and if your home oracle goes down and stays down, consider migrating to a VPS. A $5-15/month VPS is cheaper than the cost to the network of a missing oracle in a 7-of-21 quorum.

With that said — let's harden your setup. A little hardening to fully locked down tight... it all makes a difference. 🔒

---

## Home vs VPS — What's Different

Understanding your attack surface is the first step to protecting it. Here's what's different about running from home:

| Concern | VPS | Home |
|---------|-----|------|
| IP address | Static (fixed) | Dynamic (changes) |
| DDoS protection | Provider includes basic protection | None — ISP provides nothing |
| Firewall | Host firewall only (UFW, iptables) | Router NAT + host firewall (two layers) |
| Physical access | Provider datacenter (locked) | Anyone in your house |
| Network neighbors | Isolated (your VPS only) | Every device on your WiFi |
| Power | Datacenter UPS + generators | Your UPS battery (minutes, not hours) |
| Remote access | SSH over the internet | RDP/VNC on local network (or VPN) |
| Port forwarding | Not needed (public IP) | Required for P2P connectivity |
| OS variety | Almost always Linux | Linux, Windows, or macOS |

**The two big things that matter:**
1. Your router is your perimeter — if it's compromised, everything behind it is exposed
2. Only forward the ports you absolutely must — every forwarded port is a hole in your perimeter

---

## Guide Structure — Three Tiers

This guide is organized into three tiers. Do Tier 1 first. It takes 30 minutes and covers the most critical items. Tier 2 adds meaningful protection and takes another hour. Tier 3 is for operators who want to go further.

| Tier | What | Time | Priority |
|------|------|------|----------|
| **Tier 1 — Essential** | Firewall, port forwarding, time sync, auto-updates, service restart | ~30 min | Do this today |
| **Tier 2 — Recommended** | SSH access, router hardening, UPS graceful shutdown, kernel hardening | ~1 hour | Do this week |
| **Tier 3 — Advanced** | VLAN isolation, DDNS, VPN, monitoring | Varies | When you're ready |

---

## Tier 1 — Essential Hardening

> 📊 **[View Tier 1 Network Diagram](https://htmlpreview.github.io/?https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/network-tier1-essential.html)** — see what a basic home oracle network looks like

These are the minimum steps every home oracle operator should complete. If you do nothing else, do these.

---

### Step 1: Dedicated User Account

Don't run your oracle node as root (Linux), Administrator (Windows), or your daily user account. Create a dedicated account with limited privileges.

**Why:** If digibyted is ever exploited, the attacker inherits the permissions of the user running it. A dedicated account with no sudo/admin rights limits the blast radius.

**Linux (Ubuntu/Debian):**

```bash
# Create a dedicated user
sudo adduser dgboracle

# DO NOT add to sudo group unless you need it for initial setup
# If you do need sudo temporarily:
sudo usermod -aG sudo dgboracle
# Remove sudo after setup is complete:
sudo deluser dgboracle sudo
```

Log in as `dgboracle` for all oracle operations. Install DigiByte, configure your node, and run everything under this account.

**Windows:**

1. Open **Settings → Accounts → Other users → Add account** (Windows 11) or **Settings → Accounts → Family & other users → Add someone else to this PC** (Windows 10)
2. Click **"I don't have this person's sign-in information"** → **"Add a user without a Microsoft account"**
3. Create a local account named `dgboracle` with a strong password
4. Leave it as a **Standard User** — do NOT make it an Administrator
5. Log in as `dgboracle` to install and run your oracle

> **Windows tip:** If you need to install software or change system settings, use "Run as administrator" on individual tasks rather than making the oracle account an admin.

**macOS:**

1. Open **System Settings → Users & Groups**

> **macOS version note:** This guide references "System Settings" throughout — that's the name used in macOS Ventura (13) and newer. If you're running macOS Monterey (12) or older, look for "System Preferences" instead. All paths are otherwise identical.
2. Click the **+** button (you'll need to unlock with your admin password)
3. Set **New Account** to **Standard**
4. Name it `dgboracle`
5. Set a strong password
6. Log in as `dgboracle` to install and run your oracle

---

### Step 2: Host Firewall — Only Allow What's Needed

Your machine's firewall is your last line of defense if your router is misconfigured or compromised. Enable it and lock it down.

**The rule is simple: only allow inbound connections on the DigiByte P2P port. Block everything else inbound.**

- **Mainnet P2P port:** 12024
- **Testnet26 P2P port:** 12033

**Linux (UFW):**

```bash
# Install UFW if not present
sudo apt install ufw -y

# Set defaults
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow DigiByte P2P (mainnet)
sudo ufw allow 12024/tcp comment "DigiByte MainNet P2P"

# Allow DigiByte P2P (testnet — keep running alongside mainnet for future testing)
sudo ufw allow 12033/tcp comment "DigiByte TestNet P2P"

# Enable
sudo ufw enable

# Verify
sudo ufw status verbose
```

Your output should show only the P2P ports allowed inbound. If you also use SSH locally (see Tier 2), you'll add that port too — but only from your local subnet.

> **xRDP users (Aussie Epic's setup):** Do NOT add a UFW rule for port 3389. xRDP should only be accessible on your local network, and since you're not port-forwarding it through your router (right?), the host firewall doesn't need to allow it from the internet. If you DO want UFW to allow xRDP from your local network only:
> ```bash
> sudo ufw allow from 192.168.0.0/16 to any port 3389 comment "xRDP local only"
> ```
> Adjust `192.168.0.0/16` to match your actual local subnet if needed (e.g., `192.168.1.0/24`).

**Windows Firewall:**

Windows Firewall is enabled by default on modern Windows. Verify and configure:

1. Open **Windows Security → Firewall & network protection**
2. Confirm the firewall is **On** for all profiles (Domain, Private, Public)
3. Click **Advanced settings** to open Windows Firewall with Advanced Security

Create inbound rules for DigiByte P2P (create one rule for each port):

**Mainnet rule:**
1. Click **Inbound Rules → New Rule**
2. Select **Port → TCP → Specific local ports: 12024**
3. Select **Allow the connection**
4. Check all profiles (Domain, Private, Public)
5. Name it: **DigiByte MainNet P2P**
6. Click Finish

**Testnet rule (repeat the steps above):**
1. Click **Inbound Rules → New Rule**
2. Select **Port → TCP → Specific local ports: 12033**
3. Select **Allow the connection**
4. Check all profiles (Domain, Private, Public)
5. Name it: **DigiByte TestNet P2P**
6. Click Finish

Or via PowerShell (run as Administrator):

```powershell
# Allow DigiByte P2P (mainnet)
New-NetFirewallRule -DisplayName "DigiByte MainNet P2P" -Direction Inbound -Protocol TCP -LocalPort 12024 -Action Allow

# Allow DigiByte P2P (testnet)
New-NetFirewallRule -DisplayName "DigiByte TestNet P2P" -Direction Inbound -Protocol TCP -LocalPort 12033 -Action Allow

# Verify
Get-NetFirewallRule -DisplayName "DigiByte*" | Format-Table Name, DisplayName, Enabled, Direction, Action
```

**macOS (Application Firewall):**

macOS has two firewalls: the Application Firewall (GUI) and `pf` (packet filter, command-line). The Application Firewall is the simpler option:

1. Open **System Settings → Network → Firewall**
2. Toggle **Firewall** to **On**
3. Click **Options**
4. Set **"Block all incoming connections"** to **Off** (you need P2P inbound)
5. Add `digibyted` to the list and set to **"Allow incoming connections"**

For more granular control with `pf`, create a rules file:

```bash
# Edit pf rules (requires admin)
sudo nano /etc/pf.conf

# Add at the end (before any final block rules):
pass in on en0 proto tcp from any to any port 12024
pass in on en0 proto tcp from any to any port 12033

# Reload
sudo pfctl -f /etc/pf.conf
sudo pfctl -e
```

> **macOS note:** `pf` rules don't persist across reboots by default. You'd need a launchd plist to reload them on startup. For most home operators, the Application Firewall is sufficient.

> **Why are we opening both mainnet and testnet ports?** Testnet is where all future DigiByte releases get tested before mainnet deployment. If oracle operators shut down their testnet nodes after mainnet launches, there's nobody to test with. Keep both ports open so you can run testnet and mainnet side by side. If you decide not to participate in testnet, remove the 12033 rules from your firewall and router.

---

### Step 3: Port Forwarding — The Most Important Step

**This is where most home operators get it wrong.** Your router's port forwarding configuration determines what the outside world can reach on your home network.

**The golden rule: Only forward the DigiByte P2P port. Forward nothing else.**

| Port | Forward? | Why |
|------|----------|-----|
| **12024** (mainnet P2P) | **YES** | Other nodes need to connect to your oracle |
| **12033** (testnet26 P2P) | **YES** (testnet only) | Same — testnet P2P |
| 3389 (RDP/xRDP) | **NEVER** | Exposes Remote Desktop to the entire internet |
| 22 (SSH) | **NEVER** (unless VPN — see Tier 3) | Exposes SSH to brute force |
| 8332/14022/etc (RPC) | **NEVER** | Exposes your node's RPC interface — catastrophic |

**How to set up port forwarding (general steps — every router is different):**

1. Log into your router's admin panel (usually `192.168.0.1` or `192.168.1.1` in your browser)
2. Find the **Port Forwarding** section (sometimes under "NAT," "Virtual Server," or "Advanced")
3. Create a new rule:
   - **External port:** 12024
   - **Internal IP:** Your oracle machine's local IP (e.g., 192.168.1.100)
   - **Internal port:** 12024
   - **Protocol:** TCP
   - **Enabled:** Yes
4. Save and apply

> **Running testnet and mainnet at the same time?** DanGB confirmed in Gitter that operators should continue running testnet oracles alongside mainnet. Both can run on the same machine since they use different ports (12024 mainnet, 12033 testnet26). Port forwarding is per-port, not per-server — you can forward both ports to the same machine. Create two rules in your router:
>
> | Rule | External Port | Internal IP | Internal Port |
> |------|--------------|-------------|---------------|
> | Mainnet P2P | 12024 | 192.168.1.100 | 12024 |
> | Testnet P2P | 12033 | 192.168.1.100 | 12033 |
>
> This works on virtually every consumer router. If yours only supports a single port forwarding rule (very rare on modern hardware), you'd need to choose one — and mainnet takes priority.

> **Important: Give your oracle machine a static local IP.** If your machine gets a new IP from DHCP (e.g., 192.168.1.105 instead of .100), the port forward breaks and your oracle becomes unreachable. Set a static IP on the machine itself, or use your router's DHCP reservation feature to always assign the same IP to your machine's MAC address.

**Setting a static local IP:**

**Linux:**

```bash
# Using netplan (Ubuntu 18.04+)
sudo nano /etc/netplan/01-netcfg.yaml
```

```yaml
network:
  version: 2
  ethernets:
    eth0:  # Your interface name — check with 'ip a'
      dhcp4: no
      addresses:
        - 192.168.1.100/24
      routes:
        - to: default
          via: 192.168.1.1  # Your router's IP
      nameservers:
        addresses:
          - 8.8.8.8
          - 1.1.1.1
```

```bash
sudo netplan apply
```

**Windows:**

1. Open **Settings → Network & Internet → Ethernet** (or WiFi)
2. Click **Edit** next to IP assignment
3. Switch to **Manual**
4. Toggle **IPv4** on
5. Enter:
   - IP address: `192.168.1.100`
   - Subnet mask: `255.255.255.0`
   - Gateway: `192.168.1.1` (your router)
   - Preferred DNS: `8.8.8.8`
   - Alternate DNS: `1.1.1.1`

Or via PowerShell (run as Administrator):

```powershell
# Find your adapter name
Get-NetAdapter

# Set static IP (replace "Ethernet" with your adapter name)
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.1.100 -PrefixLength 24 -DefaultGateway 192.168.1.1
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 8.8.8.8, 1.1.1.1
```

**macOS:**

1. Open **System Settings → Network → Ethernet** (or WiFi)
2. Click **Details**
3. Go to **TCP/IP**
4. Change **Configure IPv4** to **Manually**
5. Enter:
   - IP Address: `192.168.1.100`
   - Subnet Mask: `255.255.255.0`
   - Router: `192.168.1.1`
6. Go to **DNS** and add `8.8.8.8` and `1.1.1.1`
7. Click **OK**

> **Verify your port forward works:** After setting it up, use an external port checker like [yougetsignal.com/tools/open-ports/](https://www.yougetsignal.com/tools/open-ports/) or [canyouseeme.org](https://canyouseeme.org) to confirm port 12024 (or 12033) is reachable from the outside while digibyted is running.

---

### Step 4: NTP Time Sync — Keep Your Clock Accurate

> 🙏 **Shoutout to Aussie Epic** for flagging this one. He caught that time sync was missing from my VPS hardening guide and shared his own experience debugging clock drift on his servers. Good catch :thumbsup:

**This is critically important for oracle nodes.** Oracle price bundles have a 3,600-second (1 hour) freshness limit. If your machine's clock drifts even slightly, you risk:

- Submitting bundles that other nodes reject as "too old" (`bad-oracle-timestamp`)
- Accepting stale bundles that should be rejected
- Contributing to chain stalls

On testnet25, a bundle that was just 58 seconds past the 3,600-second limit killed the chain at block 34,029. Clock accuracy matters.

VPS providers typically run NTP synchronization automatically. Home machines may not, or may sync infrequently. Fix this.

**Linux (Ubuntu/Debian):**

Ubuntu includes `systemd-timesyncd` by default. Verify it's running and configured:

```bash
# Check current time sync status
timedatectl status
```

Look for:
- `NTP service: active` — good
- `System clock synchronized: yes` — good

If NTP is not active:

```bash
# Enable and start
sudo timedatectl set-ntp on

# Verify
timedatectl status
```

For stricter accuracy, install `chrony` instead (better for time-critical applications):

```bash
sudo apt install chrony -y
sudo systemctl enable chrony
sudo systemctl start chrony

# Check sync status
chronyc tracking
```

`chrony` polls more frequently and corrects drift faster than the default `systemd-timesyncd`. For an oracle node, I recommend chrony.

> **Automated NTP monitoring:** If you're running my [oracle-monitor.sh](https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/oracle-monitor.sh), NTP is already monitored automatically as Check #10 — it fires Discord alerts on desync and recovery. You can skip the cron job below.
>
> **Cron job for basic monitoring (Aussie Epic's suggestion):** If you're NOT running oracle-monitor.sh and want a lightweight NTP check, add a simple cron job. The email option gives you automated alerts:
> ```bash
> # Add to crontab (crontab -e)
> 0 */6 * * * /usr/bin/timedatectl status | grep -q "synchronized: yes" || echo "TIME SYNC FAILED on $(hostname)" | mail -s "NTP Alert" your@email.com
> ```
> If you don't have mail configured, the log option is a basic fallback — but you'll need to check the file manually:
> ```bash
> 0 */6 * * * /usr/bin/timedatectl status | grep -q "synchronized: yes" || echo "$(date): TIME SYNC FAILED" >> /home/dgboracle/time-sync.log
> ```

**Windows:**

Windows Time Service (`w32tm`) handles NTP. Verify and configure:

```powershell
# Check status
w32tm /query /status

# If not syncing, configure to use pool.ntp.org
w32tm /config /manualpeerlist:"pool.ntp.org" /syncfromflags:MANUAL /reliable:YES /update

# Restart the service
Restart-Service w32time

# Force an immediate sync
w32tm /resync

# Verify
w32tm /query /status
```

Ensure the Windows Time service starts automatically:

```powershell
Set-Service -Name w32time -StartupType Automatic
```

**macOS:**

macOS syncs time via NTP by default. Verify:

1. Open **System Settings → General → Date & Time**
2. Ensure **"Set time and date automatically"** is toggled **On**
3. The server should be `time.apple.com` or you can change it to `pool.ntp.org`

Via terminal:

```bash
# Check if NTP is enabled
sudo systemsetup -getusingnetworktime

# Enable if not
sudo systemsetup -setusingnetworktime on

# Set NTP server
sudo systemsetup -setnetworktimeserver pool.ntp.org

# Force sync
sudo sntp -sS pool.ntp.org
```

---

### Step 5: Automatic Security Updates

Keeping your OS patched is one of the most effective security measures. Enable automatic updates so critical patches apply without your intervention.

**Linux (Ubuntu/Debian):**

```bash
# Install unattended-upgrades
sudo apt install unattended-upgrades -y

# Enable
sudo dpkg-reconfigure -plow unattended-upgrades
# Select "Yes"

# Verify config
cat /etc/apt/apt.conf.d/20auto-upgrades
```

Expected output:

```
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
```

This applies security patches automatically. It won't upgrade your kernel or do major version upgrades — just security fixes.

**Windows:**

1. Open **Settings → Windows Update** (Windows 11) or **Settings → Update & Security → Windows Update** (Windows 10)
2. Click **Advanced options**
3. Enable **"Receive updates for other Microsoft products"**
4. Under **Active hours**, set times when you DON'T want restarts (e.g., if your oracle runs 24/7, consider scheduling update restarts for a low-activity time)
5. Optionally enable **"Download updates over metered connections"** if on limited bandwidth

Windows will auto-install security updates. Just make sure it's not disabled.

**macOS:**

1. Open **System Settings → General → Software Update** (macOS Ventura 13 and newer; older versions: **System Preferences → Software Update**)
2. Click **Automatic Updates** (the "i" icon)
3. Enable all options:
   - Check for updates
   - Download new updates when available
   - Install macOS updates
   - Install Security Responses and system files

---

### Step 6: Auto-Restart digibyted on Boot and Crash

Your oracle needs to start automatically when the machine boots (especially after power outages and UPS shutdowns) and restart if it crashes.

**Linux (systemd):**

Create `/etc/systemd/system/digibyted.service`:

```ini
[Unit]
Description=DigiByte Core Daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
User=dgboracle
Group=dgboracle
ExecStart=/usr/local/bin/digibyted -daemon -conf=/home/dgboracle/.digibyte/digibyte.conf
ExecStop=/usr/local/bin/digibyte-cli stop
Restart=on-failure
RestartSec=30
TimeoutStartSec=120
TimeoutStopSec=120
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable digibyted.service
sudo systemctl start digibyted.service
```

Then create the oracle startup service at `/etc/systemd/system/dgb-oracle.service`:

```ini
[Unit]
Description=DigiByte Oracle Startup
After=digibyted.service
Requires=digibyted.service

[Service]
Type=oneshot
User=dgboracle
ExecStart=/home/dgboracle/start-oracle.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable dgb-oracle.service
```

> **Ubuntu 26.04 note:** If using `ssh.socket` (socket activation), service ordering is slightly different. This doesn't affect digibyted services — just be aware if you see `ssh.socket` instead of `ssh.service` in other guides.

**Windows (NSSM — Non-Sucking Service Manager):**

Windows doesn't natively run console applications as services. Use NSSM:

1. Download NSSM from [nssm.cc](https://nssm.cc/download)
2. Extract to `C:\nssm\`
3. Open Command Prompt as Administrator:

```cmd
C:\nssm\nssm.exe install DigiByteDaemon

# In the GUI that opens:
# Path: C:\path\to\digibyted.exe
# Startup directory: C:\path\to\digibyte\
# Arguments: -conf=C:\Users\dgboracle\AppData\Roaming\DigiByte\digibyte.conf
# Service name: DigiByteDaemon
```

4. Go to the **Exit** tab: set **Restart: Restart application**
5. Go to the **Log on** tab: set to run as the `dgboracle` user
6. Click **Install service**

```cmd
# Start the service
net start DigiByteDaemon

# Verify
sc query DigiByteDaemon
```

> ### A Note on DigiByte-Qt (Wallet GUI) vs digibyted (Daemon)
>
> Several oracle operators might have created their oracle keys using the Qt wallet (File → Create Wallet → Debug Console → `createoraclekey`). If that's you, you might be running your oracle through Qt instead of `digibyted`. This works — but it has significant limitations for 24/7 oracle operation.
>
> **The problem:** Qt is a GUI application. It requires a logged-in user session to run. If your machine reboots at 3 AM (power outage, Windows Update, crash), Qt does not start by itself. Your oracle stays offline until you walk up to the machine, log in, open Qt, unlock the wallet, and start the oracle. With a frozen roster and no on-chain backfill, that's a missing node the network can't replace.
>
> **digibyted (the daemon)** runs as a background service — no GUI, no logged-in user required. Combined with NSSM (Windows) or systemd (Linux) or launchd (macOS), it auto-starts on boot, auto-restarts on crash, and with a startup script that unlocks the wallet and runs `startoracle`, the entire recovery chain is automated end-to-end.
>
> **My recommendation: switch to digibyted for oracle operation.** Your oracle key lives in the wallet file, not in Qt — the same wallet works with both Qt and digibyted. You don't need to regenerate anything. Just install digibyted, point it at the same data directory and wallet, and set up the service.
>
> **If you prefer to keep using Qt**, here's how to minimize downtime:
>
> 1. **Add Qt to Windows Startup:** Press Win+R → type `shell:startup` → create a shortcut to `digibyte-qt.exe` in that folder. Qt will launch on login.
> 2. **Auto-load the wallet:** Add `wallet=oracle` to your `digibyte.conf`. Qt will automatically load the oracle wallet on startup.
> 3. **Auto-start behavior (since RC25):** If the wallet is **unencrypted**, the oracle auto-starts when the wallet loads — no manual intervention needed. If the wallet is **encrypted**, you must manually unlock it first (via the Qt unlock dialog or Debug Console: `walletpassphrase "yourpassphrase" 0`), then the oracle auto-starts.
> 4. **Windows auto-login (security tradeoff):** You can set Windows to auto-login your `dgboracle` user (Settings → Accounts → Sign-in options → disable password on wake). Combined with Qt in Startup and an unencrypted wallet, this gives you unattended recovery. But it means anyone with physical access to your machine has access to your oracle signing key.
>
> **The honest tradeoff:**
>
> | Setup | Unattended Recovery | Security |
> |-------|-------------------|----------|
> | digibyted + encrypted wallet + service + startup script | ✅ Fully automated | ✅ Passphrase protected |
> | Qt + unencrypted wallet + auto-login + Startup | ✅ Mostly automated (needs login) | 🔴 **Not recommended** — no passphrase, anyone with physical access owns your oracle key |
> | Qt + encrypted wallet | ❌ Manual unlock after every reboot | ✅ Passphrase protected |
>
> **I strongly recommend against running an unencrypted oracle wallet.** Yes, it makes auto-start easier with Qt — but your oracle signing key sits on disk with zero protection. Anyone with physical access to your machine (or malware) can extract it. Always encrypt your wallet. Always.
>
> For a frozen-roster oracle that needs to be online 24/7, `digibyted` daemon with an encrypted wallet and automated startup is the right answer.
>
> **⚠️ Community testing needed:** I run my oracle on a VPS with `digibyted`, not Qt. The Qt wallet guidance above is based on the official oracle setup documentation and the auto-start behavior confirmed in the codebase (since RC25). I haven't tested Qt oracle recovery on every OS myself. If you're running your oracle through Qt and find something that doesn't match this guide — crashes, wallet lock behavior, auto-start issues — let me know on Gitter (digibyte-maxi) or open an issue on my GitHub. The more real-world Qt testing we get, the better this section becomes.

**macOS (launchd):**

Create `~/Library/LaunchAgents/com.digibyte.daemon.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.digibyte.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/digibyted</string>
        <string>-daemon</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>UserName</key>
    <string>dgboracle</string>
    <key>StandardOutPath</key>
    <string>/tmp/digibyted.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/digibyted.stderr.log</string>
</dict>
</plist>
```

```bash
# Load the service
launchctl load ~/Library/LaunchAgents/com.digibyte.daemon.plist

# Check status
launchctl list | grep digibyte
```

---

### Step 7: Wallet File Permissions

Your oracle wallet file contains the private key that signs price bundles. Protect it.

**Linux:**

```bash
# Restrict wallet file to owner only
chmod 600 /home/dgboracle/.digibyte/wallets/oracle/wallet.dat

# Restrict the wallets directory
chmod 700 /home/dgboracle/.digibyte/wallets/

# Verify
ls -la /home/dgboracle/.digibyte/wallets/oracle/wallet.dat
# Should show: -rw------- 1 dgboracle dgboracle
```

**Windows:**

1. Navigate to `C:\Users\dgboracle\AppData\Roaming\DigiByte\wallets\oracle\`
2. Right-click `wallet.dat` → **Properties → Security**
3. Click **Advanced → Disable inheritance** → **"Convert inherited permissions"**
4. Remove all entries except `dgboracle` (Full Control) and `SYSTEM` (Full Control)
5. Click Apply

Or via PowerShell (run as Administrator):

```powershell
$path = "C:\Users\dgboracle\AppData\Roaming\DigiByte\wallets\oracle\wallet.dat"
$acl = Get-Acl $path
$acl.SetAccessRuleProtection($true, $false)  # Disable inheritance

# Remove all existing rules
$acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) }

# Add dgboracle full control
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule("dgboracle", "FullControl", "Allow")
$acl.AddAccessRule($rule)

# Add SYSTEM full control (required for services)
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM", "FullControl", "Allow")
$acl.AddAccessRule($rule)

Set-Acl $path $acl
```

**macOS:**

```bash
chmod 600 ~/Library/Application\ Support/DigiByte/wallets/oracle/wallet.dat
chmod 700 ~/Library/Application\ Support/DigiByte/wallets/
```

> **Backup reminder:** Wallet file permissions don't help if someone steals your backup. Keep your wallet backup on an encrypted USB drive in a safe place. I keep mine on an encrypted Kingston USB with the passphrase stored separately.

---

## Tier 1 Summary — What You Should Have Now

After completing Tier 1:

- [ ] Dedicated `dgboracle` user account (not root/admin)
- [ ] Host firewall enabled — only P2P port allowed inbound
- [ ] Port forwarding on router — ONLY the P2P port, nothing else
- [ ] Static local IP on the oracle machine
- [ ] NTP time sync verified and running
- [ ] Automatic OS security updates enabled
- [ ] digibyted auto-starts on boot and restarts on crash
- [ ] Wallet file permissions locked down

**This is a meaningful improvement over an unhardened setup.** You've eliminated the most common attack vectors (exposed RDP, open firewall, missing updates) and ensured your oracle recovers from power outages.

---

## Tier 2 — Recommended Hardening

> 📊 **[View Tier 2 Network Diagram](https://htmlpreview.github.io/?https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/network-tier2-recommended.html)** — same network, now hardened

These steps add meaningful additional protection. They take more time but significantly improve your security posture.

---

### Step 8: Consider Enabling SSH (Yes, Even at Home)

If you're currently accessing your oracle machine via xRDP or by walking up to it, consider enabling SSH with key-only authentication instead. Here's why:

**xRDP / RDP drawbacks:**
- GUI is heavy — wastes resources on a headless oracle node
- xRDP has had security vulnerabilities
- If you ever need to manage your node remotely (away from home), you'll want SSH
- RDP is a common attack target if it's ever accidentally exposed

**SSH advantages:**
- Lightweight — no GUI overhead
- Key-only auth is extremely secure (no password to brute force)
- Works over VPN from anywhere (see Tier 3)
- Standard for server management — most guides assume SSH

**If you enable SSH, lock it down:**

This only applies to **Linux** and **macOS**. Windows users can install OpenSSH Server (see below) or continue with RDP.

**Linux:**

```bash
# Install SSH server if not present
sudo apt install openssh-server -y

# Edit SSH config
sudo nano /etc/ssh/sshd_config
```

Critical settings to change:

```
Port 5520                           # Move off default port 22
PermitRootLogin no                  # Never allow root SSH
PubkeyAuthentication yes            # Allow key auth
PasswordAuthentication no           # Disable password auth (key-only)
KbdInteractiveAuthentication no     # Disable keyboard-interactive
MaxAuthTries 3                      # Lock out after 3 failures
LoginGraceTime 30                   # 30 seconds to authenticate
X11Forwarding no                    # No GUI forwarding needed
AllowUsers dgboracle                # Only allow the oracle user
ClientAliveInterval 300             # 5-minute keepalive
ClientAliveCountMax 2               # Drop after 2 missed keepalives
```

```bash
# Restart SSH
sudo systemctl restart ssh
# On Ubuntu 26.04, you may need:
sudo systemctl restart ssh.socket

# Add SSH port to UFW (local network only)
sudo ufw allow from 192.168.0.0/16 to any port 5520 comment "SSH local only"
```

> **Do NOT port-forward SSH through your router** unless you're using a VPN (Tier 3). The UFW rule above limits SSH to your local network only.

Generate an SSH key pair on your laptop/desktop (the machine you'll SSH *from*):

```bash
# On your laptop (Linux/macOS)
ssh-keygen -t ed25519 -C "oracle-access"
# On Windows, use PuTTYgen or:
ssh-keygen -t ed25519 -C "oracle-access"

# Copy the public key to your oracle machine
ssh-copy-id -p 5520 dgboracle@192.168.1.100
```

Test the connection before disabling password auth — if you lock yourself out, you'll need physical access to fix it.

**Windows (OpenSSH Server):**

```powershell
# Install OpenSSH Server (run as Administrator)
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# Start and enable
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
```

SSH config on Windows is at `C:\ProgramData\ssh\sshd_config`. Same settings apply — change port, disable password auth after setting up key auth.

**macOS:**

SSH (Remote Login) is built in but disabled by default:

1. Open **System Settings → General → Sharing**
2. Toggle **Remote Login** to **On**
3. Restrict to specific users (your `dgboracle` account)

SSH config is at `/etc/ssh/sshd_config`. Same settings apply.

---

### Step 9: Fail2Ban (Linux Only)

If you enabled SSH (Step 8), install Fail2Ban to block brute force attempts. If you're not running SSH, you can skip this step — there's nothing for Fail2Ban to protect.

> **Answering Aussie Epic's question:** "Does Fail2Ban need configuring differently as SSH is not being used? Or, because the Home Lab server does not use SSH and can only be accessed locally via RDP, does this negate an attack occurring as SSH is not running on the machine?"
>
> **If SSH is not running, you don't need Fail2Ban for SSH.** No SSH service = nothing listening on port 22 (or 5520) = nothing to brute force. Your xRDP is local-only (not port-forwarded), so it's not reachable from the internet either. In that scenario, Fail2Ban adds nothing.
>
> **If you enable SSH (Step 8), install Fail2Ban.** Even if SSH is only on your local network, Fail2Ban is cheap insurance.

```bash
sudo apt install fail2ban -y

# Create local config
sudo nano /etc/fail2ban/jail.local
```

```ini
[sshd]
enabled = true
port = 5520
maxretry = 3
findtime = 600
bantime = 86400
backend = systemd
```

```bash
sudo systemctl enable fail2ban
sudo systemctl restart fail2ban

# Verify
sudo fail2ban-client status sshd
```

> **`backend = systemd`** works on Ubuntu 22.04, 24.04, and 26.04. Don't use `logpath = /var/log/auth.log` — it breaks on newer Ubuntu versions that use the journal instead of log files.

---

### Step 10: Kernel Hardening (Linux Only)

These sysctl settings reduce your kernel's attack surface. They're identical to what I run on my VPS oracle.

```bash
sudo nano /etc/sysctl.d/99-oracle-hardening.conf
```

```ini
# Don't send ICMP redirects (we're not a router)
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Disable magic SysRq key (prevents console-level exploits)
kernel.sysrq = 0

# Disable core dumps for setuid programs
fs.suid_dumpable = 0
```

```bash
# Apply immediately
sudo sysctl -p /etc/sysctl.d/99-oracle-hardening.conf
```

Also harden shared memory:

```bash
# Add to /etc/fstab
echo "tmpfs /dev/shm tmpfs defaults,noexec,nosuid,nodev 0 0" | sudo tee -a /etc/fstab

# Remount
sudo mount -o remount /dev/shm

# Verify
mount | grep shm
# Should show: noexec,nosuid,nodev
```

> **Windows and macOS users:** These are Linux kernel-specific hardening steps. Windows and macOS have their own kernel protections enabled by default (DEP, ASLR, SIP on macOS). No equivalent manual steps needed.

---

### Step 11: Disable Apport (Ubuntu Only)

Ubuntu's crash reporter (`apport`) overrides the `suid_dumpable` setting on boot, re-enabling core dumps for setuid programs. Disable it:

```bash
sudo nano /etc/default/apport
```

Change `enabled=1` to `enabled=0`, then:

```bash
sudo systemctl stop apport.service
sudo systemctl disable apport.service
```

---

### Step 12: Router Hardening

Your consumer router is the perimeter between your oracle and the internet. Every router manufacturer has a different interface, so I can't give exact commands — but here are the principles that apply to all of them.

**Log into your router** (usually `192.168.0.1` or `192.168.1.1` in your browser) and check these settings:

**Change the admin password.** If your router's admin panel is still using the default password (admin/admin, admin/password, etc.), change it now. This is the single most important router hardening step.

**Update the firmware.** Router manufacturers patch security vulnerabilities in firmware updates. Check your router manufacturer's website for the latest firmware. Most modern routers have an "auto-update" option — enable it if available.

**Disable UPnP (Universal Plug and Play) — if you can.** UPnP allows devices on your network to automatically open ports on your router without your permission. This is a security risk — malware on any device in your network could use UPnP to punch a hole in your firewall and phone home. You've manually set up port forwarding for DigiByte (Step 3), so your oracle doesn't need UPnP.

However — if you run other services that depend on UPnP (like Flux nodes, gaming consoles, or smart home hubs), disabling UPnP breaks them. Check your router's UPnP client list to see what's using it before you flip the switch. On my TP-Link router, this is under NAT Forwarding → UPnP — it shows every device and port that UPnP has opened. I found a stale entry from an unknown device while writing this guide — that's exactly the kind of thing UPnP lets happen silently.

If you need UPnP for other services but want to protect your oracle, the real answer is VLAN isolation (Tier 3). Put your oracle on a separate VLAN where UPnP is disabled, and keep UPnP enabled only on the VLAN where Flux or other UPnP-dependent services live.

**Disable WPS (Wi-Fi Protected Setup).** The push-button and PIN methods in WPS have known vulnerabilities that allow attackers to brute force your WiFi password. Disable it.

**Disable remote management.** Some routers allow admin access from the internet (WAN side). This should be OFF. You only need to manage your router from inside your home network.

**Use WPA3 or WPA2-AES for WiFi.** If your oracle is on WiFi (not recommended for reliability — use Ethernet), make sure your WiFi encryption is WPA3 or at minimum WPA2-AES (never WEP or WPA-TKIP). Use a strong, unique WiFi password.

> **ISP-provided modem/routers** (the combo device your ISP gives you) often have limited configuration options. If yours doesn't let you disable UPnP or update firmware, consider putting it in bridge mode and using your own router behind it — you'll have full control over the security settings.

---

### Step 13: UPS + Graceful Shutdown

A UPS (Uninterruptible Power Supply) keeps your oracle running during short power outages and gives your machine time to shut down cleanly during long ones. An unclean shutdown can corrupt your DigiByte blockchain database, requiring a time-consuming reindex.

**What you need:** A UPS with a USB data cable that connects to your oracle machine. The USB cable lets your machine detect when it's running on battery and trigger a graceful shutdown before the battery runs out.

**Linux (NUT — Network UPS Tools):**

```bash
sudo apt install nut -y

# Configure NUT
sudo nano /etc/nut/ups.conf
```

Add your UPS (adjust driver for your model — check [NUT compatibility list](https://networkupstools.org/stable-hcl.html)):

```ini
[myups]
    driver = usbhid-ups
    port = auto
    desc = "Oracle UPS"
```

```bash
# Set NUT mode
sudo nano /etc/nut/nut.conf
# Set: MODE=standalone

# Configure monitoring
sudo nano /etc/nut/upsmon.conf
# Add: MONITOR myups@localhost 1 admin password master
# Set: SHUTDOWNCMD "/sbin/shutdown -h now"

# Start NUT
sudo systemctl enable nut-server nut-monitor
sudo systemctl start nut-server nut-monitor

# Verify UPS is detected
upsc myups
```

**Alternative (apcupsd):** If you have an APC-brand UPS, `apcupsd` is simpler:

```bash
sudo apt install apcupsd -y
# Edit /etc/apcupsd/apcupsd.conf — most defaults work for USB
# Set UPSTYPE usb and DEVICE (leave blank for auto-detect)
sudo systemctl enable apcupsd
sudo systemctl start apcupsd
apcaccess  # Check UPS status
```

**Windows:**

Windows handles UPS natively via USB:

1. Connect UPS USB cable to your machine
2. Open **Control Panel → Power Options**
3. Your UPS should appear as a battery
4. Click **"Change plan settings" → "Change advanced power settings"**
5. Under **Battery → Critical battery action**, set to **Shut down** (not hibernate)
6. Under **Battery → Critical battery level**, set to **10%** (gives time for clean shutdown)

**macOS:**

macOS handles UPS natively via USB:

1. Connect UPS USB cable
2. Open **System Settings → Battery** (or Energy Saver on older macOS)
3. Your UPS should appear
4. Under **UPS** tab, check **"Shut down the computer after using UPS battery for X minutes"**
5. Set a conservative time (e.g., 5 minutes)

---

## Tier 2 Summary — What You Should Have Now

After completing Tier 2 (in addition to Tier 1):

- [ ] SSH enabled with key-only auth (recommended over xRDP)
- [ ] Fail2Ban protecting SSH (if SSH is enabled)
- [ ] Kernel hardening applied (Linux)
- [ ] Shared memory hardened (Linux)
- [ ] Apport disabled (Ubuntu)
- [ ] Router admin password changed from default
- [ ] Router firmware updated
- [ ] UPnP disabled on router (or isolated via VLAN if other services need it)
- [ ] WPS disabled on router
- [ ] Remote management disabled on router
- [ ] UPS connected with graceful shutdown configured

---

## Tier 3 — Advanced Hardening

> 📊 **[View Tier 3 Network Diagram](https://htmlpreview.github.io/?https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/network-tier3-advanced.html)** — full VLAN isolation with WireGuard VPN

These steps are for operators who want to go further. They require more networking knowledge but provide significant additional protection.

> **Note:** Most of this section is based on my own home network setup — VLANs, WireGuard VPN, managed switches, segmented mining and node infrastructure. I've been running this layout for years and it's battle-tested. If your router supports these features, this is how I'd set it up.

---

### Step 14: VLAN Isolation

If your router supports VLANs (most prosumer routers like Ubiquiti, Mikrotik, or pfSense do), put your oracle machine on its own VLAN. This isolates it from every other device on your network — your IoT devices, phones, smart TVs, and laptops can't reach your oracle at all.

I run a VLAN-segmented home network for my mining and node infrastructure. The oracle sits on its own VLAN with no cross-VLAN access allowed. If my kid's tablet gets compromised, it can't reach my oracle.

**The concept:**
- VLAN 1 (default): Your normal devices (phones, laptops, etc.)
- VLAN 10 (example): Oracle and mining infrastructure only
- Firewall rules between VLANs: block VLAN 1 → VLAN 10 entirely, allow VLAN 10 → internet for P2P + price feeds

This requires a managed switch and a router that supports VLAN tagging. Configuration is highly device-specific — search for your router model + "VLAN setup guide."

> **ISP modem/routers don't support VLANs.** You'll need your own router (pfSense, OPNsense, Ubiquiti EdgeRouter, Mikrotik, etc.) behind the ISP modem in bridge mode.

---

### Step 15: DDNS for a Stable Hostname (Optional — Nice to Have)

> **Do you actually need this?** Probably not for oracle operation. The official oracle endpoint hostnames (`oracleN.digidollar.org`) are hardcoded into the binary via DD-FINAL-029 in chainparams. Jared controls the `digidollar.org` DNS and sets the A records that map each hostname to each operator's IP. Your oracle's discoverability is handled through that — not through your own DDNS.
>
> DDNS is only useful if you want a personal hostname for `addnode` sharing with other community members, monitoring dashboards, or personal convenience. It's a nice-to-have, not a requirement for oracle operation.

Your ISP gives you a dynamic IP that changes periodically. A Dynamic DNS (DDNS) service gives you a stable hostname (like `myoracle.ddns.net`) that automatically updates to point to your current IP.

**If you still want DDNS, here are free providers:**
- [No-IP](https://www.noip.com/) (free tier requires confirmation every 30 days)
- [DuckDNS](https://www.duckdns.org/) (free, simple, no confirmation)
- [Dynu](https://www.dynu.com/) (free tier available)

**Setup (DuckDNS example — Linux):**

1. Create an account at duckdns.org
2. Create a subdomain (e.g., `myoracle.duckdns.org`)
3. Install the update script:

```bash
mkdir -p ~/duckdns
nano ~/duckdns/duck.sh
```

```bash
#!/bin/bash
echo url="https://www.duckdns.org/update?domains=myoracle&token=YOUR-TOKEN-HERE&ip=" | curl -k -o ~/duckdns/duck.log -K -
```

```bash
chmod +x ~/duckdns/duck.sh

# Add to cron (update every 5 minutes)
(crontab -l 2>/dev/null; echo "*/5 * * * * ~/duckdns/duck.sh >/dev/null 2>&1") | crontab -
```

**Windows:** Most DDNS providers offer a Windows update client. No-IP and DuckDNS both have lightweight Windows apps that run in the system tray.

**macOS:** DuckDNS update works the same as Linux (via cron or launchd). No-IP also has a macOS client.

**Many routers** have built-in DDNS support (check under "Dynamic DNS" or "DDNS" in your router settings). If your router supports it, use the router's DDNS client — it updates even if your oracle machine is offline.

---

### Step 16: WireGuard VPN for Remote Access

If you need to manage your oracle when you're away from home, use a VPN instead of exposing SSH or RDP to the internet.

WireGuard is the modern choice — fast, simple, secure. You install WireGuard on your oracle machine (or your router, if it supports it), create a config, and connect from your laptop/phone when needed.

**Why WireGuard over exposing SSH:**
- WireGuard uses UDP with a cryptographic handshake — if you don't have the right key, the server doesn't even respond (stealth)
- One port to forward (UDP), and it's invisible to port scanners without the key
- Once connected, you have full local network access as if you were at home

Full WireGuard setup is beyond the scope of this guide, but the DigitalOcean tutorial is excellent: search for "DigitalOcean WireGuard Ubuntu" for a step-by-step.

I run WireGuard on my home network through my TP-Link BE9700 Pro router — WireGuard is built into the router firmware, which is one of the reasons I chose it. No need to run a separate WireGuard server on a machine. I use it to remotely access my miners, node GUIs, and management interfaces when I'm away from home. It's the only port I forward besides P2P — one UDP port, and if you don't have the key, the server doesn't even acknowledge your existence.

> **Tip:** If you're shopping for a router, look for one with built-in WireGuard or VPN server support. TP-Link, ASUS, and Mikrotik all offer models with native WireGuard. It's much simpler than running WireGuard on a separate machine.

**Key points for oracle operators:**
- Forward one UDP port (e.g., 51820) through your router for WireGuard
- Once connected via VPN, SSH/RDP to your oracle using its local IP (192.168.x.x)
- This is the safest way to access your oracle remotely

---

### Step 17: Adapt oracle-monitor.sh for Home

My [oracle-monitor.sh](https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/oracle-monitor.sh) was built for Linux VPS, but most of it works on a home Linux machine with one change:

```bash
# If running on mainnet (no -testnet flag needed):
CLI="digibyte-cli"

# If running on testnet:
CLI="digibyte-cli -testnet"
```

The health checks (oracle status, chain sync, consensus price, disk space, memory) all work the same. The Discord webhook alerts work from home as long as you have internet access.

**What changes for home:**
- The `ss -tlnp | grep 12024` port check works the same (use `grep 12033` for testnet)
- Systemd service checks work the same
- Disk and memory checks work the same
- You may want to add a check for your UPS battery level (if using NUT: `upsc myups battery.charge`)

> **Windows and macOS operators:** oracle-monitor.sh is Bash/Linux only. A cross-platform Python version is on my roadmap (Issue #11 on my GitHub). For now, Windows operators can use the DigiByte-Qt wallet GUI to visually check oracle status, or manually run `digibyte-cli listoracle` and `digibyte-cli getoracleprice` in a command prompt.

---

## What This Guide Can't Fix

I want to be honest about the limitations of home oracle operation:

**ISP outages.** When your ISP goes down, your oracle goes dark. No amount of hardening fixes this. If your ISP is unreliable (frequent outages, maintenance windows during peak hours), consider a VPS for your oracle.

**Dynamic IP + frozen roster.** Your official oracle endpoint (`oracleN.digidollar.org`) points to your IP via DNS that Jared controls. If your IP changes, you need to contact Jared to update the A record. This is manual and slow. Until Stage 2 ships, there's no automated solution. DDNS helps for `addnode` but doesn't solve the oracle endpoint problem.

**CGNAT (Carrier-Grade NAT).** Some ISPs (especially mobile/4G/5G providers and some fiber providers) use CGNAT, which means you're behind TWO layers of NAT — your router AND the ISP's. Port forwarding doesn't work with CGNAT because you don't have a real public IP. If `traceroute` to an external IP shows a hop through a `100.64.x.x` address, you're behind CGNAT. Contact your ISP to request a public IP, or use a VPS.

**Router as single point of failure.** Your consumer router is running embedded firmware that may have unpatched vulnerabilities. If it's compromised, your port forwarding rules can be modified, traffic can be intercepted, and your oracle's P2P connections can be MitM'd. Router firmware updates help but can't eliminate this risk entirely.

**Power outages longer than your UPS.** A UPS gives you minutes, not hours. If power is out for an extended period, your oracle goes offline after the UPS battery is drained. A generator helps but adds cost and complexity.

**No DDoS protection.** VPS providers typically include basic DDoS mitigation. Your home ISP provides none. A sustained DDoS against your public IP will take your oracle offline and potentially disrupt your entire home internet. The only mitigation is obscurity (don't publicly share your home IP) and hoping you're not targeted.

---

## Maintenance Checklist

**Weekly:**
- Check that digibyted is running and oracle is active (`digibyte-cli listoracle`)
- Verify time sync is active (Linux: `timedatectl status`, Windows: `w32tm /query /status`)
- Glance at disk space (`df -h` on Linux, check via File Explorer on Windows)

**Monthly:**
- Check for and install OS updates that weren't auto-applied
- Check router firmware for updates
- Review port forwarding rules — make sure nothing new was added (malware or UPnP)
- Test that your oracle is reachable from outside (use a port checker site)
- Verify UPS battery health (Linux NUT: `upsc myups battery.charge`, Windows: check battery icon)

**After any power outage or reboot:**
- Verify digibyted started and is syncing
- Verify oracle is running (`digibyte-cli listoracle` → `"running": true`)
- Check the oracle dashboard at https://digibyte.io/testnet/oracles (testnet) or equivalent (mainnet)

**After ISP outage or IP change:**
- Check if your public IP changed (search "what is my IP" in your browser)
- If it changed: update DDNS (should be automatic if configured), and contact Jared to update the oracle endpoint A record
- Test port forwarding is still working (port checker site)

---

## Quick Reference — Platform Commands

| Task | Linux (Ubuntu) | Windows | macOS |
|------|---------------|---------|-------|
| Check oracle status | `digibyte-cli listoracle` | `digibyte-cli.exe listoracle` | `digibyte-cli listoracle` |
| Check consensus price | `digibyte-cli getoracleprice` | `digibyte-cli.exe getoracleprice` | `digibyte-cli getoracleprice` |
| Check firewall | `sudo ufw status` | `Get-NetFirewallRule` (PS) | `sudo pfctl -sr` |
| Check NTP sync | `timedatectl status` | `w32tm /query /status` | `sudo systemsetup -getusingnetworktime` |
| Check disk space | `df -h` | `Get-PSDrive C` (PS) | `df -h` |
| Restart digibyted | `sudo systemctl restart digibyted` | `Restart-Service DigiByteDaemon` (PS) | `launchctl kickstart com.digibyte.daemon` |
| View logs | `journalctl -u digibyted -f` | Check `debug.log` in data dir | Check `debug.log` in data dir |
| Check UPS | `upsc myups` (NUT) | Check battery icon in taskbar | Check battery in System Settings |

---

## Additional Resources

- **VPS Hardening Guide** (for VPS operators): https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/ORACLE_HARDENING_GUIDE.md
- **Oracle Setup Tutorial** (all platforms): https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/ORACLE_SETUP_TUTORIAL.md
- **Oracle Monitor Script** (Linux): https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/oracle-monitor.sh
- **DigiDollar Oracle Setup** (official): https://github.com/DigiByte-Core/digibyte/blob/feature/digidollar-v1/DIGIDOLLAR_ORACLE_SETUP.md
- **Oracle Dashboard** (testnet): https://digibyte.io/testnet/oracles
- **NUT UPS Compatibility List**: https://networkupstools.org/stable-hcl.html

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-06-03 | Initial release — Linux, Windows, macOS. Three tiers. |

---

*Built from years of hardening VPS and home lab infrastructure across blockchain projects — Bitcoin, TOR, DigiByte, PIVX, Session, Helium MCC governance, solo mining and much more.....   Community-requested by Aussie Epic. If something's wrong, open an issue or find me on Gitter (digibyte-maxi in #digidollar:gitter.im).*
