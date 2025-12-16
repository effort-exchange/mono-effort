// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/**
 * @title CharityVault
 * @notice Charity-specific vault that holds funds and manages grant proposals
 * @dev Users receive non-transferable vote tokens when funds are distributed here
 *
 * Flow:
 * 1. DAFController distributes funds here and mints vote tokens to users
 * 2. Beneficiary proposes grants
 * 3. Users vote on grants with their vote tokens
 * 4. Approved grants are executed, sending funds to beneficiary
 */
contract CharityVault is Initializable, ERC20Upgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /// @notice Error thrown when attempting to transfer tokens
    error TokenNonTransferable();

    /// @notice Error thrown when caller is not the controller
    error OnlyController();

    /// @notice Error thrown when caller is not the beneficiary
    error OnlyBeneficiary();

    /// @notice Error thrown when proposal doesn't exist
    error ProposalNotFound(uint256 proposalId);

    /// @notice Error thrown when proposal is not in correct state
    error InvalidProposalState(uint256 proposalId, ProposalState current, ProposalState expected);

    /// @notice Error thrown when voting period has ended
    error VotingPeriodEnded(uint256 proposalId);

    /// @notice Error thrown when voting period hasn't ended
    error VotingPeriodNotEnded(uint256 proposalId);

    /// @notice Error thrown when user has already voted
    error AlreadyVoted(uint256 proposalId, address user);

    /// @notice Error thrown when user has no voting power
    error NoVotingPower(address user);

    /// @notice Error thrown when grant amount exceeds vault balance
    error InsufficientFunds(uint256 requested, uint256 available);

    /// @notice Error thrown when quorum not reached
    error QuorumNotReached(uint256 proposalId, uint256 votes, uint256 required);

    /// @notice Proposal states
    enum ProposalState {
        Pending,    // Created, waiting for voting to start
        Active,     // Voting in progress
        Succeeded,  // Voting ended, passed
        Defeated,   // Voting ended, failed
        Executed,   // Grant executed
        Cancelled   // Cancelled by beneficiary
    }

    /// @notice Grant proposal structure
    struct Proposal {
        uint256 id;
        address proposer;
        uint256 amount;
        string description;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 startTime;
        uint256 endTime;
        ProposalState state;
        mapping(address => bool) hasVoted;
        mapping(address => uint256) voteAmount;
    }

    /// @notice The underlying asset (USDC)
    IERC20 public asset;

    /// @notice The DAFController contract address
    address public controller;

    /// @notice The beneficiary address (can propose grants)
    address public beneficiary;

    /// @notice Charity name/description
    string public charityName;

    /// @notice Proposal counter
    uint256 public proposalCount;

    /// @notice Mapping of proposal ID to proposal
    mapping(uint256 => Proposal) public proposals;

    /// @notice Voting period duration (default 7 days)
    uint256 public votingPeriod;

    /// @notice Quorum percentage (default 10% = 1000 basis points)
    uint256 public quorumBps;

    /// @notice Approval threshold (default 50% = 5000 basis points)
    uint256 public approvalThresholdBps;

    /// @notice Total votes ever minted (for quorum calculation)
    uint256 public totalVotesMinted;

    // Events
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        uint256 amount,
        string description,
        uint256 startTime,
        uint256 endTime
    );
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId, uint256 amount);
    event ProposalCancelled(uint256 indexed proposalId);
    event VotesMinted(address indexed user, uint256 amount);
    event BeneficiaryUpdated(address indexed oldBeneficiary, address indexed newBeneficiary);

    /// @dev Modifier to restrict functions to controller only
    modifier onlyController() {
        if (msg.sender != controller) revert OnlyController();
        _;
    }

    /// @dev Modifier to restrict functions to beneficiary only
    modifier onlyBeneficiary() {
        if (msg.sender != beneficiary) revert OnlyBeneficiary();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the CharityVault
     * @param asset_ The underlying asset (USDC)
     * @param beneficiary_ The beneficiary address
     * @param charityName_ Name of the charity
     * @param name_ Token name for vote tokens
     * @param symbol_ Token symbol for vote tokens
     * @param controller_ The DAFController address
     */
    function initialize(
        IERC20 asset_,
        address beneficiary_,
        string memory charityName_,
        string memory name_,
        string memory symbol_,
        address controller_
    ) public initializer {
        __ERC20_init(name_, symbol_);
        __ReentrancyGuard_init();

        asset = asset_;
        beneficiary = beneficiary_;
        charityName = charityName_;
        controller = controller_;

        // Default voting parameters
        votingPeriod = 7 days;
        quorumBps = 1000; // 10%
        approvalThresholdBps = 5000; // 50%
    }

    /**
     * @notice Mint vote tokens to a user (called by controller during distribution)
     * @param user Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mintVotes(address user, uint256 amount) external onlyController {
        _mint(user, amount);
        totalVotesMinted += amount;
        emit VotesMinted(user, amount);
    }

    /**
     * @notice Receive assets from GlobalVault (called by controller)
     * @dev Assets are transferred directly, this just emits an event
     */
    function receiveAssets() external onlyController {
        // Assets are transferred directly via SafeERC20
        // This function exists for event emission if needed
    }

    /**
     * @notice Get user's voting power
     * @param user Address to check
     * @return Voting power
     */
    function getVotingPower(address user) external view returns (uint256) {
        return balanceOf(user);
    }

    /**
     * @notice Get available funds in the vault
     * @return Available balance
     */
    function availableFunds() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    // ============ Grant Proposal Functions ============

    /**
     * @notice Create a new grant proposal (beneficiary only)
     * @param amount Amount of funds requested
     * @param description Description of the grant
     * @return proposalId The ID of the created proposal
     */
    function proposeGrant(
        uint256 amount,
        string calldata description
    ) external onlyBeneficiary returns (uint256 proposalId) {
        if (amount > availableFunds()) {
            revert InsufficientFunds(amount, availableFunds());
        }

        proposalId = ++proposalCount;
        Proposal storage proposal = proposals[proposalId];

        proposal.id = proposalId;
        proposal.proposer = msg.sender;
        proposal.amount = amount;
        proposal.description = description;
        proposal.startTime = block.timestamp;
        proposal.endTime = block.timestamp + votingPeriod;
        proposal.state = ProposalState.Active;

        emit ProposalCreated(
            proposalId,
            msg.sender,
            amount,
            description,
            proposal.startTime,
            proposal.endTime
        );
    }

    /**
     * @notice Vote on a grant proposal
     * @param proposalId The proposal to vote on
     * @param support True for yes, false for no
     */
    function vote(uint256 proposalId, bool support) external nonReentrant {
        Proposal storage proposal = proposals[proposalId];

        if (proposal.id == 0) revert ProposalNotFound(proposalId);
        if (proposal.state != ProposalState.Active) {
            revert InvalidProposalState(proposalId, proposal.state, ProposalState.Active);
        }
        if (block.timestamp > proposal.endTime) {
            revert VotingPeriodEnded(proposalId);
        }
        if (proposal.hasVoted[msg.sender]) {
            revert AlreadyVoted(proposalId, msg.sender);
        }

        uint256 weight = balanceOf(msg.sender);
        if (weight == 0) revert NoVotingPower(msg.sender);

        proposal.hasVoted[msg.sender] = true;
        proposal.voteAmount[msg.sender] = weight;

        if (support) {
            proposal.votesFor += weight;
        } else {
            proposal.votesAgainst += weight;
        }

        emit VoteCast(proposalId, msg.sender, support, weight);
    }

    /**
     * @notice Finalize a proposal after voting period ends
     * @param proposalId The proposal to finalize
     */
    function finalizeProposal(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];

        if (proposal.id == 0) revert ProposalNotFound(proposalId);
        if (proposal.state != ProposalState.Active) {
            revert InvalidProposalState(proposalId, proposal.state, ProposalState.Active);
        }
        if (block.timestamp <= proposal.endTime) {
            revert VotingPeriodNotEnded(proposalId);
        }

        uint256 totalVotes = proposal.votesFor + proposal.votesAgainst;
        uint256 quorumRequired = (totalVotesMinted * quorumBps) / 10000;

        // Check quorum
        if (totalVotes < quorumRequired) {
            proposal.state = ProposalState.Defeated;
            return;
        }

        // Check approval threshold
        uint256 approvalRequired = (totalVotes * approvalThresholdBps) / 10000;
        if (proposal.votesFor >= approvalRequired) {
            proposal.state = ProposalState.Succeeded;
        } else {
            proposal.state = ProposalState.Defeated;
        }
    }

    /**
     * @notice Execute an approved grant proposal
     * @param proposalId The proposal to execute
     */
    function executeGrant(uint256 proposalId) external nonReentrant {
        Proposal storage proposal = proposals[proposalId];

        if (proposal.id == 0) revert ProposalNotFound(proposalId);
        if (proposal.state != ProposalState.Succeeded) {
            revert InvalidProposalState(proposalId, proposal.state, ProposalState.Succeeded);
        }
        if (proposal.amount > availableFunds()) {
            revert InsufficientFunds(proposal.amount, availableFunds());
        }

        proposal.state = ProposalState.Executed;
        asset.safeTransfer(beneficiary, proposal.amount);

        emit ProposalExecuted(proposalId, proposal.amount);
    }

    /**
     * @notice Cancel a proposal (beneficiary only)
     * @param proposalId The proposal to cancel
     */
    function cancelProposal(uint256 proposalId) external onlyBeneficiary {
        Proposal storage proposal = proposals[proposalId];

        if (proposal.id == 0) revert ProposalNotFound(proposalId);
        if (proposal.state == ProposalState.Executed) {
            revert InvalidProposalState(proposalId, proposal.state, ProposalState.Active);
        }

        proposal.state = ProposalState.Cancelled;
        emit ProposalCancelled(proposalId);
    }

    /**
     * @notice Update beneficiary address (beneficiary only)
     * @param newBeneficiary New beneficiary address
     */
    function updateBeneficiary(address newBeneficiary) external onlyBeneficiary {
        require(newBeneficiary != address(0), "Invalid beneficiary");
        address oldBeneficiary = beneficiary;
        beneficiary = newBeneficiary;
        emit BeneficiaryUpdated(oldBeneficiary, newBeneficiary);
    }

    // ============ View Functions ============

    /**
     * @notice Get proposal details
     * @param proposalId The proposal ID
     * @return id Proposal ID
     * @return proposer Proposer address
     * @return amount Requested amount
     * @return description Proposal description
     * @return votesFor Votes in favor
     * @return votesAgainst Votes against
     * @return startTime Voting start time
     * @return endTime Voting end time
     * @return state Current state
     */
    function getProposal(uint256 proposalId) external view returns (
        uint256 id,
        address proposer,
        uint256 amount,
        string memory description,
        uint256 votesFor,
        uint256 votesAgainst,
        uint256 startTime,
        uint256 endTime,
        ProposalState state
    ) {
        Proposal storage proposal = proposals[proposalId];
        return (
            proposal.id,
            proposal.proposer,
            proposal.amount,
            proposal.description,
            proposal.votesFor,
            proposal.votesAgainst,
            proposal.startTime,
            proposal.endTime,
            proposal.state
        );
    }

    /**
     * @notice Check if a user has voted on a proposal
     * @param proposalId The proposal ID
     * @param user The user address
     * @return True if user has voted
     */
    function hasVoted(uint256 proposalId, address user) external view returns (bool) {
        return proposals[proposalId].hasVoted[user];
    }

    /**
     * @notice Get user's vote amount on a proposal
     * @param proposalId The proposal ID
     * @param user The user address
     * @return Vote amount (0 if not voted)
     */
    function getVoteAmount(uint256 proposalId, address user) external view returns (uint256) {
        return proposals[proposalId].voteAmount[user];
    }

    // ============ Non-Transferable Overrides ============

    /**
     * @dev Override transfer to prevent transfers (soulbound)
     */
    function transfer(address, uint256) public pure override returns (bool) {
        revert TokenNonTransferable();
    }

    /**
     * @dev Override transferFrom to prevent transfers (soulbound)
     */
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert TokenNonTransferable();
    }

    /**
     * @dev Override approve to prevent approvals
     */
    function approve(address, uint256) public pure override returns (bool) {
        revert TokenNonTransferable();
    }
}
