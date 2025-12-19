// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {ERC20PermitUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {EffortRouter} from "./EffortRouter.sol";
import {EffortRegistry} from "./EffortRegistry.sol";
import {IEffortRouter} from "./interface/IEffortRouter.sol";
import {IEffortGlobalVault} from "./interface/IEffortGlobalVault.sol";
import {EffortBase} from "./EffortBase.sol";

contract EffortGlobalVault is
    Initializable,
    ERC20Upgradeable,
    ERC4626Upgradeable,
    ERC165Upgradeable,
    ERC20PermitUpgradeable,
    IEffortGlobalVault,
    EffortBase
{
    using SafeERC20 for IERC20;

    /// @notice The EffortRouter contract that manages pausing and whitelisting
    /// @dev This is an immutable reference to the ROUTER contract
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    EffortRouter public immutable ROUTER;

    /// @notice The EffortRegistry contract that manages operators and withdrawal delays
    /// @dev This is an immutable reference to the registry contract
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    EffortRegistry public immutable REGISTRY;


    /**
     * @dev Sets immutable references to the ROUTER and registry contracts
     * Disables initializers to prevent re-initialization
     * @param ROUTER_ The address of the EffortRouter contract
     * @param registry_ The address of the EffortRegistry contract
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(EffortRouter ROUTER_, EffortRegistry registry_) {
        ROUTER = ROUTER_;
        REGISTRY = registry_;
        _disableInitializers();
    }

    function initialize2(IERC20 asset_, string memory name_, string memory symbol_) public reinitializer(2) {
        __ERC20_init(name_, symbol_);
        __ERC4626_init(asset_);
        __ERC20Permit_init(name_);
    }

    /// @inheritdoc IERC20Metadata
    function decimals() public view override(ERC20Upgradeable, ERC4626Upgradeable) returns (uint8) {
        return ERC4626Upgradeable.decimals();
    }

    /**
     * @dev See {ERC20Upgradable-_update} with additional requirements from EffortRouter
     *
     * To update the balances of the EffortVault (and therefore mint/deposit/withdraw/redeem),
     * the following conditions must be met:
     *
     * - The contract must not be paused in the EffortRouter (whenNotPaused modifier)
     * - The contract must be whitelisted in the EffortRouter (whenWhitelisted modifier)
     *
     * @inheritdoc ERC20Upgradeable
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        if (
            from != address(0) &&
            to != address(0) &&
            to != address(ROUTER)
        ) {
            revert TransferNotAllowed();
        }
        super._update(from, to, value);
    }


    /*//////////////////////////////////////////////////////////////
                        DISABLED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Withdraw is disabled - users can only allocate to charities
     */
    function withdraw(
        uint256,
        address,
        address
    ) public pure override returns (uint256) {
        revert WithdrawDisabled();
    }

    /**
     * @notice Withdraw is disabled - users can only allocate to charities
     */
    function redeem(
        uint256,
        address,
        address
    ) public pure override returns (uint256) {
        revert WithdrawDisabled();
    }

    /**
     * @notice Allocate votes to a charity vault
     * @dev Burns gVOTE tokens and transfers corresponding USDC to Router
     * @param charityVault The charity vault to allocate to
     * @param voteAmount The number of votes to allocate
     */
    function allocateVotes(
        address charityVault,
        uint256 voteAmount
    ) external {
        address sender = _msgSender();
        if (address(ROUTER) == address(0)) revert RouterNotSet();
        if (voteAmount == 0) revert ZeroAmount();
        if (balanceOf(sender) < voteAmount) revert InsufficientVotes();
        if (!REGISTRY.isCharityVault(charityVault)) revert InvalidCharityVault();

        // Calculate USDC value of votes (uses ERC4626 standard math)
        uint256 underlyingAssetAmount = convertToAssets(voteAmount);

        // Burn user's vote tokens
        _burn(sender, voteAmount);

        // Transfer USDC to Router
        IERC20(asset()).safeTransfer(address(ROUTER), underlyingAssetAmount);

        // Record allocation in Router
        ROUTER.recordAllocation(
            sender,
            charityVault,
            voteAmount,
            underlyingAssetAmount
        );

        emit VotesAllocated(
            sender,
            charityVault,
            voteAmount,
            underlyingAssetAmount,
            ROUTER.getCurrentEpoch()
        );
    }

}
