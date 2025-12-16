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

contract EffortVault is
    Initializable,
    ERC20Upgradeable,
    ERC4626Upgradeable,
    ERC165Upgradeable,
    ERC20PermitUpgradeable
{
    /// @notice The EffortRouter contract that manages pausing and whitelisting
    /// @dev This is an immutable reference to the router contract
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    EffortRouter public immutable ROUTER;

    /// @notice The EffortRegistry contract that manages operators and withdrawal delays
    /// @dev This is an immutable reference to the registry contract
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    EffortRegistry public immutable REGISTRY;

    address internal _delegated;

    /**
     * @dev Sets immutable references to the router and registry contracts
     * Disables initializers to prevent re-initialization
     * @param router_ The address of the EffortRouter contract
     * @param registry_ The address of the EffortRegistry contract
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(EffortRouter router_, EffortRegistry registry_) {
        ROUTER = router_;
        REGISTRY = registry_;
        _disableInitializers();
    }

    /**
     * @dev Initializes the EffortVault with the given parameters
     * This function is called by the EffortVaultFactory when creating a new EffortVault instance
     * Not to be called directly
     *
     * @param asset_ The address of the underlying asset (ERC20 token) that the vault will hold
     * @param delegated_ The address of the delegated operator for this vault
     * @param name_ The name of the vault, used for ERC20 token metadata
     * @param symbol_ The symbol of the vault, used for ERC20 token metadata
     */
    function initialize(IERC20 asset_, address delegated_, string memory name_, string memory symbol_)
        public
        initializer
    {
        require(delegated_ != address(0), "Delegated is not a valid account");

        __ERC20_init(name_, symbol_);
        __ERC4626_init(asset_);
        __ERC20Permit_init(name_);
        _delegated = delegated_;
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
        super._update(from, to, value);
    }
}
