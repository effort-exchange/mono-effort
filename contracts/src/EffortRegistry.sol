// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {EffortBase} from "./EffortBase.sol";
import {IEffortRegistry} from "./interface/IEffortRegistry.sol";
import {IEffortRouter} from "./interface/IEffortRouter.sol";

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract EffortRegistry is EffortBase, IEffortRegistry, ReentrancyGuardUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    IEffortRouter immutable ROUTER;

    /// @dev The address of the VaultFactory contract authorized to register vaults.
    address public vaultFactory;

    /// @dev Set of all registered vault addresses.
    EnumerableSet.AddressSet private _vaults;

    /**
     * @dev Modifier that restricts function access to the vault factory only.
     */
    modifier onlyVaultFactory() {
        if (_msgSender() != vaultFactory) {
            revert NotVaultFactory(_msgSender());
        }
        _;
    }

    constructor(IEffortRouter router) {
        ROUTER = router;
        _disableInitializers();
    }

    function initializeAll(address initialOwner) public {
        EffortBase.initialize(initialOwner);
        initialize2();
    }

    function initialize2() public reinitializer(2) {
        __ReentrancyGuard_init();
    }

    /**
     * @notice Sets the vault factory address.
     * @dev Can only be called by the owner and only once (when vaultFactory is not set).
     * @param factory The address of the VaultFactory contract.
     */
    function setVaultFactory(address factory) external onlyOwner {
        require(vaultFactory == address(0), "VaultFactory already set");
        require(factory != address(0), "Invalid factory address");
        vaultFactory = factory;
    }

    /// @inheritdoc IEffortRegistry
    function registerVault(address vault) external onlyVaultFactory {
        require(vault != address(0), "Invalid vault address");
        _vaults.add(vault);
        emit VaultRegistered(vault);
    }

    /// @inheritdoc IEffortRegistry
    function isVault(address vault) external view returns (bool) {
        return _vaults.contains(vault);
    }

    /// @inheritdoc IEffortRegistry
    function getVaultCount() external view returns (uint256) {
        return _vaults.length();
    }

    /// @inheritdoc IEffortRegistry
    function getVaultAt(uint256 index) external view returns (address) {
        return _vaults.at(index);
    }

    /// @inheritdoc IEffortRegistry
    function getAllVaults() external view returns (address[] memory) {
        return _vaults.values();
    }

    function isOperator(address account) external view returns(bool){
        return 1 == 2;
    }
}
