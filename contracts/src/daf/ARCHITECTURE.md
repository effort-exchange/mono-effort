# Donor Advised Fund (DAF) Architecture

## Overview

A decentralized Donor Advised Fund system where users donate stablecoins, receive non-transferable receipt tokens (votes), and participate in two-phase voting:
1. **Distribution Voting**: Allocate funds to charity-specific vaults
2. **Grant Voting**: Approve grants proposed by charity beneficiaries

## System Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           PHASE 1: DONATION                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   User X (40 USDC) ──┐                                                      │
│   User Y (30 USDC) ──┼──► GlobalVault ──► Mint Non-Transferable Receipt    │
│   User Z (1000 USDC)─┘    (ERC4626)       Tokens (1:1 with USDC)           │
│                                                                             │
│   Result: X=40 votes, Y=30 votes, Z=1000 votes                             │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                    PHASE 2: DISTRIBUTION VOTING (Monthly)                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   User X: 20 votes → Clean Water, 20 votes → Cancer Research               │
│   User Y: 30 votes → Clean Water                                           │
│   User Z: 1000 votes → Clean Water                                         │
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────┐      │
│   │ Distribution Calculation:                                        │      │
│   │ - Clean Water: 20 + 30 + 1000 = 1050 votes (98.13%)             │      │
│   │ - Cancer Research: 20 votes (1.87%)                              │      │
│   │                                                                  │      │
│   │ Total Pool: 1070 USDC                                           │      │
│   │ - Clean Water receives: 1050 USDC                               │      │
│   │ - Cancer Research receives: 20 USDC                             │      │
│   └─────────────────────────────────────────────────────────────────┘      │
│                                                                             │
│   Result:                                                                   │
│   - GlobalVault receipt tokens BURNED                                      │
│   - Users receive CharityVault receipt tokens based on their votes         │
│   - X: 20 CleanWater votes, 20 CancerResearch votes                        │
│   - Y: 30 CleanWater votes                                                 │
│   - Z: 1000 CleanWater votes                                               │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                       PHASE 3: GRANT VOTING                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   Beneficiary proposes: "Buy 600 blankets for $500"                        │
│                                                                             │
│   Users vote with their CharityVault receipt tokens:                       │
│   - X votes YES with 20 CleanWater votes                                   │
│   - Y votes YES with 30 CleanWater votes                                   │
│   - Z votes YES with 1000 CleanWater votes                                 │
│                                                                             │
│   If approved (quorum reached):                                            │
│   → Funds released to beneficiary                                          │
│   → Grant receipt tokens burned                                            │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Contract Architecture

```
                    ┌──────────────────┐
                    │   DAFController  │
                    │   (Orchestrator) │
                    └────────┬─────────┘
                             │
           ┌─────────────────┼─────────────────┐
           │                 │                 │
           ▼                 ▼                 ▼
    ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐
    │ GlobalVault │  │CharityVault │  │ GrantProposal   │
    │  (ERC4626)  │  │  (ERC4626)  │  │    Manager      │
    └─────────────┘  └─────────────┘  └─────────────────┘
           │                 │
           ▼                 ▼
    ┌─────────────┐  ┌─────────────┐
    │ GlobalVote  │  │ CharityVote │
    │   Token     │  │   Token     │
    │(Non-Transfer│  │(Non-Transfer│
    └─────────────┘  └─────────────┘
```

## Contract Descriptions

### 1. NonTransferableERC20 (Base)
Base contract that prevents token transfers (soulbound).

### 2. GlobalVault (ERC4626)
- Accepts USDC deposits
- Mints 1:1 non-transferable receipt tokens (GlobalVoteToken)
- Tracks deposit epochs (monthly periods)
- Manages distribution phases

### 3. CharityVault (ERC4626)
- Receives USDC from GlobalVault during distribution
- Mints non-transferable charity-specific receipt tokens (CharityVoteToken)
- Managed by a beneficiary address
- Holds funds for grant proposals

### 4. DAFController
- Orchestrates the entire system
- Manages distribution periods (epochs)
- Handles vote collection and fund distribution
- Creates and manages CharityVaults

### 5. GrantProposal
- Beneficiaries create grant proposals
- Users vote with CharityVoteTokens
- Executes fund release when approved

## Data Structures

```solidity
// Distribution Vote
struct DistributionVote {
    uint256 epoch;
    mapping(address => uint256) charityVotes; // charity vault => vote amount
    uint256 totalVotes;
}

// Grant Proposal
struct Proposal {
    uint256 id;
    address charityVault;
    address beneficiary;
    uint256 amount;
    string description;
    uint256 votesFor;
    uint256 votesAgainst;
    uint256 deadline;
    ProposalState state;
}

enum ProposalState {
    Pending,
    Active,
    Succeeded,
    Defeated,
    Executed,
    Cancelled
}
```

## Key Functions

### GlobalVault
- `deposit(uint256 assets)` - Deposit USDC, receive GlobalVoteTokens
- `getVotingPower(address user)` - Get user's current voting power

### DAFController
- `createCharityVault(string name, address beneficiary)` - Admin creates charity
- `submitDistributionVote(CharityAllocation[] allocations)` - User votes
- `executeDistribution()` - End epoch, distribute funds
- `getCurrentEpoch()` - Get current monthly epoch

### CharityVault
- `proposeGrant(uint256 amount, string description)` - Beneficiary proposes
- `voteOnGrant(uint256 proposalId, bool support)` - Users vote
- `executeGrant(uint256 proposalId)` - Execute approved grant

## Epoch Management

```
Month 1: Users donate → Accumulate in GlobalVault
Month 1 End: Distribution voting opens
         → Users allocate votes to charities
         → Admin calls executeDistribution()
         → Funds move to CharityVaults
         → Users receive CharityVoteTokens

Month 2+: Grant voting in CharityVaults
         → Beneficiaries propose grants
         → Users vote with CharityVoteTokens
         → Approved grants execute
```

## Security Considerations

1. **Non-Transferable Tokens**: Prevents vote buying/selling
2. **Epoch-based Voting**: Clear periods prevent manipulation
3. **Access Control**: Only beneficiaries can propose grants
4. **Quorum Requirements**: Minimum participation for grant approval
5. **Time Locks**: Voting periods with deadlines

## Gas Considerations

Per requirements, gas optimization is not prioritized:
- Big loops are acceptable
- Focus on correctness and simplicity
- Minimal user interaction (donate + vote)
