// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract LendingPool is ReentrancyGuard {
    using SafeERC20 for ERC20;

    ERC20 public collateralToken;
    ERC20 public borrowToken;

    // user => amount
    mapping(address => uint256) public collateral;
    mapping(address => uint256) public debt;

    uint256 public constant COLLATERAL_FACTOR = 75; // 75%
    uint256 public constant LIQUIDATION_THRESHOLD = 80;
    uint256 public constant LIQUIDATION_BONUS = 10;

    // Events
    event Deposit(address indexed user, uint256 amount);
    event Borrow(address indexed user, uint256 amount);
    event Repay(address indexed user, uint256 amount);
    event Liquidate(address indexed liquidator, address indexed user, uint256 amount);

    constructor(address _collateralToken, address _borrowToken) {
        collateralToken = ERC20(_collateralToken);
        borrowToken = ERC20(_borrowToken);
    }

    // --- Deposit ---
    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be > 0");

        collateralToken.safeTransferFrom(msg.sender, address(this), amount);

        collateral[msg.sender] += amount;

        emit Deposit(msg.sender, amount);
    }

    // --- Borrow ---
    function borrow(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be > 0");

        uint256 maxBorrow = (collateral[msg.sender] * COLLATERAL_FACTOR) / 100;

        require(debt[msg.sender] + amount <= maxBorrow, "Exceeds borrow limit");

        debt[msg.sender] += amount;

        borrowToken.safeTransfer(msg.sender, amount);

        emit Borrow(msg.sender, amount);
    }

    // --- Repay ---
    function repay(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be > 0");
        require(debt[msg.sender] >= amount, "Too much repay");

        borrowToken.safeTransferFrom(msg.sender, address(this), amount);

        debt[msg.sender] -= amount;

        emit Repay(msg.sender, amount);
    }

    // --- Health Factor ---
    function _healthFactor(address user) internal view returns (uint256) {
        if (debt[user] == 0) return type(uint256).max;

        uint256 maxDebt = (collateral[user] * LIQUIDATION_THRESHOLD) / 100;

        return (maxDebt * 1e18) / debt[user];
    }

    // --- Liquidation ---
    function liquidate(address user, uint256 repayAmount) external nonReentrant {
        require(_healthFactor(user) < 1e18, "User is healthy");
        require(repayAmount > 0, "Amount must be > 0");
        require(debt[user] >= repayAmount, "Too much repay");

        borrowToken.safeTransferFrom(msg.sender, address(this), repayAmount);

        uint256 collateralToSeize = (repayAmount * (100 + LIQUIDATION_BONUS)) / 100;

        require(collateral[user] >= collateralToSeize, "Not enough collateral");

        debt[user] -= repayAmount;
        collateral[user] -= collateralToSeize;

        require(
            collateralToken.transfer(msg.sender, collateralToSeize),
            "Transfer failed"
        );

        emit Liquidate(msg.sender, user, repayAmount);
    }

    // --- TESTING ONLY ---
    function setDebtForTest(address user, uint256 amount) external {
        debt[user] = amount;
    }
}