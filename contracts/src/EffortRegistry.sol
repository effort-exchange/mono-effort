// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {EffortBase} from "./EffortBase.sol";

contract EffortRegistry is EffortBase {
    constructor() {
        _disableInitializers();
    }
}
