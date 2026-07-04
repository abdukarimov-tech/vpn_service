# Encryption Self-Classification Report — Barys VPN

**Submitted under:** U.S. Export Administration Regulations (EAR),
15 CFR §740.17(b)(1) — Encryption commodities, software and components
(mass market), self-classification.

**Report type:** Annual self-classification report (Supplement No. 8 to Part 742).

---

## 1. Point of Contact

| Field | Value |
|-------|-------|
| Company / Developer | Murat Abdukarimov |
| Contact name | Murat Abdukarimov |
| Email | support@rudnowski.dev |
| Country | Kazakhstan |

## 2. Product Information

| Field | Value |
|-------|-------|
| Product name | Barys VPN |
| Model / Version | 1.0 |
| Manufacturer | Murat Abdukarimov |
| ECCN | 5D992.c |
| Authorization type | MMKT (Mass Market, self-classified) |
| Item type | Network infrastructure — VPN client software (mobile application) |
| Non-U.S. manufacturing location | N/A (software, distributed via Apple App Store / Google Play) |

## 3. Product Description

Barys VPN is a free consumer mobile VPN (virtual private network) client
for iOS and Android. It establishes an encrypted tunnel between the user's
device and a remote proxy server to protect the confidentiality of the
user's internet traffic. The application is a mass-market product
distributed to the general public through the Apple App Store and Google
Play with no restriction on the class of end user.

## 4. Cryptographic Functionality

The application uses only standard, publicly available encryption
algorithms accepted by international standards bodies (IETF/ISO/NIST).
No proprietary or non-standard cryptography is implemented.

| Purpose | Algorithm |
|---------|-----------|
| Transport security | TLS 1.3 |
| Key exchange | X25519 (ECDH, RFC 7748) |
| Symmetric encryption | AES-256-GCM; ChaCha20-Poly1305 (RFC 8439) |
| Hashing / integrity | SHA-256 |
| Protocol | VLESS with the Reality transport |

Maximum symmetric key length: 256 bits.
Maximum asymmetric key length: 256-bit elliptic curve (X25519).

## 5. Distribution

Distributed worldwide as a free application via the Apple App Store and
Google Play. Bundle identifier: `dev.rudnowski.freevpn`.

---

*This report is provided to the U.S. Bureau of Industry and Security (BIS)
and the ENC Encryption Request Coordinator (NSA) in satisfaction of the
annual self-classification reporting requirement, and to Apple Inc. as
export compliance documentation.*
