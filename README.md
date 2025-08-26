# EduChain Credentials - Soulbound NFT Certificates

A smart contract system for issuing non-transferable (soulbound) NFT certificates for online courses, workshops, and educational achievements. Prevents fake diplomas and provides verifiable on-chain learning records.

## Features

- Soulbound NFT certificates (non-transferable)
- Authorized issuer system for institutions
- Certificate verification and authenticity checking
- Metadata URI support for rich certificate data
- Revocation system for invalid certificates
- Comprehensive recipient tracking

## Contract Functions

### Public Functions
- `authorize-issuer` - Authorize educational institutions to issue certificates
- `issue-certificate` - Issue soulbound certificate to recipient
- `revoke-certificate` - Revoke invalid certificates
- `verify-certificate` - Verify certificate with hash comparison
- `transfer` - Blocked function (soulbound implementation)

### Read-Only Functions
- `get-certificate` - Get certificate details by ID
- `get-recipient-certificates` - Get all certificates for recipient
- `verify-completion` - Check if recipient completed specific course
- `get-issuer-info` - Get authorized issuer information
- `is-authorized-issuer` - Check if principal can issue certificates

## Soulbound Properties

Certificates are permanently bound to recipients and cannot be transferred, ensuring:
- Authentic ownership verification
- Prevention of certificate trading/selling
- Immutable educational records
- Trust in credential authenticity

## Usage

1. Contract owner authorizes educational institutions
2. Institutions issue certificates with course completion data
3. Recipients receive soulbound NFTs as proof of completion
4. Certificates can be verified by third parties
5. Invalid certificates can be revoked by issuers