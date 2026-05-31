# DigiDollar Oracle Setup — Quick Start

> Originally posted by **DigiSwarm** in the DigiDollar Gitter community.  
> Reproduced here for reference. All credit to the original author.  
> Gitter: https://app.gitter.im/#/room/#digidollar:gitter.im

---

## Requirements

- DigiByte Core v9.26.0-rc43 or later
- A VPS or machine you can keep online reliably for 1–2 years
- An assigned oracle ID (request one in the Gitter dev chat — do not guess)

---

## Download

**DigiByte Core v9.26.0-rc43:**  
https://github.com/DigiByte-Core/digibyte/releases/tag/v9.26.0-rc43

| Platform | File |
|----------|------|
| Windows | `digibyte-9.26.0-rc43-win64-setup-unsigned.exe` |
| macOS | `digibyte-9.26.0-rc43-x86_64-apple-darwin-unsigned.zip` |
| Linux x86_64 | `digibyte-9.26.0-rc43-x86_64-linux-gnu.tar.gz` |
| Linux ARM64 | `digibyte-9.26.0-rc43-aarch64-linux-gnu.tar.gz` |

---

## Steps

1. **Download and install** DigiByte Core RC43 for your platform.

2. **Request an oracle ID** in the Gitter dev chat:  
   https://app.gitter.im/#/room/#digidollar:gitter.im  
   Do not pick your own ID — ask the team.

3. **Create or open a wallet named `oracle`.**

   Qt wallet (Windows/macOS): File → Create Wallet → name it `oracle`

   CLI:
   ```bash
   digibyte-cli -testnet createwallet "oracle"
   ```

4. **Generate your oracle key** using your assigned ID:

   Qt wallet: Help → Debug Window → Console, then run:
   ```
   createoraclekey <your_oracle_id>
   ```

   CLI:
   ```bash
   digibyte-cli -testnet -rpcwallet=oracle createoraclekey <your_oracle_id>
   ```

5. **Post your details in Gitter** with:
   - Requested ID
   - Oracle name
   - Public key (the output from step 4)
   - Platform / VPS basics
   - Confirmation you can run it reliably for 1–2 years

6. **Back up your wallet.** The oracle key is stored there — if you lose it, you lose your slot.

7. **Wait for the next RC** that includes your public key before running `startoracle`.

---

## Security

- **Never share your private key.**
- Share only the public key returned by `createoraclekey`.
- Keep your wallet backup in a safe location.

---

## Full Tutorial

For a detailed walkthrough covering Linux, Windows, and macOS:  
→ [ORACLE_SETUP_TUTORIAL.md](./ORACLE_SETUP_TUTORIAL.md)

Official DigiByte setup guide:  
→ https://github.com/DigiByte-Core/digibyte/blob/feature/digidollar-v1/DIGIDOLLAR_ORACLE_SETUP.md
