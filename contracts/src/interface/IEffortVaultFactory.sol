// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {EffortVault} from "../EffortVault.sol";

/**
 * @title Vault Factory Interface
 * @dev Interface for the EffortVaultFactory contract.
 */
interface IEffortVaultFactory {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev The account is not an operator.
     */
    error NotOperator(address account);

    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice For operator (the caller) to create a new EffortVault instance using the Beacon proxy pattern.
     * The IERC20Metadata is used to initialize the vault with its name and symbol prefixed.
     * This self-serve function allows operators to create new vaults without needing to go through the owner.
     * For example an operator can create a vault for a new token that is IERC20Metadata compliant.
     * Given the {ERC20.name()} is Token and {ERC20.symbol()} is TKN,
     * the vault will be initialized with the name "Restaked {name} {ERC20.name()}" and symbol "efxAV.{symbol}.{ERC20.symbol()}".
     *
     * We recommend operators to use a unique infix name and symbol to avoid confusion with other vaults.
     *
     * @param asset The ERC20Metadata asset to be used in the vault.
     * @param name The infix name of the tokenized vault token. (e.g. "{name} Wrapped BTC" )
     * @param symbol The infix symbol of the tokenized vault token. (e.g. "efxAV.{symbol}.WBTC" )
     * @return The newly created EffortVault instance.
     */
    function create(IERC20Metadata asset, string calldata name, string calldata symbol)
        external
        returns (EffortVault);
}
