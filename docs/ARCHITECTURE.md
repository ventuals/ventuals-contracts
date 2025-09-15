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
  During genesis, this role is assigned to the GenesisVaultManager; once epochs begin, it will be assigned
  to the EpochVaultManager.
- `OPERATOR` – Handles automated, day-to-day protocol operations (e.g. transferring HYPE from HyperEVM to
  HyperCore, rotating the StakingVault's API wallets).

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
function transferToCoreAndDelegate() public onlyOperator;
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

## HyperEVM and HyperCore interaction timings

The L1Read precompiles will reflect the HyperCore state **at the beginning of the HyperEVM
block** ([Hyperliquid docs](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm/interaction-timings)).
This introduces a subtle timing issue when performing transfers from HyperEVM → HyperCore.

When a transfer occurs:

- The HyperEVM balance is reduced immediately.
- The HyperCore spot balance queried via L1Read is not updated until the next block.

This desynchronization means that immediately after a transfer to HyperCore, the vault's
`totalBalance()` computation will be incorrect, because it relies on both HyperEVM balances
and HyperCore spot balances. If a deposit happens after a transfer in the same block, we
will mint vHYPE against an inaccurate exchange rate.

To avoid this, we need to enforce a **one-block delay** between HyperEVM → HyperCore transfers
and any action (such as deposits) that requires an accurate totalBalance(). User deposits
will simply transfer HYPE to the StakingVault on HyperEVM, and then the OPERATOR will
periodically transfer the HYPE from HyperEVM to HyperCore.

In practice:

- Deposits are allowed at the beginning of a block, when L1Read values are up-to-date.
- When the OPERATOR initiates a HyperEVM → HyperCore transfer, subsequent deposits in
  that same block are reverted.
- Deposits may resume in the following block, once L1Read values are up-to-date again.

This ensures that the vault's exchange rate is computed consistently.

### Example:

**Block begins**

- 100 vHYPE supply
- 0 HYPE on HyperEVM
- 100 HYPE on HyperCore
- Exchange rate: 1 HYPE = 1 vHYPE

**User deposits 100 HYPE - `deposit()`**

- 200 vHYPE supply
- 100 HYPE on HyperEVM
- 100 HYPE on HyperCore
- Exchange rate: 1 HYPE = 1 vHYPE

**Operator transfers 100 HYPE to HyperCore - `transferToCoreAndDelegate()`**

- 200 vHYPE supply
- 0 HYPE on HyperEVM
  - ⇒ HyperEVM balance is immediately reduced
- 100 HYPE on HyperCore
  - ⇒ Should be 200 HYPE, but not reflected until next block
- Exchange rate: 1 HYPE = 2 vHYPE
  - ⇒ Exchange rate is incorrect

**Another user deposits 200 HYPE - `deposit()`**

- ⇒ Reverts

**Block ends**

**Next block begins**

- 200 vHYPE supply
- 0 HYPE on HyperEVM
- 200 HYPE on HyperCore
- Exchange rate: 1 HYPE = 1 vHYPE
- ⇒ This is correct now

**User deposits 200 HYPE - `deposit()`**

- 400 vHYPE supply
- 200 HYPE on HyperEVM
- 200 HYPE on HyperCore
- Exchange rate: 1 HYPE = 1 vHYPE

### Diagram

```mermaid
%%{init: {'theme':'neo-dark'}}%%
sequenceDiagram
    participant User
    participant GVM as GenesisVaultManager
    participant vHYPE as vHYPE Token
    participant SV as StakingVault
    participant L1R as L1Read
    participant HCSP as HyperCore Spot
    participant HCST as HyperCore Staking
    participant Op as Operator

    Note over User,Op: User deposits (block n)

    User->>+GVM: deposit() {value: HYPE amount}

    rect rgb(40, 40, 80)
        Note over GVM: canDeposit() modifier checks
        GVM->>GVM: Check: block.number >= lastEvmToCoreTransferBlockNumber + 1
        GVM->>GVM: Check: totalBalance() < vaultCapacity
        GVM->>GVM: Check: remainingDepositLimit() > 0
    end

    rect rgb(60, 40, 40)
        Note over GVM,HCST: Calculate totalBalance() - aggregates all balances

        GVM->>+L1R: delegatorSummary() for staking balance
        L1R->>+HCST: Query staking account
        HCST-->>-L1R: delegated + undelegated + pendingWithdrawal
        L1R-->>-GVM: Staking balance (reflects Block N-1 state)

        GVM->>+L1R: spotBalance() for spot balance
        L1R->>+HCSP: Query spot account
        HCSP-->>-L1R: spot balance
        L1R-->>-GVM: Spot balance (reflects Block N-1 state)

        GVM->>+SV: address(stakingVault).balance
        SV-->>-GVM: Current EVM balance

        GVM->>GVM: totalBalance = stakingBalance + spotBalance + evmBalance
    end

    rect rgb(40, 80, 40)
        Note over GVM,vHYPE: Calculate exchange rate and mint vHYPE
        GVM->>GVM: exchangeRate = totalBalance / vHYPE.totalSupply()
        GVM->>GVM: amountToMint = HYPETovHYPE(amountToDeposit)
        GVM->>+vHYPE: mint(msg.sender, amountToMint)
        vHYPE-->>User: vHYPE tokens
        vHYPE-->>-GVM: Success
    end

    rect rgb(80, 80, 40)
        Note over GVM,SV: Transfer HYPE to StakingVault (HyperEVM → HyperEVM)
        GVM->>+SV: Transfer HYPE via call{value: amountToDeposit}
        SV-->>-GVM: HYPE received on HyperEVM
    end

    alt requestedAmount > availableCapacity
        Note over GVM: Refund excess HYPE
        GVM->>User: call{value: refund}("")
    end

    GVM-->>-User: Deposit() event emitted

    Note over User,Op: Operator transfers HYPE from HyperEVM to HyperCore (block n)

    Op->>+GVM: transferToCoreAndDelegate()

    rect rgb(100, 40, 40)
        Note over GVM: Check timing constraint
        GVM->>GVM: require(block.number >= lastEvmToCoreTransferBlockNumber + 1)
    end

    rect rgb(80, 40, 80)
        Note over GVM,HCST: Transfer and delegate HYPE
        GVM->>+SV: transferHypeToCore(amount)
        SV->>+HCSP: Transfer HYPE (HyperEVM → HyperCore Spot)
        Note right of SV: EVM balance reduced immediately
        HCSP-->>-SV: Success
        SV-->>-GVM: HYPE transferred to HyperCore

        GVM->>+SV: stakingDeposit(amount)
        SV->>+HCST: Transfer (HyperCore Spot → HyperCore Staking)
        HCST-->>-SV: Success
        SV-->>-GVM: HYPE moved to staking

        GVM->>+SV: tokenDelegate(defaultValidator, amount)
        SV->>+HCST: Delegate to validator
        HCST-->>-SV: HYPE delegated
        SV-->>-GVM: Success
    end

    GVM->>GVM: lastEvmToCoreTransferBlockNumber = block.number
    GVM-->>-Op: Transfer completed

    Note over User,Op: Subsequent user deposit fails (block n)

    User->>+GVM: deposit() {value: HYPE amount}

    rect rgb(100, 40, 40)
        Note over GVM: Timing check fails!
        GVM->>GVM: require(block.number >= lastEvmToCoreTransferBlockNumber + 1)
        Note right of GVM: block.number = N<br/>lastEvmToCoreTransferBlockNumber = N<br/>N >= N + 1 = false
        GVM-->>User: ❌ CannotDepositUntilNextBlock()
    end

    GVM-->>-User: Transaction reverted

    Note over User,Op: Next block user deposit (block n + 1)

    User->>+GVM: deposit() {value: HYPE amount}

    rect rgb(40, 80, 40)
        Note over GVM: Timing check passes
        GVM->>GVM: require(block.number >= lastEvmToCoreTransferBlockNumber + 1)
        Note right of GVM: block.number = N+1<br/>lastEvmToCoreTransferBlockNumber = N<br/>N+1 >= N + 1 = true ✓
    end

    rect rgb(60, 40, 40)
        Note over GVM,HCST: totalBalance() now accurate
        GVM->>+L1R: Get updated HyperCore balances
        Note right of L1R: L1Read now reflects the<br/>HyperEVM → HyperCore transfer<br/>that happened in Block N
        L1R-->>-GVM: Updated balances
        GVM->>GVM: totalBalance = correct sum of all balances
    end

    Note over GVM: Continue with normal deposit flow...
    GVM-->>-User: Deposit successful with correct exchange rate
```
