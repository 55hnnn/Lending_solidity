// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// - ETH를 담보로 사용해서 USDC를 빌리고 빌려줄 수 있는 서비스를 구현하세요.
// - 이자율은 24시간에 0.1% (복리), Loan To Value (LTV)는 50%, liquidation threshold는 75%로 하고 담보 가격 정보는 “참고코드"를 참고해 생성한 컨트랙트에서 갖고 오세요.
// - 필요한 기능들은 다음과 같습니다. Deposit (ETH, USDC 입금), Borrow (담보만큼 USDC 대출), Repay (대출 상환), Liquidate (담보를 청산하여 USDC 확보)
// - 청산 방법은 다양하기 때문에 조사 후 bad debt을 최소화에 가장 적합하다고 생각하는 방식을 적용하고 그 이유를 쓰세요.
// - 실제 토큰을 사용하지 않고 컨트랙트 생성자의 인자로 받은 주소들을 토큰의 주소로 간주합니다.
// - 주요 기능 인터페이스는 아래를 참고해 만드시면 됩니다.

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
        if (token == address(0)) { // Ether를 예치하는 경우
            require(msg.value == amount, "Ether amount mismatch");
            balances[msg.sender][token] += amount;
        } else { // ERC20 토큰을 예치하는 경우
            require(msg.value == 0, "No Ether should be sent");
            ERC20(token).transferFrom(msg.sender, address(this), amount);
            balances[msg.sender][token] += amount;
        }
    }

    function borrow(address token, uint256 amount) external {
        require(token != address(0), "Invalid token address");
        require(amount > 0, "Amount must be greater than zero");

        // 사용자가 제공한 담보의 가치를 계산
        uint256 collateralValue = _calculateCollateralValue(msg.sender);
        // 필요한 담보 비율 확인 (예: 150%)
        uint256 requiredCollateralValue = (amount + debts[msg.sender][token]) * dreamOracle.getPrice(token) * 2; 
        require(collateralValue >= requiredCollateralValue, "Insufficient collateral");

        // 대출 가능 여부 확인 후, ERC20 토큰 전송
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

        // 사용자가 상환할 금액을 스마트 계약에 전송
        ERC20(token).transferFrom(msg.sender, address(this), amount);

        // 부채를 줄임
        debts[msg.sender][token] -= amount;
    }
    
    function liquidate(address borrower, address token, uint256 repayAmount) external {
        require(borrower != address(0), "Invalid borrower address");
        require(token != address(0), "Invalid token address");
        require(repayAmount > 0, "Repayment amount must be greater than zero");

        uint256 debt = debts[borrower][token];
        require(debt > 0, "No outstanding debt");

        // 청산 가능한 상태인지 확인
        uint256 collateralValue = _calculateCollateralValue(borrower);
        uint256 debtValue = debt * dreamOracle.getPrice(token);
        uint256 liquidationThreshold = (collateralValue * 3) / 4; // 예: 담보 비율이 75%일 때 청산 가능

        require(debtValue > liquidationThreshold, "Loan is not eligible for liquidation");
        require(repayAmount <= (debt / 4), "Repayment amount exceeds debt");

        ERC20(token).transferFrom(msg.sender, address(this), repayAmount);
        debts[borrower][token] -= repayAmount;
    }

    function withdraw(address token, uint256 amount) external {
        require(amount > 0, "Amount must be greater than zero");
        if (token == address(0)) { // Ether를 인출하는 경우
            require(balances[msg.sender][token] >= amount, "Insufficient balance");
        
            // 인출 가능 여부 확인 (예: 부채 대비 담보 비율)
            uint256 WithdrawablecollateralValue = _calculateCollateralValue(msg.sender) - debts[msg.sender][usdc] * dreamOracle.getPrice(usdc) * 4 / 3;
            uint256 WithdrawValue = amount * dreamOracle.getPrice(token);

            require(WithdrawValue <= WithdrawablecollateralValue, "Collateral would be insufficient after withdrawal");

            balances[msg.sender][token] -= amount;
            payable(msg.sender).transfer(amount);
        } else { // ERC20 토큰을 인출하는 경우
            require(balances[msg.sender][token] >= amount, "Insufficient balance");

            // 인출 가능 여부 확인 (예: 부채 대비 담보 비율)
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

        return etherValue + usdcValue; // 총 담보 가치 반환
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