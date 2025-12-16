// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {GlobalVault} from "./GlobalVault.sol";
import {CharityVault} from "./CharityVault.sol";

/**
 * @title DAFController
 * @notice Main controller for the Donor Advised Fund system
 * @dev Orchestrates donations, distribution voting, and charity vault management
 *
 * System Flow:
 * 1. Admin creates charity vaults
 * 2. Users donate to GlobalVault, receiving non-transferable vote tokens
 * 3. Users submit distribution votes to allocate funds to charities
 * 4. At epoch end, admin executes distribution:
 *    - Burns users' GlobalVault tokens
 *    - Transfers funds to CharityVaults proportionally
 *    - Mints CharityVault tokens to users based on their votes
 * 5. Users vote on grants in CharityVaults
 */
contract DAFController is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /// @notice Error thrown when charity vault doesn't exist
    error CharityVaultNotFound(address vault);

    /// @notice Error thrown when charity vault already exists
    error CharityVaultAlreadyExists(string name);

    /// @notice Error thrown when distribution is not open
    error DistributionNotOpen();

    /// @notice Error thrown when distribution is already open
    error DistributionAlreadyOpen();

    /// @notice Error thrown when user has no votes
    error NoVotesToAllocate(address user);

    /// @notice Error thrown when vote allocation exceeds balance
    error VoteAllocationExceedsBalance(address user, uint256 allocated, uint256 balance);

    /// @notice Error thrown when user has already voted this epoch
    error AlreadyVotedThisEpoch(address user, uint256 epoch);

    /// @notice Error thrown when no votes were cast
    error NoVotesCast();

    /// @notice Error thrown when arrays length mismatch
    error ArrayLengthMismatch();

    /// @notice Structure for charity vault info
    struct CharityInfo {
        address vault;
        string name;
        address beneficiary;
        bool active;
    }

    /// @notice Structure for user's distribution vote
    struct DistributionVote {
        address[] charities;
        uint256[] amounts;
        uint256 totalAmount;
    }

    /// @notice The GlobalVault contract
    GlobalVault public globalVault;

    /// @notice The underlying asset (USDC)
    IERC20 public asset;

    /// @notice CharityVault implementation for cloning
    address public charityVaultImplementation;

    /// @notice Array of all charity vault addresses
    address[] public charityVaults;

    /// @notice Mapping of charity name to vault address
    mapping(string => address) public charityByName;

    /// @notice Mapping of vault address to charity info
    mapping(address => CharityInfo) public charityInfo;

    /// @notice Whether distribution voting is currently open
    bool public distributionOpen;

    /// @notice Current epoch
    uint256 public currentEpoch;

    /// @notice Mapping of user => epoch => distribution vote
    mapping(address => mapping(uint256 => DistributionVote)) internal userVotes;

    /// @notice Mapping of user => epoch => whether they've voted
    mapping(address => mapping(uint256 => bool)) public hasVotedInEpoch;

    /// @notice Array of users who voted in current epoch (for iteration)
    address[] internal currentEpochVoters;

    /// @notice Mapping to track if address is in currentEpochVoters
    mapping(address => bool) internal isCurrentEpochVoter;

    /// @notice Total votes allocated to each charity in current epoch
    mapping(address => uint256) public charityVoteTotal;

    /// @notice Total votes cast in current epoch
    uint256 public totalVotesCast;

    // Events
    event CharityVaultCreated(address indexed vault, string name, address indexed beneficiary);
    event CharityVaultDeactivated(address indexed vault);
    event DistributionVoteSubmitted(address indexed user, uint256 epoch, uint256 totalVotes);
    event DistributionOpened(uint256 epoch);
    event DistributionExecuted(uint256 epoch, uint256 totalDistributed, uint256 charitiesCount);
    event FundsDistributed(address indexed charity, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the DAFController
     * @param globalVault_ The GlobalVault contract address
     * @param charityVaultImpl_ The CharityVault implementation for cloning
     * @param owner_ Initial owner address
     */
    function initialize(
        GlobalVault globalVault_,
        address charityVaultImpl_,
        address owner_
    ) public initializer {
        __Ownable_init(owner_);
        __ReentrancyGuard_init();

        globalVault = globalVault_;
        asset = IERC20(globalVault_.asset());
        charityVaultImplementation = charityVaultImpl_;
        currentEpoch = 1;
    }

    // ============ Admin Functions ============

    /**
     * @notice Create a new charity vault
     * @param name Charity name (must be unique)
     * @param beneficiary Address that can propose grants
     * @return vault The created CharityVault address
     */
    function createCharityVault(
        string calldata name,
        address beneficiary
    ) external onlyOwner returns (address vault) {
        if (charityByName[name] != address(0)) {
            revert CharityVaultAlreadyExists(name);
        }

        // Clone the CharityVault implementation
        vault = Clones.clone(charityVaultImplementation);

        // Initialize the vault
        string memory tokenName = string(abi.encodePacked("DAF ", name, " Vote"));
        string memory tokenSymbol = string(abi.encodePacked("daf", name));

        CharityVault(vault).initialize(
            asset,
            beneficiary,
            name,
            tokenName,
            tokenSymbol,
            address(this)
        );

        // Store charity info
        charityVaults.push(vault);
        charityByName[name] = vault;
        charityInfo[vault] = CharityInfo({
            vault: vault,
            name: name,
            beneficiary: beneficiary,
            active: true
        });

        emit CharityVaultCreated(vault, name, beneficiary);
    }

    /**
     * @notice Deactivate a charity vault (no new distributions)
     * @param vault The charity vault address
     */
    function deactivateCharityVault(address vault) external onlyOwner {
        if (charityInfo[vault].vault == address(0)) {
            revert CharityVaultNotFound(vault);
        }
        charityInfo[vault].active = false;
        emit CharityVaultDeactivated(vault);
    }

    /**
     * @notice Open distribution voting for current epoch
     */
    function openDistribution() external onlyOwner {
        if (distributionOpen) revert DistributionAlreadyOpen();
        distributionOpen = true;
        emit DistributionOpened(currentEpoch);
    }

    /**
     * @notice Execute distribution after voting period
     * @dev Transfers funds to charity vaults and mints vote tokens
     */
    function executeDistribution() external onlyOwner nonReentrant {
        if (!distributionOpen) revert DistributionNotOpen();
        if (totalVotesCast == 0) revert NoVotesCast();

        uint256 totalAssets = globalVault.totalAssetsForDistribution();

        // Distribute funds to each charity based on votes
        uint256 charitiesDistributed = 0;
        for (uint256 i = 0; i < charityVaults.length; i++) {
            address charity = charityVaults[i];
            uint256 votes = charityVoteTotal[charity];

            if (votes > 0 && charityInfo[charity].active) {
                // Calculate proportional share
                uint256 share = (totalAssets * votes) / totalVotesCast;

                if (share > 0) {
                    // Transfer from GlobalVault to CharityVault
                    globalVault.transferToCharity(charity, share);
                    charitiesDistributed++;

                    emit FundsDistributed(charity, share);
                }
            }
        }

        // Mint charity vault tokens to users and burn their global tokens
        for (uint256 i = 0; i < currentEpochVoters.length; i++) {
            address user = currentEpochVoters[i];
            DistributionVote storage userVote = userVotes[user][currentEpoch];

            // Burn user's global vault tokens
            globalVault.burnVotes(user, userVote.totalAmount);

            // Mint charity vault tokens for each allocation
            for (uint256 j = 0; j < userVote.charities.length; j++) {
                address charity = userVote.charities[j];
                uint256 amount = userVote.amounts[j];

                if (amount > 0 && charityInfo[charity].active) {
                    CharityVault(charity).mintVotes(user, amount);
                }
            }
        }

        emit DistributionExecuted(currentEpoch, totalAssets, charitiesDistributed);

        // Reset state for next epoch
        _resetEpochState();
        globalVault.advanceEpoch();
        currentEpoch++;
        distributionOpen = false;
    }

    // ============ User Functions ============

    /**
     * @notice Submit distribution vote
     * @param charities Array of charity vault addresses
     * @param amounts Array of vote amounts for each charity
     */
    function submitDistributionVote(
        address[] calldata charities,
        uint256[] calldata amounts
    ) external nonReentrant {
        if (!distributionOpen) revert DistributionNotOpen();
        if (charities.length != amounts.length) revert ArrayLengthMismatch();
        if (hasVotedInEpoch[msg.sender][currentEpoch]) {
            revert AlreadyVotedThisEpoch(msg.sender, currentEpoch);
        }

        uint256 userBalance = globalVault.getVotingPower(msg.sender);
        if (userBalance == 0) revert NoVotesToAllocate(msg.sender);

        // Calculate total allocation
        uint256 totalAllocation = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAllocation += amounts[i];

            // Validate charity exists
            if (charityInfo[charities[i]].vault == address(0)) {
                revert CharityVaultNotFound(charities[i]);
            }
        }

        // Ensure user isn't allocating more than they have
        if (totalAllocation > userBalance) {
            revert VoteAllocationExceedsBalance(msg.sender, totalAllocation, userBalance);
        }

        // Store user's vote
        DistributionVote storage vote = userVotes[msg.sender][currentEpoch];
        vote.charities = charities;
        vote.amounts = amounts;
        vote.totalAmount = totalAllocation;

        hasVotedInEpoch[msg.sender][currentEpoch] = true;

        // Track voter for iteration
        if (!isCurrentEpochVoter[msg.sender]) {
            currentEpochVoters.push(msg.sender);
            isCurrentEpochVoter[msg.sender] = true;
        }

        // Update charity vote totals
        for (uint256 i = 0; i < charities.length; i++) {
            charityVoteTotal[charities[i]] += amounts[i];
        }
        totalVotesCast += totalAllocation;

        emit DistributionVoteSubmitted(msg.sender, currentEpoch, totalAllocation);
    }

    // ============ View Functions ============

    /**
     * @notice Get all charity vaults
     * @return Array of charity vault addresses
     */
    function getAllCharityVaults() external view returns (address[] memory) {
        return charityVaults;
    }

    /**
     * @notice Get number of charity vaults
     * @return Count of charity vaults
     */
    function getCharityVaultCount() external view returns (uint256) {
        return charityVaults.length;
    }

    /**
     * @notice Get user's distribution vote for an epoch
     * @param user User address
     * @param epoch Epoch number
     * @return charities Array of charity addresses
     * @return amounts Array of vote amounts
     * @return totalAmount Total votes allocated
     */
    function getUserVote(
        address user,
        uint256 epoch
    ) external view returns (
        address[] memory charities,
        uint256[] memory amounts,
        uint256 totalAmount
    ) {
        DistributionVote storage vote = userVotes[user][epoch];
        return (vote.charities, vote.amounts, vote.totalAmount);
    }

    /**
     * @notice Get active charity vaults
     * @return Array of active charity vault addresses
     */
    function getActiveCharityVaults() external view returns (address[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < charityVaults.length; i++) {
            if (charityInfo[charityVaults[i]].active) {
                activeCount++;
            }
        }

        address[] memory active = new address[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < charityVaults.length; i++) {
            if (charityInfo[charityVaults[i]].active) {
                active[index++] = charityVaults[i];
            }
        }

        return active;
    }

    /**
     * @notice Get current epoch voters count
     * @return Number of voters in current epoch
     */
    function getCurrentEpochVotersCount() external view returns (uint256) {
        return currentEpochVoters.length;
    }

    // ============ Internal Functions ============

    /**
     * @dev Reset state for next epoch
     */
    function _resetEpochState() internal {
        // Reset charity vote totals
        for (uint256 i = 0; i < charityVaults.length; i++) {
            charityVoteTotal[charityVaults[i]] = 0;
        }

        // Reset voter tracking
        for (uint256 i = 0; i < currentEpochVoters.length; i++) {
            isCurrentEpochVoter[currentEpochVoters[i]] = false;
        }
        delete currentEpochVoters;

        totalVotesCast = 0;
    }
}
