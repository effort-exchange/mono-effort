// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {GlobalVault} from "../src/daf/GlobalVault.sol";
import {CharityVault} from "../src/daf/CharityVault.sol";
import {DAFController} from "../src/daf/DAFController.sol";
import {MockERC20} from "./MockERC20.sol";

/**
 * @title DAFTest
 * @notice Comprehensive test suite for the Donor Advised Fund system
 */
contract DAFTest is Test {
    // Contracts
    GlobalVault public globalVault;
    CharityVault public charityVaultImpl;
    DAFController public controller;
    MockERC20 public usdc;

    // Users
    address public owner = makeAddr("owner");
    address public userX = makeAddr("userX");
    address public userY = makeAddr("userY");
    address public userZ = makeAddr("userZ");

    // Charity beneficiaries
    address public cleanWaterBeneficiary = makeAddr("cleanWaterBeneficiary");
    address public cancerResearchBeneficiary = makeAddr("cancerResearchBeneficiary");

    // Charity vaults
    address public cleanWaterVault;
    address public cancerResearchVault;

    // Constants
    uint256 constant USDC_DECIMALS = 6;
    uint256 constant USER_X_DEPOSIT = 40 * 10**USDC_DECIMALS;
    uint256 constant USER_Y_DEPOSIT = 30 * 10**USDC_DECIMALS;
    uint256 constant USER_Z_DEPOSIT = 1000 * 10**USDC_DECIMALS;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy USDC mock
        usdc = new MockERC20("USD Coin", "USDC", 6);

        // Deploy GlobalVault
        globalVault = new GlobalVault();
        globalVault.initialize(
            IERC20(address(usdc)),
            "Global DAF Vote",
            "gDAFV",
            owner
        );

        // Deploy CharityVault implementation (for cloning)
        charityVaultImpl = new CharityVault();

        // Deploy DAFController
        controller = new DAFController();
        controller.initialize(
            globalVault,
            address(charityVaultImpl),
            owner
        );

        // Set controller on GlobalVault
        globalVault.setController(address(controller));

        // Create charity vaults
        cleanWaterVault = controller.createCharityVault("CleanWater", cleanWaterBeneficiary);
        cancerResearchVault = controller.createCharityVault("CancerResearch", cancerResearchBeneficiary);

        vm.stopPrank();

        // Mint USDC to users
        usdc.mint(userX, USER_X_DEPOSIT);
        usdc.mint(userY, USER_Y_DEPOSIT);
        usdc.mint(userZ, USER_Z_DEPOSIT);

        // Approve GlobalVault to spend users' USDC
        vm.prank(userX);
        usdc.approve(address(globalVault), type(uint256).max);
        vm.prank(userY);
        usdc.approve(address(globalVault), type(uint256).max);
        vm.prank(userZ);
        usdc.approve(address(globalVault), type(uint256).max);
    }

    // ============ Donation Tests ============

    function test_UserCanDeposit() public {
        vm.prank(userX);
        globalVault.deposit(USER_X_DEPOSIT, userX);

        assertEq(globalVault.balanceOf(userX), USER_X_DEPOSIT);
        assertEq(globalVault.getVotingPower(userX), USER_X_DEPOSIT);
        assertEq(usdc.balanceOf(address(globalVault)), USER_X_DEPOSIT);
    }

    function test_MultipleUsersCanDeposit() public {
        vm.prank(userX);
        globalVault.deposit(USER_X_DEPOSIT, userX);

        vm.prank(userY);
        globalVault.deposit(USER_Y_DEPOSIT, userY);

        vm.prank(userZ);
        globalVault.deposit(USER_Z_DEPOSIT, userZ);

        assertEq(globalVault.balanceOf(userX), USER_X_DEPOSIT);
        assertEq(globalVault.balanceOf(userY), USER_Y_DEPOSIT);
        assertEq(globalVault.balanceOf(userZ), USER_Z_DEPOSIT);
        assertEq(usdc.balanceOf(address(globalVault)), USER_X_DEPOSIT + USER_Y_DEPOSIT + USER_Z_DEPOSIT);
    }

    function test_VoteTokensAreNonTransferable() public {
        vm.prank(userX);
        globalVault.deposit(USER_X_DEPOSIT, userX);

        vm.prank(userX);
        vm.expectRevert(GlobalVault.TokenNonTransferable.selector);
        globalVault.transfer(userY, USER_X_DEPOSIT);
    }

    function test_CannotWithdrawFromGlobalVault() public {
        vm.prank(userX);
        globalVault.deposit(USER_X_DEPOSIT, userX);

        vm.prank(userX);
        vm.expectRevert(GlobalVault.TokenNonTransferable.selector);
        globalVault.withdraw(USER_X_DEPOSIT, userX, userX);
    }

    // ============ Distribution Voting Tests ============

    function test_OwnerCanOpenDistribution() public {
        vm.prank(owner);
        controller.openDistribution();

        assertTrue(controller.distributionOpen());
    }

    function test_NonOwnerCannotOpenDistribution() public {
        vm.prank(userX);
        vm.expectRevert();
        controller.openDistribution();
    }

    function test_UserCanSubmitDistributionVote() public {
        // Setup: Users deposit
        _setupDeposits();

        // Open distribution
        vm.prank(owner);
        controller.openDistribution();

        // User X votes: 20 to CleanWater, 20 to CancerResearch
        address[] memory charities = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        charities[0] = cleanWaterVault;
        charities[1] = cancerResearchVault;
        amounts[0] = 20 * 10**USDC_DECIMALS;
        amounts[1] = 20 * 10**USDC_DECIMALS;

        vm.prank(userX);
        controller.submitDistributionVote(charities, amounts);

        assertTrue(controller.hasVotedInEpoch(userX, 1));
        assertEq(controller.totalVotesCast(), USER_X_DEPOSIT);
    }

    function test_CannotVoteTwiceInSameEpoch() public {
        _setupDeposits();

        vm.prank(owner);
        controller.openDistribution();

        // First vote
        address[] memory charities = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        charities[0] = cleanWaterVault;
        amounts[0] = 20 * 10**USDC_DECIMALS;

        vm.prank(userX);
        controller.submitDistributionVote(charities, amounts);

        // Second vote should fail
        vm.prank(userX);
        vm.expectRevert(abi.encodeWithSelector(DAFController.AlreadyVotedThisEpoch.selector, userX, 1));
        controller.submitDistributionVote(charities, amounts);
    }

    function test_CannotAllocateMoreThanBalance() public {
        _setupDeposits();

        vm.prank(owner);
        controller.openDistribution();

        address[] memory charities = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        charities[0] = cleanWaterVault;
        amounts[0] = USER_X_DEPOSIT + 1; // More than user X has

        vm.prank(userX);
        vm.expectRevert(abi.encodeWithSelector(
            DAFController.VoteAllocationExceedsBalance.selector,
            userX,
            USER_X_DEPOSIT + 1,
            USER_X_DEPOSIT
        ));
        controller.submitDistributionVote(charities, amounts);
    }

    // ============ Full Distribution Flow Test ============

    function test_FullDistributionFlow() public {
        // Phase 1: Donations
        _setupDeposits();

        uint256 totalDeposits = USER_X_DEPOSIT + USER_Y_DEPOSIT + USER_Z_DEPOSIT;
        assertEq(usdc.balanceOf(address(globalVault)), totalDeposits);

        // Phase 2: Distribution Voting
        vm.prank(owner);
        controller.openDistribution();

        // User X: 20 to CleanWater, 20 to CancerResearch
        {
            address[] memory charities = new address[](2);
            uint256[] memory amounts = new uint256[](2);
            charities[0] = cleanWaterVault;
            charities[1] = cancerResearchVault;
            amounts[0] = 20 * 10**USDC_DECIMALS;
            amounts[1] = 20 * 10**USDC_DECIMALS;

            vm.prank(userX);
            controller.submitDistributionVote(charities, amounts);
        }

        // User Y: 30 to CleanWater
        {
            address[] memory charities = new address[](1);
            uint256[] memory amounts = new uint256[](1);
            charities[0] = cleanWaterVault;
            amounts[0] = USER_Y_DEPOSIT;

            vm.prank(userY);
            controller.submitDistributionVote(charities, amounts);
        }

        // User Z: 1000 to CleanWater
        {
            address[] memory charities = new address[](1);
            uint256[] memory amounts = new uint256[](1);
            charities[0] = cleanWaterVault;
            amounts[0] = USER_Z_DEPOSIT;

            vm.prank(userZ);
            controller.submitDistributionVote(charities, amounts);
        }

        // Verify vote totals
        // CleanWater: 20 + 30 + 1000 = 1050 USDC
        // CancerResearch: 20 USDC
        uint256 cleanWaterVotes = 20 * 10**USDC_DECIMALS + USER_Y_DEPOSIT + USER_Z_DEPOSIT;
        uint256 cancerVotes = 20 * 10**USDC_DECIMALS;

        assertEq(controller.charityVoteTotal(cleanWaterVault), cleanWaterVotes);
        assertEq(controller.charityVoteTotal(cancerResearchVault), cancerVotes);
        assertEq(controller.totalVotesCast(), totalDeposits);

        // Phase 3: Execute Distribution
        vm.prank(owner);
        controller.executeDistribution();

        // Verify funds distributed proportionally
        // CleanWater should have: 1050/1070 * 1070 = 1050 USDC
        // CancerResearch should have: 20/1070 * 1070 = 20 USDC
        assertEq(usdc.balanceOf(cleanWaterVault), cleanWaterVotes);
        assertEq(usdc.balanceOf(cancerResearchVault), cancerVotes);
        assertEq(usdc.balanceOf(address(globalVault)), 0);

        // Verify GlobalVault tokens burned
        assertEq(globalVault.balanceOf(userX), 0);
        assertEq(globalVault.balanceOf(userY), 0);
        assertEq(globalVault.balanceOf(userZ), 0);

        // Verify CharityVault tokens minted
        // User X: 20 CleanWater, 20 CancerResearch
        assertEq(CharityVault(cleanWaterVault).balanceOf(userX), 20 * 10**USDC_DECIMALS);
        assertEq(CharityVault(cancerResearchVault).balanceOf(userX), 20 * 10**USDC_DECIMALS);

        // User Y: 30 CleanWater
        assertEq(CharityVault(cleanWaterVault).balanceOf(userY), USER_Y_DEPOSIT);
        assertEq(CharityVault(cancerResearchVault).balanceOf(userY), 0);

        // User Z: 1000 CleanWater
        assertEq(CharityVault(cleanWaterVault).balanceOf(userZ), USER_Z_DEPOSIT);
        assertEq(CharityVault(cancerResearchVault).balanceOf(userZ), 0);

        // Verify epoch advanced
        assertEq(controller.currentEpoch(), 2);
        assertEq(globalVault.currentEpoch(), 2);
        assertFalse(controller.distributionOpen());
    }

    // ============ Grant Proposal Tests ============

    function test_BeneficiaryCanProposeGrant() public {
        // Run full distribution first
        test_FullDistributionFlow();

        // Beneficiary proposes grant
        vm.prank(cleanWaterBeneficiary);
        uint256 proposalId = CharityVault(cleanWaterVault).proposeGrant(
            500 * 10**USDC_DECIMALS,
            "Buy 600 blankets for refugees"
        );

        assertEq(proposalId, 1);

        (
            uint256 id,
            address proposer,
            uint256 amount,
            string memory description,
            uint256 votesFor,
            uint256 votesAgainst,
            uint256 startTime,
            uint256 endTime,
            CharityVault.ProposalState state
        ) = CharityVault(cleanWaterVault).getProposal(proposalId);

        assertEq(id, 1);
        assertEq(proposer, cleanWaterBeneficiary);
        assertEq(amount, 500 * 10**USDC_DECIMALS);
        assertEq(description, "Buy 600 blankets for refugees");
        assertEq(votesFor, 0);
        assertEq(votesAgainst, 0);
        assertTrue(state == CharityVault.ProposalState.Active);
    }

    function test_NonBeneficiaryCannotProposeGrant() public {
        test_FullDistributionFlow();

        vm.prank(userX);
        vm.expectRevert(CharityVault.OnlyBeneficiary.selector);
        CharityVault(cleanWaterVault).proposeGrant(
            500 * 10**USDC_DECIMALS,
            "Unauthorized proposal"
        );
    }

    function test_UsersCanVoteOnGrant() public {
        test_FullDistributionFlow();

        // Propose grant
        vm.prank(cleanWaterBeneficiary);
        uint256 proposalId = CharityVault(cleanWaterVault).proposeGrant(
            500 * 10**USDC_DECIMALS,
            "Buy 600 blankets"
        );

        // Users vote
        vm.prank(userX);
        CharityVault(cleanWaterVault).vote(proposalId, true);

        vm.prank(userY);
        CharityVault(cleanWaterVault).vote(proposalId, true);

        vm.prank(userZ);
        CharityVault(cleanWaterVault).vote(proposalId, true);

        // Check votes
        (,,,, uint256 votesFor,,,,) = CharityVault(cleanWaterVault).getProposal(proposalId);

        // Total votes: 20 + 30 + 1000 = 1050
        assertEq(votesFor, 20 * 10**USDC_DECIMALS + USER_Y_DEPOSIT + USER_Z_DEPOSIT);
    }

    function test_CannotVoteTwiceOnSameGrant() public {
        test_FullDistributionFlow();

        vm.prank(cleanWaterBeneficiary);
        uint256 proposalId = CharityVault(cleanWaterVault).proposeGrant(
            500 * 10**USDC_DECIMALS,
            "Buy blankets"
        );

        vm.prank(userX);
        CharityVault(cleanWaterVault).vote(proposalId, true);

        vm.prank(userX);
        vm.expectRevert(abi.encodeWithSelector(CharityVault.AlreadyVoted.selector, proposalId, userX));
        CharityVault(cleanWaterVault).vote(proposalId, true);
    }

    function test_GrantExecutionAfterApproval() public {
        test_FullDistributionFlow();

        uint256 grantAmount = 500 * 10**USDC_DECIMALS;

        // Propose grant
        vm.prank(cleanWaterBeneficiary);
        uint256 proposalId = CharityVault(cleanWaterVault).proposeGrant(
            grantAmount,
            "Buy 600 blankets"
        );

        // All users vote yes
        vm.prank(userX);
        CharityVault(cleanWaterVault).vote(proposalId, true);
        vm.prank(userY);
        CharityVault(cleanWaterVault).vote(proposalId, true);
        vm.prank(userZ);
        CharityVault(cleanWaterVault).vote(proposalId, true);

        // Fast forward past voting period
        vm.warp(block.timestamp + 8 days);

        // Finalize proposal
        CharityVault(cleanWaterVault).finalizeProposal(proposalId);

        // Check proposal succeeded
        (,,,,,,,, CharityVault.ProposalState state) = CharityVault(cleanWaterVault).getProposal(proposalId);
        assertTrue(state == CharityVault.ProposalState.Succeeded);

        // Execute grant
        uint256 beneficiaryBalanceBefore = usdc.balanceOf(cleanWaterBeneficiary);
        CharityVault(cleanWaterVault).executeGrant(proposalId);

        // Verify funds transferred
        assertEq(usdc.balanceOf(cleanWaterBeneficiary), beneficiaryBalanceBefore + grantAmount);

        // Verify state updated
        (,,,,,,,, CharityVault.ProposalState newState) = CharityVault(cleanWaterVault).getProposal(proposalId);
        assertTrue(newState == CharityVault.ProposalState.Executed);
    }

    function test_GrantDefeatedWithMajorityAgainst() public {
        test_FullDistributionFlow();

        // Propose grant
        vm.prank(cleanWaterBeneficiary);
        uint256 proposalId = CharityVault(cleanWaterVault).proposeGrant(
            500 * 10**USDC_DECIMALS,
            "Questionable expense"
        );

        // User X votes yes (20), Y and Z vote no (30 + 1000 = 1030)
        vm.prank(userX);
        CharityVault(cleanWaterVault).vote(proposalId, true);
        vm.prank(userY);
        CharityVault(cleanWaterVault).vote(proposalId, false);
        vm.prank(userZ);
        CharityVault(cleanWaterVault).vote(proposalId, false);

        // Fast forward and finalize
        vm.warp(block.timestamp + 8 days);
        CharityVault(cleanWaterVault).finalizeProposal(proposalId);

        // Check proposal defeated
        (,,,,,,,, CharityVault.ProposalState state) = CharityVault(cleanWaterVault).getProposal(proposalId);
        assertTrue(state == CharityVault.ProposalState.Defeated);
    }

    function test_CharityVoteTokensAreNonTransferable() public {
        test_FullDistributionFlow();

        vm.prank(userX);
        vm.expectRevert(CharityVault.TokenNonTransferable.selector);
        CharityVault(cleanWaterVault).transfer(userY, 10 * 10**USDC_DECIMALS);
    }

    // ============ Edge Cases ============

    function test_CannotExecuteDistributionWithNoVotes() public {
        _setupDeposits();

        vm.prank(owner);
        controller.openDistribution();

        vm.prank(owner);
        vm.expectRevert(DAFController.NoVotesCast.selector);
        controller.executeDistribution();
    }

    function test_NewEpochAfterDistribution() public {
        test_FullDistributionFlow();

        // New deposits in epoch 2
        usdc.mint(userX, USER_X_DEPOSIT);
        vm.prank(userX);
        globalVault.deposit(USER_X_DEPOSIT, userX);

        assertEq(globalVault.balanceOf(userX), USER_X_DEPOSIT);
        assertEq(globalVault.currentEpoch(), 2);
    }

    // ============ Helper Functions ============

    function _setupDeposits() internal {
        vm.prank(userX);
        globalVault.deposit(USER_X_DEPOSIT, userX);

        vm.prank(userY);
        globalVault.deposit(USER_Y_DEPOSIT, userY);

        vm.prank(userZ);
        globalVault.deposit(USER_Z_DEPOSIT, userZ);
    }
}
