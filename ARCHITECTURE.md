# Architecture

# Contract interactions

## Genesis deposit

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

    User->>+GVM: deposit() {value: HYPE amount}

    Note over GVM: Check vault balance

    rect dimgray
        Note over GVM,HCST: Aggregates balances across all accounts

        GVM->>+L1R: Get HyperCore balances
        L1R->>+HCSP: Get spot balance
        HCSP-->>-L1R: spot balance
        L1R->>+HCST: Get staking balance
        HCST-->>-L1R: staking balance
        L1R-->>-GVM: HyperCore balances
        GVM->>+SV: Get EVM balance
        SV-->>-GVM: EVM balance
        GVM->>GVM: Get protocol withdrawals
        GVM->>GVM: totalBalance = HyperCore + EVM + protocol withdrawals
    end

    Note over GVM: Mint vHYPE
    GVM->>+vHYPE: mint(msg.sender, amountToMint)
    vHYPE-->>-User: vHYPE tokens

    Note over GVM: Stake

    rect dimgray
        Note over GVM,HCST: Transfer and stake HYPE via StakingVault
        GVM->>+SV: Transfer HYPE to EVM
        SV-->>-GVM: Success
        GVM->>+SV: Transfer HYPE to Spot
        SV->>+HCSP: Transfer HYPE to Spot
        HCSP-->>-SV: Success
        SV-->>-GVM: HYPE transferred to Spot

        GVM->>+SV: Transfer HYPE to Staking
        SV->>+HCST: Transfer HYPE to Staking
        HCST-->>-SV: Success
        SV-->>-GVM: HYPE transferred to Staking

        GVM->>+SV: Delegate HYPE
        SV->>+HCST: Delegate HYPE
        HCST-->>-SV: Success
        SV-->>-GVM: HYPE delegated
    end

    alt requestedAmount > remainingCapacity
        Note over GVM: Refund excess HYPE
        GVM->>User: call{value: refund}("")
    end

    GVM-->>-User: Success
```

## Protocol withdraw (single-step)

Executes a single-step withdraw process if we leave HYPE as HyperEVM reserves.
No HyperCore interactions are required.

```mermaid
%%{init: {'theme':'neo-dark'}}%%
sequenceDiagram
    participant Owner
    participant GVM as GenesisVaultManager
    participant SV as StakingVault

    Note over Owner,SV: Withdrawal from Vault

    Owner->>+GVM: protocolWithdraw(amount, purpose)

    GVM->>GVM: cumulativeProtocolWithdrawals += amount
    GVM->>SV: transferHype(payable(owner), amount)
    SV->>Owner: Transfer HYPE to owner

    GVM-->>-Owner: Withdraw complete
```

## Protocol withdraw (multi-step)

Executes a multi-step withdraw process if we stake all HYPE and don't leave any HYPE as HyperEVM reserves.

```mermaid
%%{init: {'theme':'neo-dark'}}%%
sequenceDiagram
    participant Owner
    participant GVM as GenesisVaultManager
    participant SV as StakingVault
    participant HCST as HyperCore Staking
    participant HCSP as HyperCore Spot

    Note over Owner,HCSP: Step 1: Queue Staking Withdrawal

    Owner->>+GVM: protocolQueueStakingWithdraw(amount, purpose)

    GVM->>+SV: tokenDelegate(VALIDATOR, amount, true) (undelegates)
    SV->>+HCST: CoreWriter.tokenDelegate(validator, amount, true)
    Note over HCST: Immediately undelegate HYPE from validator
    HCST-->>-SV: Success
    SV-->>-GVM: Success

    GVM->>+SV: stakingWithdraw(amount)
    SV->>+HCST: CoreWriter.stakingWithdraw(amount)
    Note over HCST: Queue withdrawal (7-day delay)
    HCST-->>-SV: Success
    SV-->>-GVM: Success

    GVM-->>-Owner: Success

    Note over Owner,HCSP: 7 days later...

    Note over Owner,HCSP: Step 2: Transfer from HyperCore Spot to HyperEVM

    Owner->>+GVM: protocolSpotToEvmWithdraw(amount, purpose)


    GVM->>+SV: spotSend(0x2222...2222, HYPE_TOKEN_ID, amount)
    SV->>+HCSP: CoreWriter.spotSend(0x2222...2222, HYPE_TOKEN_ID, amount)
    Note over HCSP: Transfer HYPE from HyperCore Spot to HyperEVM
    HCSP-->>-SV: Success
    SV-->>-GVM: Success

    GVM-->>-Owner: Success

    Note over Owner,HCSP: Step 3: Final Withdrawal from Vault

    Owner->>+GVM: protocolWithdraw(amount, purpose)

    GVM->>GVM: cumulativeProtocolWithdrawals += amount
    GVM->>SV: transferHype(payable(owner), amount)
    SV->>Owner: Transfer HYPE to owner

    GVM-->>-Owner: Withdraw complete
```
