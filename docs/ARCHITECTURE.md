# Architecture

## Overview

The Ventuals HYPE LST enables contributors to stake HYPE and receive vHYPE, a fully
transferable ERC20 that represents their staked principal.

The lifecycle of the system begins with a _genesis_ phase, which covers the initial HYPE
stake raise required for HIP-3 mainnet deployment. During genesis, native HYPE staking
rewards accrue automatically, reflected in the vHYPE/HYPE exchange rate. After genesis,
the protocol will transition into epoch-based staking with scheduled deposit and withdraw
windows. All HYPE deposited during genesis will automatically rollover to the first epoch,
and remain locked until the end of the first epoch.

After the Ventuals mainnet deployment, staking will be organized into discrete epochs,
during which HYPE deposits remain locked. At the end of each epoch, contributors can
choose to redeem their HYPE, roll over their HYPE into the next epoch, or deposit
additional HYPE. The first epoch will be 1 year; subsequent epochs will last 6 months.
This structure ensures predictable and guaranteed withdrawal windows for all contributors.

This repository currently includes the contracts required for the genesis phase. Contracts
for epoch-based staking will be finalized in a future release.

## Architecture

TODO: Add architecture diagram

## Access Control

The Ventuals protocol uses a centralized role-based access control system (via the RoleRegistry contract).

### Roles

- `OWNER` – Has the highest level of control. Can upgrade and pause contracts, grant and revoke roles, set
  vault parameters, and execute emergency operations (e.g., withdrawing HYPE). This role is controlled by
  the Ventuals multisig.
- `MANAGER` – Manages the vault. Can deposit, withdraw, delegate, and transfer HYPE on behalf of the vault.
  During genesis, this role is assigned to the GenesisVaultManager; once epochs begin, it will be assigned to the EpochVaultManager.
- `OPERATOR` – Handles automated, day-to-day protocol operations (e.g. rotating the StakingVault's
  API wallets).

## Contracts

All contracts are [UUPSUpgradeable](https://docs.openzeppelin.com/contracts/5.x/api/proxy#UUPSUpgradeable)
proxies, and upgrades may only be performed by the `OWNER`.

### StakingVault

- Holds the HYPE that gets staked
- Will be the address of the Ventuals HIP-3 subdex deployer
- Provides a thin wrapper around CoreWriter staking and delegation functionality, restricted to the `MANAGER` role
- Managed by the GenesisVaultManager during genesis, and by the EpochVaultManager once epochs begin

#### Key functions

```solidity
function stakingDeposit(uint64 weiAmount) external onlyManager;
function stakingWithdraw(uint64 weiAmount) external onlyManager;
function tokenDelegate(address validator, uint64 weiAmount, bool isUndelegate) external onlyManager;
function spotSend(address destination, uint64 token, uint64 weiAmount) external onlyManager;
function transferHypeToCore(uint256 amount) external onlyManager;
function transferHype(address payable recipient, uint256 amount) external onlyManager;
function addApiWallet(address apiWalletAddress, string calldata name) external onlyOperator;
```

### GenesisVaultManager

- Enforces the HYPE vault capacity and deposit limits
- Mints vHYPE to HYPE according to the current exchange rate
- Deposits are locked until the end of the first epoch; withdrawals are not allowed before then
- All vHYPE holders automatically earn native staking yield — no need to stake vHYPE separately
- As underlying HYPE in the vault grows from native yield, the GenesisVaultManager mints new vHYPE proportionally

#### Key functions

```solidity
function deposit() public canDeposit;
function exchangeRate() public view returns (uint256);
function totalBalance() public view returns (uint256);
```

### vHYPE

- Standard ERC20 token
- Only the `MANAGER` role can mint vHYPE - assigned to the GenesisVaultManager during genesis, and
  will be assigned to the EpochVaultManager once epochs begin.

#### Key functions

```solidity
function mint(address to, uint256 amount) external onlyManager;
function burn(address from, uint256 amount) external;
```

### RoleRegistry

The RoleRegistry contract centralizes role-based access control across the protocol. Any contract in the
protocol that requires role-based access control should reference the RoleRegistry.

Roles:

- `OWNER`
- `MANAGER`
- `OPERATOR`

#### Key functions

```solidity
function grantRole(bytes32 role, address account) public override onlyOwner;
function revokeRole(bytes32 role, address account) public override onlyOwner;
function pause(address contractAddress) external onlyOwner;
function unpause(address contractAddress) external onlyOwner
```
