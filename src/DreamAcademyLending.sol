// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IPriceOracle {
    function getPrice(address token) external view returns (uint256);
    function setPrice(address token, uint256 price) external;
}

contract DreamAcademyLending {
    
    IPriceOracle dreamOracle;
    address usdc;

    mapping(address => mapping(address => uint256)) balances;
    mapping(address => mapping(address => uint256)) debts;

    constructor (IPriceOracle _oracle, address token) {
        dreamOracle = _oracle;
        usdc = token;
    }

    function initializeLendingProtocol(address token) external payable {
        require(token != address(0), "Invalid token address");
        require(msg.value > 0, "Must send Ether to initialize");

        if (token != address(0)) {
            ERC20(token).transferFrom(msg.sender, address(this), msg.value);
            balances[address(this)][token] += msg.value;
        }
    }

    function deposit(address token, uint256 amount) external payable {
        if (token == address(0)) {
            require(msg.value == amount, "Ether amount mismatch");
            balances[msg.sender][token] += amount;
        } else {
            require(msg.value == 0, "No Ether should be sent");
            ERC20(token).transferFrom(msg.sender, address(this), amount);
            balances[msg.sender][token] += amount;
        }
    }

    function borrow(address token, uint256 amount) external {
        require(token != address(0), "Invalid token address");
        require(amount > 0, "Amount must be greater than zero");

        uint256 collateralValue = _calculateCollateralValue(msg.sender);
        uint256 requiredCollateralValue = (amount + debts[msg.sender][token]) * dreamOracle.getPrice(token) * 2; 
        require(collateralValue >= requiredCollateralValue, "Insufficient collateral");

        require(ERC20(token).balanceOf(address(this)) >= amount, "Insufficient liquidity");
        ERC20(token).transfer(msg.sender, amount);
        debts[msg.sender][token] += amount;
    }

    function repay(address token, uint256 amount) external {
        require(token != address(0), "Invalid token address");
        require(amount > 0, "Amount must be greater than zero");

        uint256 debt = debts[msg.sender][token];
        require(debt > 0, "No outstanding debt");
        require(amount <= debt, "Repayment amount exceeds debt");

        ERC20(token).transferFrom(msg.sender, address(this), amount);
        debts[msg.sender][token] -= amount;
    }
    
    function liquidate(address borrower, address token, uint256 repayAmount) external {
        require(borrower != address(0), "Invalid borrower address");
        require(token != address(0), "Invalid token address");
        require(repayAmount > 0, "Repayment amount must be greater than zero");

        uint256 debt = debts[borrower][token];
        require(debt > 0, "No outstanding debt");

        uint256 collateralValue = _calculateCollateralValue(borrower);
        uint256 debtValue = debt * dreamOracle.getPrice(token);
        uint256 liquidationThreshold = (collateralValue * 3) / 4;

        require(debtValue > liquidationThreshold, "Loan is not eligible for liquidation");
        require(repayAmount <= (debt / 4), "Repayment amount exceeds debt");

        ERC20(token).transferFrom(msg.sender, address(this), repayAmount);
        debts[borrower][token] -= repayAmount;
    }

    function withdraw(address token, uint256 amount) external {
        require(amount > 0, "Amount must be greater than zero");
        if (token == address(0)) {
            require(balances[msg.sender][token] >= amount, "Insufficient balance");
        
            uint256 WithdrawablecollateralValue = _calculateCollateralValue(msg.sender) - debts[msg.sender][usdc] * dreamOracle.getPrice(usdc) * 4 / 3;
            uint256 WithdrawValue = amount * dreamOracle.getPrice(token);

            require(WithdrawValue <= WithdrawablecollateralValue, "Collateral would be insufficient after withdrawal");

            balances[msg.sender][token] -= amount;
            payable(msg.sender).transfer(amount);
        } else {
            require(balances[msg.sender][token] >= amount, "Insufficient balance");

            uint256 WithdrawablecollateralValue = _calculateCollateralValue(msg.sender) - debts[msg.sender][usdc] * dreamOracle.getPrice(usdc) * 4 / 3;
            uint256 WithdrawValue = amount * dreamOracle.getPrice(token);

            require(WithdrawValue <= WithdrawablecollateralValue, "Collateral would be insufficient after withdrawal");

            balances[msg.sender][token] -= amount;
            ERC20(token).transfer(msg.sender, amount);
        }
    }

    function _calculateCollateralValue(address user) internal view returns (uint256) {
        uint256 etherValue = balances[user][address(0)] * dreamOracle.getPrice(address(0));
        uint256 usdcValue = balances[user][usdc] * dreamOracle.getPrice(usdc);

        return etherValue + usdcValue;
    }
    
    uint256 lastblock = block.number;
    function getAccruedSupplyAmount(address token) external returns (uint256) {
        uint256 principal = balances[address(this)][token]; // 사용자가 예치한 원금
        uint256 interestRate = 1e15 / uint256(7200); // 해당 토큰에 대한 이자율을 가져옴
        uint256 blocksElapsed = block.number - lastblock;// 마지막 이자 계산 이후 지난 블록 수

        // 이자 계산: 원금 * 이자율 * 지난 블록 수
        uint256 interest = (principal * interestRate * blocksElapsed) / 1e18;

        // 총 예치 금액 = 원금 + 누적 이자
        uint256 totalAccruedAmount = principal + interest;
        lastblock = block.number;

        return totalAccruedAmount;
    }
}