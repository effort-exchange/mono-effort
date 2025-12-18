// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {EffortBase} from "./EffortBase.sol";

import {EffortVault} from "./EffortVault.sol";

import {IEffortVaultFactory} from "./interface/IEffortVaultFactory.sol";

import {IEffortRegistry} from "./interface/IEffortRegistry.sol";
import {IEffortRouter} from "./interface/IEffortRouter.sol";

/**
 * @title Vault Factory Contract
 * @dev Factory contract for creating EffortVault instances.
 * This contract is responsible for deploying new vaults and managing their creation.
 * It inherits from EffortBase which provides basic functionality like initialization,
 * upgradeability, ownership, and pause/unpause functions.
 *
 * @custom:oz-upgrades-from src/EffortBase.sol:EffortBase
 */
contract EffortVaultFactory is EffortBase, IEffortVaultFactory {
    /**
     * @dev The address of the UpgradeableBeacon that points to the EffortVault implementation.
     * This is used when creating new vault instances via BeaconProxy.
     * @custom:oz-upgrades-unsafe-allow state-variable-immutable
     */
    address public immutable BEACON;

    /**
     * @dev Reference to the EffortRegistry contract used for operator verification.
     * This is used to check if an address is registered as an operator.
     * @custom:oz-upgrades-unsafe-allow state-variable-immutable
     */
    IEffortRegistry public immutable REGISTRY;

    /**
     * @dev Modifier that restricts function access to operators only.
     * Throws if called by any account that is not registered as an operator in the EffortRegistry.
     * Uses the _checkOperator function to verify the caller's operator status.
     */
    modifier onlyPartner() {
        _checkPartner(_msgSender());
        _;
    }

    /**
     * @dev Constructor for EffortVaultFactory.
     * Sets up the immutable beacon and registry references and disables initializers.
     *
     * @param beacon_ The address of the UpgradeableBeacon that points to the EffortVault implementation.
     * @param registry_ The address of the EffortRegistry contract used for operator verification.
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(address beacon_, IEffortRegistry registry_) {
        BEACON = beacon_;
        REGISTRY = registry_;
        _disableInitializers();
    }

    /**
     * @dev Checks if the given account is an operator.
     * Throws if the account is not registered as an operator in the EffortRegistry.
     *
     * @param account The address to check if it's an operator.
     */
    function _checkPartner(address account) internal view virtual {
        if (!REGISTRY.isPartner(account)) {
            revert NotOperator(account);
        }
    }

    /// @inheritdoc IEffortVaultFactory
    function create(IERC20Metadata asset, string calldata name, string calldata symbol)
        external
        override
        whenNotPaused
        onlyPartner
        returns (EffortVault)
    {
        address operator = _msgSender();
        string memory fullName = string(abi.encodePacked("Effort Charity Grant Voting Token", name, " ", asset.name()));
        string memory fullSymbol = string(abi.encodePacked("efxAV", symbol, ".", asset.symbol()));

        bytes memory data = abi.encodeCall(EffortVault.initialize, (asset, operator, fullName, fullSymbol));
        BeaconProxy proxy = new BeaconProxy(BEACON, data);
        REGISTRY.addCharityVault(address(proxy));
        return EffortVault(address(proxy));
    }
}
