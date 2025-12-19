// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {EffortBase} from "./EffortBase.sol";
import {IEffortRegistry} from "./interface/IEffortRegistry.sol";
import {IEffortRouter} from "./interface/IEffortRouter.sol";

import {IEffortGlobalVault} from "./interface/IEffortGlobalVault.sol";
import {EffortGlobalVault} from "./EffortGlobalVault.sol";

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract EffortRouter is EffortBase, IEffortRouter, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;


    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    IEffortRegistry immutable REGISTRY;
    EffortGlobalVault immutable GLOBAL_VAULT;

    constructor(IEffortRegistry registry_, EffortGlobalVault global_vault_) {
        REGISTRY = registry_;
        GLOBAL_VAULT = global_vault_;
        _disableInitializers();
    }

    function initializeAll(address initialOwner) public {
        EffortBase.initialize(initialOwner);
        initialize2();
    }

    function initialize2() public reinitializer(2) {
        __ReentrancyGuard_init();
        epochStartTime = block.timestamp;
        currentEpoch = 1;
        epochDuration = 30 days;
    }

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Current epoch number (starts at 1)
    uint256 public currentEpoch;

    /// @notice Timestamp when current epoch started
    uint256 public epochStartTime;

    /// @notice Duration of each epoch (default 30 days)
    uint256 public epochDuration;

    /// @notice Allocations: epoch => user => charity => Allocation
    mapping(uint256 => mapping(address => mapping(address => Allocation))) public allocations;

    /// @notice Track if user has allocated to a charity this epoch (for array management)
    mapping(uint256 => mapping(address => mapping(address => bool))) public hasAllocatedToCharity;

    /// @notice Charity summary: epoch => charity => CharitySummary
    mapping(uint256 => mapping(address => CharitySummary)) internal _charitySummaries;

    /// @notice Track which charities received allocations in each epoch
    mapping(uint256 => address[]) public epochCharities;

    /// @notice Track if a charity has received allocation this epoch (for array management)
    mapping(uint256 => mapping(address => bool)) public hasCharityReceivedAllocation;

    /// @notice Track which users allocated in each epoch
    mapping(uint256 => address[]) public epochUsers;

    /// @notice Track if user has allocated this epoch (for array management)
    mapping(uint256 => mapping(address => bool)) public hasAllocatedInEpoch;

    /// @notice Track which charities a user allocated to in an epoch
    mapping(uint256 => mapping(address => address[])) public userCharities;

    /// @notice Total assets escrowed for each epoch
    mapping(uint256 => uint256) public epochTotalAssets;

    /// @notice Track if an epoch has been finalized
    mapping(uint256 => bool) public epochFinalized;


    /**
     * @notice Update epoch duration (affects next epoch)
     * @param _epochDuration New epoch duration in seconds
     */
    function setEpochDuration(uint256 _epochDuration) external onlyOwner {
        epochDuration = _epochDuration;
    }

    /*//////////////////////////////////////////////////////////////
                           CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Record a vote allocation from GlobalVault
     * @dev Only callable by GlobalVault. Assets should already be transferred.
     * @param user The user who allocated votes
     * @param charityVault The charity vault allocated to
     * @param voteAmount The number of votes allocated
     * @param assetAmount The asset value of the votes
     */
    function recordAllocation(
        address user,
        address charityVault,
        uint256 voteAmount,
        uint256 assetAmount
    ) external override {
        if (_msgSender() != address(GLOBAL_VAULT)) revert OnlyGlobalVault();
        if (!REGISTRY.isCharityVault(charityVault)) revert InvalidCharityVault();

        uint256 epoch = currentEpoch;

        // Accumulate user's allocation to this charity
        Allocation storage userAlloc = allocations[epoch][user][charityVault];
        userAlloc.votes += voteAmount;
        userAlloc.assets += assetAmount;

        // Update charity summary
        CharitySummary storage summary = _charitySummaries[epoch][charityVault];
        summary.totalVotes += voteAmount;
        summary.totalAssets += assetAmount;

        // Track user in charity's user list (avoid duplicates)
        if (!hasAllocatedToCharity[epoch][user][charityVault]) {
            hasAllocatedToCharity[epoch][user][charityVault] = true;
            summary.users.push(user);
            userCharities[epoch][user].push(charityVault);
        }

        // Track charity in epoch's charity list (avoid duplicates)
        if (!hasCharityReceivedAllocation[epoch][charityVault]) {
            hasCharityReceivedAllocation[epoch][charityVault] = true;
            epochCharities[epoch].push(charityVault);
        }

        // Track user in epoch's user list (avoid duplicates)
        if (!hasAllocatedInEpoch[epoch][user]) {
            hasAllocatedInEpoch[epoch][user] = true;
            epochUsers[epoch].push(user);
        }

        // Update epoch total
        epochTotalAssets[epoch] += assetAmount;

        emit AllocationRecorded(epoch, user, charityVault, voteAmount, assetAmount);
    }

    /**
     * @notice Finalize the current epoch and distribute funds to charity vaults
     * @dev Can be called by anyone after the epoch ends
     *      Uses ERC4626 deposit() to transfer assets and mint grant tokens
     */
    function finalizeEpoch() external override {
        uint256 epoch = currentEpoch;
        
        if (block.timestamp < epochStartTime + epochDuration) revert EpochNotEnded();
        if (epochFinalized[epoch]) revert EpochAlreadyFinalized();

        epochFinalized[epoch] = true;

        IERC20 assetToken = IERC20(EffortGlobalVault(GLOBAL_VAULT).asset());
        uint256 totalDistributed = 0;

        // Get charities that received allocations this epoch
        address[] storage charitiesWithAllocations = epochCharities[epoch];

        // Distribute only to charities that received allocations
        for (uint256 i = 0; i < charitiesWithAllocations.length; i++) {
            address charityVault = charitiesWithAllocations[i];
            CharitySummary storage summary = _charitySummaries[epoch][charityVault];

            if (summary.totalAssets > 0) {
                // Approve charity vault to pull assets
                assetToken.approve(charityVault, summary.totalAssets);

                // Deposit for each user using ERC4626 deposit()
                // This transfers assets from Router and mints shares to user
                uint256 userCount = summary.users.length;
                for (uint256 j = 0; j < userCount; j++) {
                    address user = summary.users[j];
                    uint256 userAssets = allocations[epoch][user][charityVault].assets;
                    
                    if (userAssets > 0) {
                        // ERC4626 deposit: transfers assets from msg.sender (Router), mints shares to receiver (user)
                        IERC4626(charityVault).deposit(userAssets, user);
                    }
                }

                // Reset approval
                assetToken.approve(charityVault, 0);

                emit FundsDistributed(
                    epoch,
                    charityVault,
                    summary.totalAssets,
                    summary.totalVotes
                );

                totalDistributed += summary.totalAssets;
            }
        }

        // Start new epoch
        currentEpoch = epoch + 1;
        epochStartTime = block.timestamp;

        emit EpochFinalized(epoch, totalDistributed);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get allocation for a specific user and charity in an epoch
     * @param epoch The epoch number
     * @param user The user address
     * @param charityVault The charity vault address
     * @return votes The number of votes allocated
     * @return assets The asset value allocated
     */
    function getAllocation(
        uint256 epoch,
        address user,
        address charityVault
    ) external view override returns (uint256 votes, uint256 assets) {
        Allocation storage alloc = allocations[epoch][user][charityVault];
        return (alloc.votes, alloc.assets);
    }

    /**
     * @notice Get time remaining until epoch can be finalized
     * @return seconds until epoch end (0 if already ended)
     */
    function getTimeUntilEpochEnd() external view override returns (uint256) {
        uint256 epochEnd = epochStartTime + epochDuration;
        if (block.timestamp >= epochEnd) return 0;
        return epochEnd - block.timestamp;
    }

    /**
     * @notice Check if the current epoch can be finalized
     * @return True if epoch has ended and not yet finalized
     */
    function canFinalizeEpoch() external view override returns (bool) {
        return (
            block.timestamp >= epochStartTime + epochDuration &&
            !epochFinalized[currentEpoch]
        );
    }

    function getCurrentEpoch() external view returns (uint256) {
        return currentEpoch;
    }

}
