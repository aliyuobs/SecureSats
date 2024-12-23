# SecureStats

SecureStats is a decentralized Bitcoin-backed lending protocol built on the Stacks blockchain. It enables users to obtain STX loans using their STX as collateral (with future plans for Bitcoin collateral), all managed through secure smart contracts.

## Features

- **Secure Collateralization**: Lock up STX as collateral through smart contracts
- **Dynamic Interest Rates**: Interest rates adjust based on collateralization ratio
- **Liquidation System**: Automated liquidation process with rewards for liquidators
- **Risk Management**: Configurable collateral ratios and liquidation thresholds
- **User Dashboard**: Track loan health and manage positions

## Technical Architecture

The protocol currently consists of a core lending contract that handles all primary functionality:

### Core Contract Functions

1. **Loan Management**
   - `create-loan`: Create a new loan position
   - `repay-loan`: Repay an existing loan
   - `add-collateral`: Add collateral to existing loan
   - `check-loan-health`: Monitor loan health status

2. **Liquidation System**
   - `liquidate-loan`: Process liquidation of unhealthy loans
   - Liquidator reward: 5% of collateral
   - Protocol fee: 1% of collateral

3. **Administrative Controls**
   - `update-minimum-collateral-ratio`: Adjust minimum required collateral
   - `update-liquidation-threshold`: Modify liquidation trigger threshold

### Key Parameters

- Minimum Loan Amount: 1M uSTX
- Maximum Loan Amount: 1B uSTX
- Minimum Collateralization Ratio: 150%
- Liquidation Threshold: 130%
- Base Interest Rate: 5%
- Protocol Fee: 1%
- Liquidator Reward: 5%

## Getting Started

### Prerequisites

- Stacks Wallet (Hiro or similar)
- STX for collateral and transaction fees

### Usage Examples

1. **Creating a Loan**
   ```clarity
   ;; Create a loan with 1.5M uSTX collateral for 1M uSTX loan
   (contract-call? .secure-stats create-loan u1500000 u1000000)
   ```

2. **Adding Collateral**
   ```clarity
   ;; Add 500K uSTX collateral to loan #1
   (contract-call? .secure-stats add-collateral u1 u500000)
   ```

3. **Checking Loan Health**
   ```clarity
   ;; Check health status of loan #1
   (contract-call? .secure-stats check-loan-health u1)
   ```

4. **Repaying a Loan**
   ```clarity
   ;; Repay loan #1
   (contract-call? .secure-stats repay-loan u1)
   ```

## Security Features

- Comprehensive error handling with specific error codes
- Input validation for all parameters
- Protected administrative functions
- Loan ID validation
- Safe math operations
- Liquidation protection mechanisms

## Future Development

### Short-term Roadmap
- Integration with Bitcoin as collateral
- Price oracle implementation
- Governance system deployment
- Advanced liquidation mechanisms

### Long-term Vision
- Multi-collateral support
- Flash loan functionality
- Yield-generating strategies
- Cross-chain integrations

## Technical Details

### Error Codes
- `ERR-OWNER-ONLY (100)`: Unauthorized administrative access
- `ERR-INVALID-LOAN (101)`: Invalid loan parameters
- `ERR-INSUFFICIENT-COLLATERAL (102)`: Collateral below minimum
- `ERR-LOAN-NOT-FOUND (103)`: Non-existent loan ID
- `ERR-ALREADY-LIQUIDATED (104)`: Loan already liquidated
- `ERR-NOT-LIQUIDATABLE (105)`: Loan not eligible for liquidation
- `ERR-NOT-BORROWER (106)`: Unauthorized loan access
- `ERR-INVALID-AMOUNT (107)`: Invalid amount specified
- `ERR-INVALID-PARAMETER (108)`: Invalid parameter value
- `ERR-INVALID-LOAN-ID (109)`: Invalid loan ID

## Contributing

We welcome contributions! Before submitting PRs:

1. Review the smart contract code
2. Test your changes thoroughly
3. Follow Clarity best practices
4. Update documentation as needed

