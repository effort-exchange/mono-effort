// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {MockERC20} from "./MockERC20.sol";
import {EffortBase} from "../src/EffortBase.sol";
import {EffortRegistry} from "../src/EffortRegistry.sol";
import {EffortRouter} from "../src/EffortRouter.sol";
import {EffortVaultFactory} from "../src/EffortVaultFactory.sol";
import {EffortVault} from "../src/EffortVault.sol";
import {EffortGlobalVault} from "../src/EffortGlobalVault.sol";
import {Test, console} from "forge-std/Test.sol";
import {UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";

/**
 * @dev This test suite set up all the  contracts needed for testing.
 */
contract TestSuite is Test {
    address public owner = vm.randomAddress();

    address public baseImpl = address(new EffortBase());

    EffortRouter public router;
    EffortRegistry public registry;
    EffortVaultFactory public vaultFactory;
    EffortGlobalVault public globalVault;

    function setUp() public virtual {
        bytes memory baseInit = abi.encodeCall(EffortBase.initialize, (owner));

        router = EffortRouter(UnsafeUpgrades.deployUUPSProxy(baseImpl, baseInit));
        registry = EffortRegistry(UnsafeUpgrades.deployUUPSProxy(baseImpl, baseInit));
        vaultFactory = EffortVaultFactory(UnsafeUpgrades.deployUUPSProxy(baseImpl, baseInit));
        globalVault = EffortGlobalVault(UnsafeUpgrades.deployUUPSProxy(baseImpl, baseInit));

        EffortVault vaultImpl = new EffortVault(router, registry);
        address beacon = UnsafeUpgrades.deployBeacon(address(vaultImpl), owner);

        vm.startPrank(owner);
        UnsafeUpgrades.upgradeProxy(
            address(router), address(new EffortRouter(registry, globalVault)), abi.encodeCall(EffortRouter.initialize2, ())
        );
        UnsafeUpgrades.upgradeProxy(
            address(registry), address(new EffortRegistry(router)), abi.encodeCall(EffortRegistry.initialize2, ())
        );
        UnsafeUpgrades.upgradeProxy(address(vaultFactory), address(new EffortVaultFactory(beacon, registry)), "");
        vm.stopPrank();
    }

    function _advanceBlockBy(uint256 blocks) internal {
        vm.roll(block.number + blocks);
        vm.warp(block.timestamp + (12 * blocks));
    }

    function _advanceBlockBySeconds(uint256 newSeconds) internal {
        vm.roll(block.number + (newSeconds / 12));
        vm.warp(block.timestamp + newSeconds);
    }
}
