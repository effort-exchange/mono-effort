// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title Registry Interface
 * @dev Interface for the EffortRegistry contract.
 */
interface IEffortGlobalVault {

    error TransferNotAllowed();
    error RouterNotSet();
    error InvalidCharityVault();
    error InsufficientVotes();
    error ZeroAmount();
    error WithdrawDisabled();

    /// @notice Emitted when a user allocates votes to a charity
    event VotesAllocated(
        address indexed user,
        address indexed charityVault,
        uint256 voteAmount,
        uint256 usdcAmount,
        uint256 epoch
    );

}
