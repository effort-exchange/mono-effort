## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

### Overview
```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                     CONTRACT INTERACTION SUMMARY                                 │
└─────────────────────────────────────────────────────────────────────────────────┘

                              ┌─────────────┐
                              │    USERS    │
                              └──────┬──────┘
                                     │
                    ┌────────────────┼────────────────┐
                    │                │                │
                    ▼                ▼                ▼
              deposit()      allocateVotes()   finalizeEpoch()
                    │                │                │
                    ▼                │                │
    ┌───────────────────────────┐    │                │
    │       GLOBAL VAULT        │    │                │
    │  ┌─────────────────────┐  │    │                │
    │  │ • Hold USDC         │  │    │                │
    │  │ • Mint/Burn allocVOTE  │    │                │
    │  │ • Track whitelist   │  │    │                │
    │  └─────────────────────┘  │    │                │
    └────────────┬──────────────┘    │                │
                 │                   │                │
                 │ USDC + recordAllocation()          │
                 │                   │                │
                 └───────────────────┼────────────────┘
                                     │
                                     ▼
                      ┌───────────────────────────┐
                      │          ROUTER           │
                      │  ┌─────────────────────┐  │
                      │  │ • Escrow USDC       │  │
                      │  │ • Track allocations │  │
                      │  │ • Manage epochs     │  │
                      │  └─────────────────────┘  │
                      └────────────┬──────────────┘
                                   │
                                   │ finalizeEpoch()
                                   │ (only at epoch boundary)
                                   │
                    ┌──────────────┴──────────────┐
                    │                             │
                    ▼                             ▼
    ┌───────────────────────────┐ ┌───────────────────────────┐
    │     CHARITY VAULT #1      │ │     CHARITY VAULT #2      │
    │      (Clean Water)        │ │    (Cancer Research)      │
    │  ┌─────────────────────┐  │ │  ┌─────────────────────┐  │
    │  │ • Receive USDC      │  │ │  │ • Receive USDC      │  │
    │  │ • Mint grantVote    │  │ │  │ • Mint grantVote    │  │
    │  │ • [Future: Grants]  │  │ │  │ • [Future: Grants]  │  │
    │  └─────────────────────┘  │ │  └─────────────────────┘  │
    └───────────────────────────┘ └───────────────────────────┘
```
### Deposit (Donors deposit underlying asset, get voting token)
```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                            DEPOSIT FLOW                                          │
└─────────────────────────────────────────────────────────────────────────────────┘

    User                         USDC                    GlobalVault
      │                           │                           │
      │  1. approve(globalVault,  │                           │
      │            100 USDC)      │                           │
      │──────────────────────────>│                           │
      │                           │                           │
      │  2. deposit(100, user)    │                           │
      │──────────────────────────────────────────────────────>│
      │                           │                           │
      │                           │  3. transferFrom(user,    │
      │                           │     vault, 100)           │
      │                           │<──────────────────────────│
      │                           │                           │
      │                           │                           │  4. Calculate shares:
      │                           │                           │     shares = previewDeposit(100)
      │                           │                           │     (ERC4626 standard math)
      │                           │                           │
      │                           │                           │  5. _mint(user, shares)
      │                           │                           │     → User receives allocVote
      │                           │                           │
      │ 6. Return: 100 allocVote* │                           │
      │<──────────────────────────────────────────────────────│
      │                           │                           │

    * If no dilution: 100 USDC = 100 allocVote
      If dilution exists: shares = 100 * totalSupply / totalAssets
```


### User allocation funds from global vault to charity specific vaults
```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                      VOTE ALLOCATION FLOW                                        │
│                  (Immediate USDC transfer to Router)                            │
└─────────────────────────────────────────────────────────────────────────────────┘

   User           GlobalVault            USDC              Router
     │                 │                   │                  │
     │ 1. allocateVotes                    │                  │
     │   (cleanWater,  │                   │                  │
     │    50 votes)    │                   │                  │
     │────────────────>│                   │                  │
     │                 │                   │                  │
     │                 │ 2. Validate:      │                  │
     │                 │    • User has 50 allocVOTE              │
     │                 │    • cleanWater is registered       │
     │                 │                   │                  │
     │                 │ 3. Calculate USDC:│                  │
     │                 │    usdcAmount = convertToAssets(50) │
     │                 │    e.g., 52.5 if diluted            │
     │                 │                   │                  │
     │                 │ 4. _burn(user, 50 allocVOTE)            │
     │                 │    → Votes destroyed immediately    │
     │                 │                   │                  │
     │                 │ 5. Transfer USDC  │                  │
     │                 │    to Router      │                  │
     │                 │──────────────────>│                  │
     │                 │                   │──────────────────>│
     │                 │                   │                  │
     │                 │ 6. recordAllocation                  │
     │                 │   (user, cleanWater, 50, 52.5)      │
     │                 │─────────────────────────────────────>│
     │                 │                   │                  │
     │                 │                   │                  │ 7. Update state:
     │                 │                   │                  │    allocations[epoch][user][cleanWater] += 50
     │                 │                   │                  │    epochCharityUSDC[epoch][cleanWater] += 52.5
     │                 │                   │                  │    Track user in epochUsers
     │                 │                   │                  │
     │ 8. Success      │                   │                  │
     │<────────────────│                   │                  │
     │                 │                   │                  │

    STATE AFTER:
    ┌─────────────────────────────────────────────────────────────────────────┐
    │  GlobalVault: User's allocVOTE balance reduced by 50                       │
    │  Router: Holds 52.5 USDC in escrow                                     │
    │  Router: Records user→cleanWater→50 votes for current epoch            │
    └─────────────────────────────────────────────────────────────────────────┘

```
