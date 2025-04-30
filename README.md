# Aucpay

## Revolutionizing Payments at Auction Events with Clarity

## Table of Contents
- [Overview](#overview)
- [Features](#features)
- [Technology Stack](#technology-stack)
- [Getting Started](#getting-started)
- [Architecture](#architecture)
- [Smart Contracts](#smart-contracts)
- [Development](#development)
- [Testing](#testing)
- [Deployment](#deployment)
- [Security](#security)
- [Contributing](#contributing)
- [License](#license)

## Overview

Aucpay is a decentralized application built on Stacks blockchain that streamlines the payment process at auction events. By leveraging the power of Clarity smart contracts, Aucpay provides a secure, transparent, and efficient payment system for auction houses, sellers, and bidders.

Traditional auction payment systems often suffer from lengthy settlement times, high transaction fees, and limited transparency. Aucpay addresses these pain points by providing instant settlements, reduced fees, and complete transaction visibility through blockchain technology.

## Features

- **Instant Settlement**: Payments are processed and settled immediately after auction completion
- **Transparency**: All transactions are recorded on the Stacks blockchain and publicly verifiable
- **Escrow Services**: Built-in escrow functionality to protect both buyers and sellers
- **Multi-currency Support**: Accept payments in STX, Bitcoin (via sBTC), and supported fungible tokens
- **Auction Management**: Tools for creating, managing, and concluding auctions
- **Fee Optimization**: Lower transaction fees compared to traditional payment processors
- **Bidder Identity Verification**: Optional KYC integration for regulatory compliance
- **Automated Commission Calculation**: Instant distribution of proceeds to sellers and auction houses
- **Dispute Resolution System**: Smart contract-based resolution for transaction disputes
- **Real-time Notifications**: Instant updates on bids, payments, and auction status

## Technology Stack

- **Blockchain**: [Stacks](https://www.stacks.co/)
- **Smart Contract Language**: [Clarity](https://clarity-lang.org/)
- **Frontend**: React.js
- **Backend**: Node.js
- **Authentication**: Stacks Connect
- **Data Storage**: Gaia Storage & IPFS
- **API Integration**: Stacks API

## Getting Started

### Prerequisites

- Node.js (v16 or higher)
- Stacks CLI
- Clarity VS Code Extension (recommended)

### Installation

1. Clone the repository:
```bash
git clone https://github.com/aucpay/aucpay.git
cd aucpay
```

2. Install dependencies:
```bash
npm install
```

3. Configure environment variables:
```bash
cp .env.example .env
```

4. Start the development server:
```bash
npm run dev
```

### Connecting to Stacks Blockchain

Aucpay connects to the Stacks blockchain through Stacks Connect. Users can authenticate using their Stacks wallet (Hiro Wallet, Xverse, etc.).

```javascript
import { AppConfig, UserSession, showConnect } from '@stacks/connect';

const appConfig = new AppConfig(['store_write', 'publish_data']);
const userSession = new UserSession({ appConfig });

// Authentication function
function authenticate() {
  showConnect({
    appDetails: {
      name: 'Aucpay',
      icon: window.location.origin + '/logo.svg',
    },
    redirectTo: '/',
    onFinish: () => {
      window.location.reload();
    },
    userSession,
  });
}
```

## Architecture

Aucpay follows a modular architecture with clear separation between the core payment system and the auction management components:

1. **Core Payment Module**
   - Transaction processing
   - Escrow management
   - Fee calculation and distribution

2. **Auction Management Module**
   - Auction creation and setup
   - Bidding system
   - Auction conclusion and settlement

3. **User Interface Layer**
   - Auction browse/search
   - Bidder interface
   - Seller dashboard
   - Admin controls

4. **Integration Layer**
   - API for auction houses
   - Integration with payment processors
   - External services connectors

## Smart Contracts

### Main Contracts

#### AucpayEscrow

The escrow contract handles the secure holding and release of funds during the auction process.

```clarity
;; AucpayEscrow.clar
;; Manages escrow for auction payments

(define-data-var escrow-fee uint u25) ;; 0.25% default fee

(define-map escrows
  { auction-id: uint, bidder: principal }
  { amount: uint, status: (string-ascii 20) }
)

(define-public (deposit-escrow (auction-id uint))
  (let
    (
      (amount (get-bid-amount auction-id))
      (sender tx-sender)
    )
    (if (> amount u0)
      (begin
        (try! (stx-transfer? amount sender (as-contract tx-sender)))
        (map-set escrows { auction-id: auction-id, bidder: sender } { amount: amount, status: "deposited" })
        (ok true)
      )
      (err u1)
    )
  )
)

;; Additional functions for escrow management and release
```

#### AucpayAuction

Handles the auction creation, bidding, and finalization process.

```clarity
;; AucpayAuction.clar
;; Manages auctions and bidding

(define-map auctions
  { id: uint }
  { 
    seller: principal,
    start-price: uint,
    reserve-price: uint,
    end-block: uint,
    status: (string-ascii 20),
    highest-bid: uint,
    highest-bidder: (optional principal)
  }
)

(define-data-var next-auction-id uint u1)

(define-public (create-auction (start-price uint) (reserve-price uint) (blocks-duration uint))
  (let
    (
      (auction-id (var-get next-auction-id))
      (end-block (+ block-height blocks-duration))
    )
    (map-set auctions 
      { id: auction-id }
      {
        seller: tx-sender,
        start-price: start-price,
        reserve-price: reserve-price,
        end-block: end-block,
        status: "active",
        highest-bid: u0,
        highest-bidder: none
      }
    )
    (var-set next-auction-id (+ auction-id u1))
    (ok auction-id)
  )
)

;; Additional functions for bidding and auction management
```

### Contract Interactions

The following diagram illustrates how the Aucpay smart contracts interact with each other:

```
User -> AucpayAuction (place bid) -> AucpayEscrow (deposit funds)
                                  -> AucpayPayment (process payment)
                                  -> AucpayFees (calculate fees)
```

## Development

### Development Environment Setup

1. Set up Clarity development environment:
```bash
npm install -g @stacks/cli
```

2. Start local Stacks blockchain for development:
```bash
stacks-node start --config=./config/stacks-local.toml
```

3. Deploy contracts to local environment:
```bash
clarinet deploy --network=development
```

### Development Best Practices

- Write thorough tests for all smart contract functions
- Use explicit type declarations in Clarity code
- Follow the principle of least privilege for contract functions
- Document all public functions and state variables
- Use post-conditions for all transactions that transfer value

## Testing

Aucpay uses both unit tests and integration tests to ensure reliability:

### Unit Testing

```bash
npm run test:unit
```

### Integration Testing

```bash
npm run test:integration
```

### Clarity Contract Testing

```bash
clarinet test
```

Example test for the `create-auction` function:

```clarity
;; tests/auction-tests.clar

(use-trait-test "contracts/AucpayAuction.clar")

(define-test "can create an auction"
  (let
    (
      (result (contract-call? 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.AucpayAuction create-auction u1000 u5000 u144))
    )
    (asserts! (is-ok result) "Failed to create auction")
    (asserts! (is-eq (unwrap-panic result) u1) "Auction ID should be 1")
  )
)
```

## Deployment

### Testnet Deployment

1. Configure your testnet credentials:
```bash
stacks config setup --testnet
```

2. Deploy to Stacks testnet:
```bash
clarinet deploy --network=testnet
```

### Mainnet Deployment

1. Configure your mainnet credentials:
```bash
stacks config setup --mainnet
```

2. Deploy to Stacks mainnet:
```bash
clarinet deploy --network=mainnet
```

## Security

Security is a priority for Aucpay. The project implements:

- Smart contract audits before major releases
- Formal verification of critical contract functions
- Rate limiting for sensitive operations
- Multi-signature requirements for admin operations
- Insurance fund for user protection
- Bug bounty program

## Contributing

We welcome contributions from the community! To contribute:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Contact

- Project Website: [https://aucpay.io](https://aucpay.io)
- GitHub: [https://github.com/aucpay](https://github.com/aucpay)
- Twitter: [@aucpay](https://twitter.com/aucpay)

For inquiries, please email: contact@aucpay.io
