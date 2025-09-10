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
