// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title Registry Interface
 * @dev Interface for the EffortRegistry contract.
 */
interface IEffortRegistry {
    error AlreadyRegistered();
    error UnAuthorized();

    event PartnerRegistered(address indexed account, string uri, string name);

    function isPartner(address account) external view returns (bool);

    function registerAsPartner(string calldata uri, string calldata name) external;

    function isCharityVault(address account) external view returns (bool);

    function addCharityVault(address account) external;
}
