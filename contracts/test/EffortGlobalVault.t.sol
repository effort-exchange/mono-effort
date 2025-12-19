// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {TestSuite} from "./TestSuite.sol";
import {EffortGlobalVault} from "../src/EffortGlobalVault.sol";
import {EffortVault} from "../src/EffortVault.sol";
import {UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract EffortGlobalVaultScenarioTest is TestSuite {
    EffortVault public cancerResearchVault;
    EffortVault public cleanWaterVault;

    address public partner = address(0x1337);

    function setUp() public override {
        super.setUp();

        // Register userX as a partner to create vaults
        vm.prank(partner);
        registry.registerAsPartner("https://example.com", "Example Partner");

        vm.startPrank(partner);
        cancerResearchVault = vaultFactory.create(usdc, "Cancer Research", "CR");
        cleanWaterVault = vaultFactory.create(usdc, "Clean Water", "CW");
        vm.stopPrank();
    }

    function test_asset_distribution_by_voting_token_1_to_1_pegged() public {
        address userX = address(0x1111);
        address userY = address(0x2222);
        address userZ = address(0x3333);
        // 1. Setup Balances
        uint256 amountX = 20 * 10 ** 6;
        uint256 amountY = 30 * 10 ** 6;
        uint256 amountZ = 1000 * 10 ** 6;

        usdc.mint(userX, amountX);
        usdc.mint(userY, amountY);
        usdc.mint(userZ, amountZ);

        // 2. Deposit to Global Vault (Donation)
        vm.startPrank(userX);
        usdc.approve(address(globalVault), amountX);
        globalVault.deposit(amountX, userX);
        vm.stopPrank();

        vm.startPrank(userY);
        usdc.approve(address(globalVault), amountY);
        globalVault.deposit(amountY, userY);
        vm.stopPrank();

        vm.startPrank(userZ);
        usdc.approve(address(globalVault), amountZ);
        globalVault.deposit(amountZ, userZ);
        vm.stopPrank();

        // Verify deposits (receipt tokens)
        assertEq(globalVault.balanceOf(userX), amountX, "User X should have 20 vUSDC");
        assertEq(globalVault.balanceOf(userY), amountY, "User Y should have 30 vUSDC");
        assertEq(globalVault.balanceOf(userZ), amountZ, "User Z should have 1000 vUSDC");

        // 3. Allocate Votes
        // User X votes 20 to Cancer Research
        vm.prank(userX);
        globalVault.allocateVotes(address(cancerResearchVault), amountX);

        // User Y votes 30 to Cancer Research
        vm.prank(userY);
        globalVault.allocateVotes(address(cancerResearchVault), amountY);

        // User Z votes 100 to Clean Water
        vm.prank(userZ);
        globalVault.allocateVotes(address(cleanWaterVault), 100 * 10 ** 6);

        // router.finalizeEpoch();

        // 4. Finalize Epoch
        // Advance time to end of epoch
        uint256 epochDuration = router.epochDuration();
        // Move forward by epochDuration + 1 second to ensure we are past the end
        // Assuming current timestamp is close to epochStartTime (which is initialized in constructor/initializer?)
        // Let's check router.epochStartTime()

        _advanceBlockBySeconds(block.timestamp + epochDuration);

        // anyone can call
        vm.prank(vm.randomAddress());
        // Call finalizeEpoch
        router.finalizeEpoch();

        // 5. Verify Results
        // User X should get receipt token for cancer research 20
        assertEq(cancerResearchVault.balanceOf(userX), amountX, "User X should have 20 Cancer Research shares");

        // User Y should get receipt token for cancer research 30
        assertEq(cancerResearchVault.balanceOf(userY), amountY, "User Y should have 30 Cancer Research shares");

        // User Z should get receipt token for clean water vault 100
        assertEq(cleanWaterVault.balanceOf(userZ), 100 * 10 ** 6, "User Z should have 100 Clean Water shares");

        // User Z still have 900 receipt allocation receipt token from global vault
        assertEq(globalVault.balanceOf(userZ), 900 * 10 ** 6, "User Z should have 900 global vault shares");
    }

    function test_asset_distribution_by_voting_token_saturated() public {
        address userX = address(0x1222);
        address userY = address(0x2222);
        address userZ = address(0x3222);
        address nonVotingDonor = address(0x4222);
        // 1. Setup Balances
        uint256 amountX = 1000 * 10 ** 6;
        uint256 amountY = 1000 * 10 ** 6;
        uint256 amountZ = 1000 * 10 ** 6;
        uint256 amountNonVotingDonor = 3000 * 10 ** 6;

        usdc.mint(userX, amountX);
        usdc.mint(userY, amountY);
        usdc.mint(userZ, amountZ);
        usdc.mint(nonVotingDonor, amountNonVotingDonor);

        // 2. Deposit to Global Vault (Donation)
        vm.startPrank(userX);
        usdc.approve(address(globalVault), amountX);
        globalVault.deposit(amountX, userX);
        vm.stopPrank();

        vm.startPrank(userY);
        usdc.approve(address(globalVault), amountY);
        globalVault.deposit(amountY, userY);
        vm.stopPrank();

        vm.startPrank(userZ);
        usdc.approve(address(globalVault), amountZ);
        globalVault.deposit(amountZ, userZ);
        vm.stopPrank();

        vm.startPrank(nonVotingDonor);
        usdc.transfer(address(globalVault), amountNonVotingDonor);
        vm.stopPrank();

        // Verify deposits (receipt tokens)
        assertEq(globalVault.balanceOf(userX), amountX, "User X should have 1000 vUSDC");
        assertEq(globalVault.balanceOf(userY), amountY, "User Y should have 1000 vUSDC");
        assertEq(globalVault.balanceOf(userZ), amountZ, "User Z should have 1000 vUSDC");
        assertEq(globalVault.balanceOf(nonVotingDonor), 0, "Non Voting Donor receive 0 voting token");

        // Because Non Voting Donor Sends the fund directly
        // Global Vault does not mint voting power for that user.
        // That mean existing votes for userx, y, z is not saturated (worth more, twice as much)
        // assertEq(globalVault.convertToAssets(1), 1999999, "gg");

        // 3. Allocate Votes
        // User X votes 1000 to Cancer Research
        vm.prank(userX);
        globalVault.allocateVotes(address(cancerResearchVault), amountX);

        // User Y votes 1000 to Cancer Research
        vm.prank(userY);
        globalVault.allocateVotes(address(cancerResearchVault), amountY);

        // User Z votes 100 to Clean Water
        vm.prank(userZ);
        globalVault.allocateVotes(address(cleanWaterVault), 100 * (10 ** 6));

        // router.finalizeEpoch();

        // 4. Finalize Epoch
        // Advance time to end of epoch
        uint256 epochDuration = router.epochDuration();
        // Move forward by epochDuration + 1 second to ensure we are past the end
        // Assuming current timestamp is close to epochStartTime (which is initialized in constructor/initializer?)
        // Let's check router.epochStartTime()

        _advanceBlockBySeconds(block.timestamp + epochDuration);

        // anyone can call
        vm.prank(vm.randomAddress());
        // Call finalizeEpoch
        router.finalizeEpoch();

        // 5. Verify Results
        // User X should get receipt token for cancer research 1999.999999
        // The reason the first user doesn't get exactly 1:2 ratio is because of OZ's inflation attack preventions with +1 offset.
        assertEq(
            cancerResearchVault.balanceOf(userX), 1999999999, "User X should have approx 2000 Cancer Research shares"
        );

        // User Y should get receipt token for cancer research 2000
        assertEq(
            cancerResearchVault.balanceOf(userY),
            2000 * 10 ** 6,
            "User Y should have approx 2000 Cancer Research shares"
        );

        // User Z should get receipt token for clean water vault 200
        assertEq(cleanWaterVault.balanceOf(userZ), 200 * 10 ** 6, "User Z should have approx 200 Clean Water shares");

        // User Z still have 900 receipt allocation receipt token from global vault
        assertEq(globalVault.balanceOf(userZ), 900 * 10 ** 6, "User Z should have 900 global vault shares");

        // assert that charity vault receive usdc
        assertEq(usdc.balanceOf(address(cancerResearchVault)), 2000 * 10 ** 6 + 1999999999);
        assertEq(usdc.balanceOf(address(cleanWaterVault)), 200 * 10 ** 6);
    }
}
