// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {EffortBase} from "./EffortBase.sol";
import {IEffortRegistry} from "./interface/IEffortRegistry.sol";
import {IEffortRouter} from "./interface/IEffortRouter.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract EffortRouter is EffortBase, IEffortRouter, ReentrancyGuardUpgradeable {
    IEffortRegistry immutable REGISTRY;

    constructor(IEffortRegistry registry) {
        REGISTRY = registry;
        _disableInitializers();
    }

    function initializeAll(address initialOwner) public {
        EffortBase.initialize(initialOwner);
        initialize2();
    }

    function initialize2() public reinitializer(2) {
        __ReentrancyGuard_init();
    }
}
