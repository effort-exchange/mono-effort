// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title GlobalVault
 * @notice Main donation vault where users deposit stablecoins and receive non-transferable vote tokens
 * @dev ERC4626 vault with non-transferable shares (soulbound tokens)
 *
 * Flow:
 * 1. Users deposit USDC via deposit()
 * 2. Users receive 1:1 non-transferable GlobalVote tokens
 * 3. At epoch end, DAFController calls distributeToCharity() to move funds
 * 4. Users' GlobalVote tokens are burned during distribution
 */
contract GlobalVault is Initializable, ERC4626Upgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    /// @notice Error thrown when attempting to transfer tokens
    error TokenNonTransferable();

    /// @notice Error thrown when caller is not the controller
    error OnlyController();

    /// @notice Error thrown when user has insufficient votes
    error InsufficientVotes(address user, uint256 requested, uint256 available);

    /// @notice The DAFController contract address
    address public controller;

    /// @notice Current epoch (distribution period)
    uint256 public currentEpoch;

    /// @notice Mapping of user => epoch => deposited amount (for tracking per-epoch deposits)
    mapping(address => mapping(uint256 => uint256)) public userEpochDeposits;

    /// @notice Total deposits in current epoch
    uint256 public currentEpochDeposits;

    /// @notice Event emitted when a user deposits
    event Deposited(address indexed user, uint256 amount, uint256 epoch);

    /// @notice Event emitted when votes are burned during distribution
    event VotesBurned(address indexed user, uint256 amount, uint256 epoch);

    /// @notice Event emitted when epoch advances
    event EpochAdvanced(uint256 newEpoch, uint256 totalDistributed);

    /// @notice Event emitted when controller is set
    event ControllerSet(address indexed controller);

    /// @dev Modifier to restrict functions to controller only
    modifier onlyController() {
        if (msg.sender != controller) revert OnlyController();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the GlobalVault
     * @param asset_ The underlying asset (USDC)
     * @param name_ Token name for vote tokens
     * @param symbol_ Token symbol for vote tokens
     * @param owner_ Initial owner address
     */
    function initialize(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address owner_
    ) public initializer {
        __ERC4626_init(asset_);
        __ERC20_init(name_, symbol_);
        __Ownable_init(owner_);
        currentEpoch = 1;
    }

    /**
     * @notice Set the DAFController address
     * @param controller_ The controller contract address
     */
    function setController(address controller_) external onlyOwner {
        controller = controller_;
        emit ControllerSet(controller_);
    }

    /**
     * @notice Deposit assets and receive vote tokens
     * @param assets Amount of assets to deposit
     * @param receiver Address to receive vote tokens
     * @return shares Amount of vote tokens minted
     */
    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        shares = super.deposit(assets, receiver);
        userEpochDeposits[receiver][currentEpoch] += assets;
        currentEpochDeposits += assets;
        emit Deposited(receiver, assets, currentEpoch);
    }

    /**
     * @notice Get user's voting power (their vote token balance)
     * @param user Address to check
     * @return Voting power
     */
    function getVotingPower(address user) external view returns (uint256) {
        return balanceOf(user);
    }

    /**
     * @notice Burn votes from a user during distribution (called by controller)
     * @param user Address to burn votes from
     * @param amount Amount of votes to burn
     */
    function burnVotes(address user, uint256 amount) external onlyController {
        uint256 balance = balanceOf(user);
        if (balance < amount) {
            revert InsufficientVotes(user, amount, balance);
        }
        _burn(user, amount);
        emit VotesBurned(user, amount, currentEpoch);
    }

    /**
     * @notice Transfer assets to a charity vault (called by controller during distribution)
     * @param charityVault Address of the charity vault
     * @param amount Amount of assets to transfer
     */
    function transferToCharity(address charityVault, uint256 amount) external onlyController {
        IERC20(asset()).safeTransfer(charityVault, amount);
    }

    /**
     * @notice Advance to the next epoch (called by controller after distribution)
     */
    function advanceEpoch() external onlyController {
        uint256 distributed = currentEpochDeposits;
        currentEpochDeposits = 0;
        currentEpoch += 1;
        emit EpochAdvanced(currentEpoch, distributed);
    }

    /**
     * @notice Get total assets available for distribution
     * @return Total assets in the vault
     */
    function totalAssetsForDistribution() external view returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    // ============ Non-Transferable Overrides ============

    /**
     * @dev Override transfer to prevent transfers (soulbound)
     */
    function transfer(address, uint256) public pure override returns (bool) {
        revert TokenNonTransferable();
    }

    /**
     * @dev Override transferFrom to prevent transfers (soulbound)
     */
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert TokenNonTransferable();
    }

    /**
     * @dev Override approve to prevent approvals
     */
    function approve(address, uint256) public pure override returns (bool) {
        revert TokenNonTransferable();
    }

    /**
     * @dev Disable withdraw (users can't withdraw, only vote)
     */
    function withdraw(uint256, address, address) public pure override returns (uint256) {
        revert TokenNonTransferable();
    }

    /**
     * @dev Disable redeem (users can't redeem, only vote)
     */
    function redeem(uint256, address, address) public pure override returns (uint256) {
        revert TokenNonTransferable();
    }
}
