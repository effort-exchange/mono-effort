// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title Router Interface
 * @dev Interface for the EffortRouter contract.
 */
interface IEffortRouter {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error OnlyGlobalVault();
    error EpochNotEnded();
    error EpochAlreadyFinalized();
    error CharityVaultAlreadyRegistered();
    error InvalidCharityVault();
    error ZeroAddress();
    error InvalidArrayLengths();

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Allocation data for a user to a specific charity in an epoch
    struct Allocation {
        uint256 votes; // Total votes allocated
        uint256 assets; // Total asset value (e.g., USDC)
    }

    /// @notice Summary data for a charity in an epoch
    struct CharitySummary {
        uint256 totalVotes;
        uint256 totalAssets;
        address[] users; // Users who allocated to this charity
    }

    /// @notice Emitted when an allocation is recorded
    event AllocationRecorded(
        uint256 indexed epoch,
        address indexed user,
        address indexed charityVault,
        uint256 voteAmount,
        uint256 usdcAmount
    );

    /// @notice Emitted when an epoch is finalized
    event EpochFinalized(uint256 indexed epoch, uint256 totalUSDCDistributed);

    /// @notice Emitted when funds are distributed to a charity vault
    event FundsDistributed(uint256 indexed epoch, address indexed charityVault, uint256 usdcAmount, uint256 totalVotes);

    /// @notice Emitted when a charity vault is registered
    event CharityVaultRegistered(address indexed charityVault);

    /// @notice Record a vote allocation from GlobalVault
    /// @param user The user who allocated votes
    /// @param charityVault The charity vault allocated to
    /// @param voteAmount The number of votes allocated
    /// @param usdcAmount The USDC value of the votes
    function recordAllocation(address user, address charityVault, uint256 voteAmount, uint256 usdcAmount) external;

    /// @notice Finalize the current epoch and distribute funds
    function finalizeEpoch() external;

    /// @notice Get allocation for a specific user and charity in an epoch
    function getAllocation(uint256 epoch, address user, address charityVault)
        external
        view
        returns (uint256 votes, uint256 usdc);

    /// @notice Get the current epoch number
    function getCurrentEpoch() external view returns (uint256);

    /// @notice Get time remaining until epoch can be finalized
    function getTimeUntilEpochEnd() external view returns (uint256);

    /// @notice Check if the current epoch can be finalized
    function canFinalizeEpoch() external view returns (bool);
}
