// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title Registry Interface
 * @dev Interface for the EffortRegistry contract.
 */
interface IEffortRegistry {
    function isOperator(address account) external view returns (bool);
}
