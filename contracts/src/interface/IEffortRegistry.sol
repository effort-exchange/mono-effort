// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title Registry Interface
 * @dev Interface for the EffortRegistry contract.
 */
interface IEffortRegistry {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Emitted when a new vault is registered.
     * @param vault The address of the newly registered vault.
     */
    event VaultRegistered(address indexed vault);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev The caller is not the vault factory.
     */
    error NotVaultFactory(address caller);

    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function isOperator(address account) external view returns (bool);

    /**
     * @notice Registers a new vault address.
     * @dev Can only be called by the VaultFactory.
     * @param vault The address of the vault to register.
     */
    function registerVault(address vault) external;

    /**
     * @notice Checks if an address is a registered vault.
     * @param vault The address to check.
     * @return True if the address is a registered vault, false otherwise.
     */
    function isVault(address vault) external view returns (bool);

    /**
     * @notice Returns the total number of registered vaults.
     * @return The count of registered vaults.
     */
    function getVaultCount() external view returns (uint256);

    /**
     * @notice Returns the vault address at a specific index.
     * @param index The index of the vault to retrieve.
     * @return The vault address at the given index.
     */
    function getVaultAt(uint256 index) external view returns (address);

    /**
     * @notice Returns all registered vault addresses.
     * @return An array of all registered vault addresses.
     */
    function getAllVaults() external view returns (address[] memory);
}
