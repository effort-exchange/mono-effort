// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title NonTransferableERC20
 * @notice Base contract for soulbound (non-transferable) ERC20 tokens
 * @dev Overrides transfer functions to prevent token transfers
 * Only minting and burning are allowed
 */
abstract contract NonTransferableERC20 is Initializable, ERC20Upgradeable {
    /// @notice Error thrown when attempting to transfer tokens
    error TokenNonTransferable();

    /**
     * @dev Initializes the non-transferable token
     * @param name_ Token name
     * @param symbol_ Token symbol
     */
    function __NonTransferableERC20_init(string memory name_, string memory symbol_) internal onlyInitializing {
        __ERC20_init(name_, symbol_);
    }

    /**
     * @dev Override transfer to prevent transfers
     * @notice This function always reverts
     */
    function transfer(address, uint256) public pure override returns (bool) {
        revert TokenNonTransferable();
    }

    /**
     * @dev Override transferFrom to prevent transfers
     * @notice This function always reverts
     */
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert TokenNonTransferable();
    }

    /**
     * @dev Override approve to prevent approvals (no point since transfers are blocked)
     * @notice This function always reverts
     */
    function approve(address, uint256) public pure override returns (bool) {
        revert TokenNonTransferable();
    }

    /**
     * @dev Internal mint function - can only be called by derived contracts
     * @param account Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function _mintVotes(address account, uint256 amount) internal {
        _mint(account, amount);
    }

    /**
     * @dev Internal burn function - can only be called by derived contracts
     * @param account Address to burn tokens from
     * @param amount Amount of tokens to burn
     */
    function _burnVotes(address account, uint256 amount) internal {
        _burn(account, amount);
    }
}
