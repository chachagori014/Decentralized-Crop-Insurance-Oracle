# 🌾 Cropguard - Decentralized Crop Insurance Oracle

> Protecting farmers with smart contracts and satellite data 🛰️

## 📖 Overview

Cropguard is a decentralized crop insurance platform built on the Stacks blockchain. It uses oracle-provided weather data to automatically trigger insurance payouts when adverse weather conditions damage crops, eliminating the need for manual claim processing.

## ✨ Features

- 🚜 **Automated Policy Creation**: Farmers can create custom insurance policies
- 🌡️ **Weather Oracle Integration**: Real-time weather data from authorized oracles
- ⚡ **Automatic Payouts**: Claims processed instantly when conditions are met
- 🔒 **Transparent**: All operations recorded on blockchain
- 💰 **Premium Calculation**: Smart premium pricing based on coverage amount

## 🚀 Getting Started

### Prerequisites

- Clarinet CLI installed
- Stacks wallet with STX tokens

### Installation

```bash
git clone https://github.com/yourusername/cropguard
cd cropguard
clarinet console
```

## 📋 Usage

### 1. Create Insurance Policy 📝

```clarity
(contract-call? .cropguardd create-policy 
  "corn"           ;; crop-type
  u1000000         ;; coverage-amount (in microSTX)
  u8640            ;; duration-blocks (~60 days)
  4000000          ;; latitude (decimal degrees * 1000000)
  -9000000         ;; longitude (decimal degrees * 1000000)
  u500             ;; min-rainfall (mm)
  u350             ;; max-temperature (celsius * 10)
)
```

### 2. Submit Weather Data (Oracles Only) 🌤️

```clarity
(contract-call? .cropguardd submit-weather-data
  u1               ;; policy-id
  u450             ;; rainfall (mm)
  u380             ;; temperature (celsius * 10)
  u75              ;; humidity (%)
  u25              ;; wind-speed (km/h)
)
```

### 3. Submit Insurance Claim 📞

```clarity
(contract-call? .cropguardd submit-claim u1)  ;; policy-id
```

### 4. Check Policy Status 📊

```clarity
(contract-call? .cropguardd get-policy-status u1)
```

## 🔧 Admin Functions

### Authorize Oracle

```clarity
(contract-call? .cropguardd authorize-oracle 'SP1ABC...)
```

### Fund Contract

```clarity
(contract-call? .cropguardd fund-contract)
```

## 📊 Read-Only Functions

- `get-policy(policy-id)` - Get policy details
- `get-farmer-policies(farmer)` - Get all policies for a farmer
- `get-weather-data(policy-id, timestamp)` - Get weather data for policy
- `get-claim-request(policy-id)` - Get claim status
- `is-oracle-authorized(oracle)` - Check oracle authorization
- `get-contract-stats()` - Get contract statistics
- `calculate-premium(coverage-amount)` - Calculate insurance premium

## 🎯 How It Works

1. **Policy Creation** 🆕: Farmers create policies specifying crop type, location, coverage amount, and weather thresholds
2. **Premium Payment** 💳: Farmers pay 5% of coverage amount as premium
3. **Weather Monitoring** 📡: Authorized oracles submit weather data throughout policy period
4. **Automatic Claims** ⚡: Claims automatically processed when weather conditions breach thresholds
5. **Instant Payouts** 💸: Qualifying claims receive immediate STX payouts

## 🌡️ Weather Conditions

Payouts trigger when:
- Average rainfall < minimum threshold
- Maximum temperature > maximum threshold

## 🏗️ Smart Contract Architecture

- **Policies Map**: Stores all insurance policy data
- **Weather Data Map**: Historical weather information
- **Authorized Oracles**: Trusted data providers
- **Claim Requests**: Pending and processed claims
- **Farmer Policies**: Links farmers to their policies

## 🔐 Security Features

- Owner-only admin functions
- Oracle authorization system
- Balance validation for payouts
- Duplicate policy prevention
- Claim processing safeguards

## 🧪 Testing

```bash
clarinet test
```

## 📈 Contract Statistics

Monitor contract performance:
- Total policies created
- Total claims paid out
- Current contract balance
- Next available policy ID

## 🤝 Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

## 📄 License

This project is licensed under the MIT License.

## 🆘 Support

For support and questions:
- Create an issue on GitHub
- Contact the development team

---

*for farmers worldwide* 🌍
