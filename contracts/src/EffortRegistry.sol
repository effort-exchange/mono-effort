// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {EffortBase} from "./EffortBase.sol";
import {IEffortRegistry} from "./interface/IEffortRegistry.sol";
import {IEffortVaultFactory} from "./interface/IEffortVaultFactory.sol";
import {IEffortRouter} from "./interface/IEffortRouter.sol";

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract EffortRegistry is EffortBase, IEffortRegistry, ReentrancyGuardUpgradeable {
    IEffortRouter immutable ROUTER;
    IEffortVaultFactory immutable FACTORY;

    mapping(address Partner => bool) private _partners;
    mapping(address CharityVault => address Partner) private _charityVaults;

    modifier onlyPartner(address account) {
        if (_partners[account] != true) {
            revert UnAuthorized();
        }
        _;
    }

    modifier onlyCharityVaultFactory(address account) {
        if (account != address(FACTORY)) {
            revert UnAuthorized();
        }
        _;
    }

    constructor(IEffortRouter router_, IEffortVaultFactory factory_) {
        FACTORY = factory_;
        ROUTER = router_;
        _disableInitializers();
    }

    function initializeAll(address initialOwner) public {
        EffortBase.initialize(initialOwner);
        initialize2();
    }
    
    function initialize2() public reinitializer(2) {
        __ReentrancyGuard_init();
    }

    function isPartner(address account) external view returns(bool){
        return _partners[account] == true;
    }

    function registerAsPartner(string calldata uri, string calldata name) external {
        address sender = _msgSender();
        if (_partners[sender] == true) {
            revert AlreadyRegistered();
        }

        _partners[sender] = true;

        emit PartnerRegistered(sender, uri, name);
    }

    function addCharityVault(address vaultAddress) external onlyCharityVaultFactory(_msgSender()) {
        if(_charityVaults[vaultAddress] != address(0)) {
            revert AlreadyRegistered();
        }
        _charityVaults[vaultAddress] = vaultAddress;
    }

    function isCharityVault(address account) external view returns(bool) {
        return _charityVaults[account] != address(0);
    }
}
