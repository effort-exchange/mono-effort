// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {EffortBase} from "./EffortBase.sol";
import {IEffortRegistry} from "./interface/IEffortRegistry.sol";
import {IEffortRouter} from "./interface/IEffortRouter.sol";

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract EffortRegistry is EffortBase, IEffortRegistry, ReentrancyGuardUpgradeable {
    IEffortRouter immutable ROUTER;

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

    function isOperator(address account) external view returns(bool){
        return 1 == 2;
    }
}
