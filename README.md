# 🚚 Aidflow - Transparent Aid Delivery Supply Chain

> 📦 Track donations from donor to recipient with complete transparency and accountability

## 🌟 Overview

Aidflow is a blockchain-based supply chain management system for aid delivery that ensures complete transparency in donation logistics. Built on the Stacks blockchain using Clarity smart contracts, it enables donors, organizations, and carriers to track aid from donation to final delivery.

## ✨ Key Features

- 🏢 **Organization Registration**: Aid organizations can register and get verified
- 💰 **Transparent Donations**: Donors can contribute STX tokens to verified organizations
- 📋 **Shipment Tracking**: Real-time tracking of aid packages through the supply chain
- 🚛 **Carrier Authorization**: Authorized carriers manage shipment logistics
- ✅ **Delivery Confirmation**: Automated fund release upon confirmed delivery
- 🔍 **Full Transparency**: All transactions and status updates are publicly verifiable

## 🚀 Getting Started

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) installed
- Stacks wallet for testing

### Installation

1. Clone this repository
2. Navigate to the project directory
3. Run Clarinet commands to interact with the contract

```bash
clarinet console
```

## 📖 Usage Guide

### For Aid Organizations 🏥

1. **Register your organization**:
   ```clarity
   (contract-call? .Aidflow register-organization "Red Cross" "New York, USA")
   ```

2. **Wait for verification** from contract owner

3. **Create shipments** for received donations:
   ```clarity
   (contract-call? .Aidflow create-shipment u1 "Warehouse A" "Disaster Zone B" "Medical supplies, food")
   ```

### For Donors 💝

1. **Make a donation** to a verified organization:
   ```clarity
   (contract-call? .Aidflow make-donation u1 "Emergency medical aid")
   ```

2. **Track your donation** using the donation ID returned

### For Carriers 🚚

1. **Get authorized** by the contract owner
2. **Update shipment status** during transit:
   ```clarity
   (contract-call? .Aidflow update-shipment-status u1 "in-transit")
   ```

3. **Confirm delivery** to release funds:
   ```clarity
   (contract-call? .Aidflow confirm-delivery u1)
   ```

### For Contract Owners 👑

1. **Verify organizations**:
   ```clarity
   (contract-call? .Aidflow verify-organization u1)
   ```

2. **Authorize carriers**:
   ```clarity
   (contract-call? .Aidflow authorize-carrier 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7)
   ```

## 🔍 Read-Only Functions

- `get-donation`: Retrieve donation details
- `get-shipment`: Get shipment information
- `get-organization`: View organization data
- `get-organization-by-wallet`: Find organization by wallet address
- `is-carrier-authorized`: Check carrier authorization status

## 📊 Data Flow

1. 🏢 Organizations register and get verified
2. 💰 Donors make STX donations to verified organizations
3. 📦 Organizations create shipments for donations
4. 🚛 Authorized carriers update shipment status
5. ✅ Upon delivery confirmation, funds are released to organizations
6. 📈 Organizations' total received amounts are updated

## 🛡️ Security Features

- Only verified organizations can receive donations
- Only authorized carriers can update shipment status
- Funds are held in escrow until delivery confirmation
- All actions are recorded on-chain for transparency

## 🎯 Status Tracking

### Donation Status
- `pending`: Donation made, awaiting shipment
- `shipped`: Shipment created and in transit
- `delivered`: Successfully delivered to recipient

### Shipment Status
- `in-transit`: Package is being transported
- `delivered`: Package has reached destination
- Custom status updates allowed for detailed tracking

## 🤝 Contributing

This is an MVP implementation. Future enhancements could include:
- Multi-token support
- Batch donations
- GPS tracking integration
- Reputation system for carriers
- Mobile app interface

## 📄 License

Open source - feel free to fork and improve! 🚀

