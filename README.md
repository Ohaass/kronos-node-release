# KRONOS Protocol — Node Release Distribution

[![Mainnet](https://img.shields.io/badge/Mainnet-v0.2.1-2E86AB?style=for-the-badge)](https://www.kroscripto.com)
[![Post-Quantum](https://img.shields.io/badge/Dilithium3-FIPS%20204-00A550?style=for-the-badge)](https://csrc.nist.gov/projects/post-quantum-cryptography)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue?style=for-the-badge)](LICENSE)

This repository distributes **signed, verifiable binaries** of the KRONOS Protocol node — the first production Layer 1 blockchain network built on post-quantum cryptography.

> **KRONOS** is a permissioned post-quantum L1 with a **DAG-based consensus** (PDV — Proof of Deterministic Validation), **State Reconstruction Protocol** (SRP) for archival nodes, and **CRYSTALS-Dilithium3** (FIPS 204) signatures throughout the entire stack — including the binaries you download here.

- **Live network**: https://www.kroscripto.com
- **Block explorer**: https://www.kroscripto.com/explorer
- **Whitepaper**: https://www.kroscripto.com/whitepaper
- **Contact**: info@kroscripto.com

---

## Why this repository exists

The KRONOS Protocol source code is currently private during the OEPM utility model (`U202630818`) priority window. To allow third-party node operators to participate in the network, this repository publishes:

- **Pre-compiled, signed binaries** of `kronos-node`, `kros-ca`, and `kros-wallet`
- The network **trust bundle** (root + intermediate CA public keys)
- A turnkey **`install.sh`** for Ubuntu 22.04 / 24.04 LTS
- This **operator handbook**

Every binary in `releases/v0.2.1/` is signed with **Dilithium3 + SHA3-256** by the KRONOS Intermediate Certificate Authority. You can verify them with the `kros-ca` tool included in the same release — a self-consistent, post-quantum verifiable distribution chain.

---

## Quick start

### Requirements

| Component | Minimum |
|-----------|---------|
| OS | Ubuntu 22.04 LTS or 24.04 LTS (x86_64) |
| CPU | 2 cores |
| RAM | 4 GB |
| Disk | 40 GB SSD |
| Network | Static public IPv4, port 9000 reachable |
| Other | `root` access, outbound HTTPS |

### Install in two phases

```bash
# Phase 1 — bootstrap (generates keypair + cert-request)
curl -sSL https://raw.githubusercontent.com/Ohaass/kronos-node-release/main/install.sh -o install.sh
sudo bash install.sh
```

This will:

1. Download and verify the `kronos-node`, `kros-ca`, and `kros-wallet` binaries with Dilithium3.
2. Generate a fresh Dilithium3 keypair on your machine. Your private key never leaves your server.
3. Produce a `cert-request.json` ready to email.
4. Configure UFW (firewall) for SSH + port 9000 between KRONOS peers.

You will then receive instructions to **email `cert-request.json` to `info@kroscripto.com`**.

We will verify your identity, sign your `NodeCert` with the intermediate CA, and reply with the `.cert` file (typically within 24–48 hours).

```bash
# Phase 2 — finalize (after receiving the signed .cert by email)
sudo bash install.sh --finalize /path/to/your.cert
```

This will:

1. Verify the received `NodeCert` against the trust bundle.
2. Generate `node.toml` with the bootstrap peers.
3. Install a `systemd` service and start `kronos-node`.
4. Confirm the service is up and registering with the network.

Your node will appear on the public dashboard within ~1 minute: https://www.kroscripto.com/network

---

## Manual verification (optional)

If you prefer to verify the binaries before running `install.sh`, do it manually:

```bash
# Download
curl -fsSL https://github.com/Ohaass/kronos-node-release/releases/download/v0.2.1/kronos-node-linux-x86_64       -o kronos-node
curl -fsSL https://github.com/Ohaass/kronos-node-release/releases/download/v0.2.1/kronos-node-linux-x86_64.sig   -o kronos-node.sig
curl -fsSL https://github.com/Ohaass/kronos-node-release/releases/download/v0.2.1/kros-ca-linux-x86_64           -o kros-ca
curl -fsSL https://github.com/Ohaass/kronos-node-release/releases/download/v0.2.1/kros-ca-linux-x86_64.sig       -o kros-ca.sig
curl -fsSL https://github.com/Ohaass/kronos-node-release/releases/download/v0.2.1/kros-wallet-linux-x86_64       -o kros-wallet
curl -fsSL https://github.com/Ohaass/kronos-node-release/releases/download/v0.2.1/kros-wallet-linux-x86_64.sig   -o kros-wallet.sig
curl -fsSL https://raw.githubusercontent.com/Ohaass/kronos-node-release/main/trust-bundle.bin                    -o trust-bundle.bin

# Verify trust bundle SHA256 (the only "trust on first download" step)
echo "ef6a28a3fff77229839150ebbd968446e91777c9ba70b72b0e2cb991f19ef893  trust-bundle.bin" | sha256sum --check

# Make kros-ca executable, then use it to verify both binaries with Dilithium3
chmod +x kros-ca kronos-node kros-wallet
./kros-ca verify-file --in-file kros-ca      --sig kros-ca.sig      --bundle trust-bundle.bin
./kros-ca verify-file --in-file kronos-node  --sig kronos-node.sig  --bundle trust-bundle.bin
./kros-ca verify-file --in-file kros-wallet  --sig kros-wallet.sig  --bundle trust-bundle.bin
```

Expected output for each `verify-file`:

```
✓ VALID — signature verified
  File:        ...
  Hash:        ... (SHA3-256)
  Algo:        sha3-256 + Dilithium3
  Signed at:   2026-05-25T...
  Signer:      kros1a42048b08d6e200b7c448cfc58ea63ac43a8d9fbdd
  Trust:       issuer is intermediate of the bundle
```

If the signature is invalid, **do not run the binary**. Open an issue or email `info@kroscripto.com`.

---

## Permissioned onboarding

KRONOS uses a closed-CA model. Each node holds a `NodeCert` signed by the Intermediate CA. The Intermediate is in turn signed by the offline Root CA. New nodes are not trusted by the network until their `NodeCert` is issued.

The full process:

1. You run `install.sh` → it generates a Dilithium3 keypair **on your server**.
2. Your **private key never leaves the server** (stored at `/etc/kronos/v0.2.1/node.key`, chmod 600).
3. Only the **public key + node metadata** is included in `cert-request.json`.
4. You email the JSON to `info@kroscripto.com`.
5. The KRONOS operator verifies the request and signs your `NodeCert` with `kros-ca sign-cert`.
6. The operator emails you the signed `.cert` file.
7. You run `install.sh --finalize` to install the cert and start the service.
8. The TLS handshake between your node and existing peers presents the cert; peers verify the chain against their embedded trust bundle and accept your connection.

All signing operations are recorded in the CA `audit.log`.

---

## What's inside this repo

```
.
├── README.md                  This file
├── LICENSE                    Apache License 2.0
├── NOTICE                     Required Apache 2.0 attribution
├── install.sh                 Turnkey installer
├── trust-bundle.bin           Network trust bundle (root + intermediate pubkeys)
├── trust-bundle.bin.sha256    SHA256 of trust bundle
└── releases/
    └── v0.2.1/
        ├── kronos-node-linux-x86_64        Node binary (8.4 MB)
        ├── kronos-node-linux-x86_64.sha256
        ├── kronos-node-linux-x86_64.sig    Dilithium3 signature
        ├── kros-ca-linux-x86_64            CA tool / verifier (1.3 MB)
        ├── kros-ca-linux-x86_64.sha256
        ├── kros-ca-linux-x86_64.sig        Dilithium3 signature
        ├── kros-wallet-linux-x86_64        CLI wallet (4.6 MB)
        ├── kros-wallet-linux-x86_64.sha256
        └── kros-wallet-linux-x86_64.sig    Dilithium3 signature
```

Binaries are also published as GitHub Releases: https://github.com/Ohaass/kronos-node-release/releases

---

## Frequently asked questions

**Is the source code open?**

The KRONOS Protocol main repository is currently private during the OEPM utility model priority window. The **binaries and verification chain in this repo are open**, allowing third parties to run nodes and audit signatures cryptographically. The source may open in a future release.

**What does PDV (Proof of Deterministic Validation) mean?**

PDV is a consensus mechanism where validators for each transaction are selected deterministically using a cryptographic hash of the transaction itself. There is no fixed validator set, no mining, and no staking required for the protocol to make progress.

**What is SRP (State Reconstruction Protocol)?**

SRP allows archival nodes to reconstruct historical state from checkpoints and a partial DAG, providing efficient sync for late-joining nodes without requiring full history transfer.

**Can I run a node behind a NAT?**

Not currently. The P2P protocol requires inbound TCP on port 9000 from the other KRONOS peers. We recommend a VPS with a static public IPv4 (Hetzner, OVH, Vultr, etc.).

**What if my server gets compromised?**

Email `info@kroscripto.com` immediately. The operator can publish a revocation list (serial number incremented) that invalidates your `NodeCert`. All peers will refuse to authenticate it within one revocation refresh cycle (≤1 hour).

**Can I run an archival node (full history)?**

Yes — request `"capabilities": ["archive"]` in your `cert-request.json` (the default in `install.sh` is `"validator"`). Archive nodes serve SRP queries to other peers and require more disk over time.

**What's the roadmap?**

See the whitepaper at https://www.kroscripto.com/whitepaper. Phase 5 (KROS rewards for validators) is the next major milestone after the v0.2.x stabilization phase.

**Where can I get help?**

- **Email**: info@kroscripto.com
- **GitHub Issues**: https://github.com/Ohaass/kronos-node-release/issues
- **Dashboard**: https://www.kroscripto.com/network

---

## License

Apache License 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).

The KRONOS Protocol architecture (DAG + PDV + SRP) is covered by Spanish utility model **OEPM U202630818** (filed April 2026). International patent protection is being secured within the 1-year priority window.

The Apache License grants you the right to run, distribute, and modify the **binaries and scripts in this repository**, but does not grant any rights over the KRONOS Protocol's patented architecture beyond what is required to use the published artifacts.

---

*Built by Oscar Haass ([@Ohaass](https://github.com/Ohaass)). Powered by post-quantum cryptography.*
