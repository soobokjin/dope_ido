pragma solidity ^0.8.0;

import {SafeMath} from '@openzeppelin/contracts/utils/math/SafeMath.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {Context, Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {Fund, IFund} from "../Fund.sol";
import "hardhat/console.sol";

interface ILend {
    function getDepositedAmount(address user) external view returns (uint256);
    function deposit (uint256 amount) external;
    function withdraw () external returns (uint256, uint256);
    function borrow (uint256 amount) external;
    function repay (uint amount) external;
}


contract Lend {
    using SafeERC20 for IERC20;
    using SafeMath for uint32;
    using SafeMath for uint256;

    event Deposit(
        address indexed user,
        uint256 amount,
        uint256 totalDepositAmount
    );

    event Withdraw(
        address indexed user,
        uint256 amount
    );

    event Borrow(
        address indexed user,
        uint256 amount
    );

    event Repay(
        address indexed user,
        uint256 repayAmount,
        uint256 interestAmount
    );

    // 소수점 둘 째 자리까지 표현
    uint32 constant MAX_LTV_RATE = 10000;
    uint32 constant MAX_INTEREST_RATE = 10000;
    uint256 constant MAX_PERCENT_RATE = 1e18;

    mapping (address => uint256) lenderDepositAmount;
    mapping (address => uint256) borrowAmount;

    IFund public fund;
    IERC20 public lendToken;

    uint256 public ltvRate;
    uint256 public interestRate;

    uint32 public totalLender;
    uint256 public maxUserAllocation;

    uint256 public maxTotalAllocation;

    uint256 public totalLockedDepositAmount;
    uint256 public totalCurrentDepositAmount;
    uint256 public totalRemainDepositAmountAfterDistribution;

    constructor (
        address _fundAddress,
        address _lendTokenAddress,
        uint256 _maxTotalAllocation,
        uint256 _maxUserAllocation,
        uint256 _ltvRate,
        uint256 _interestRate
    ) {
        // Todo: sale amount 를 받아서 maxAllocation 설정하기
        fund = IFund(_fundAddress);
        lendToken = IERC20(_lendTokenAddress);
        maxTotalAllocation = _maxTotalAllocation;
        maxUserAllocation = _maxUserAllocation;
        ltvRate = _ltvRate;
        interestRate = _interestRate;
    }

//   function getExpectedRepayInterest(address user, uint256 amount) public view returns (uint256, uint256, uint256) {
//        // Todo: 함수로 중복 구현 제거
//        uint256 unlockCollateralAmount = amount.mul(MAX_LTV_RATE).div(ltvRate);
//        uint256 interestAmount = unlockCollateralAmount.mul(interestRate).div(MAX_INTEREST_RATE);
//
//        return (
//            interestRate,
//            interestAmount.mul(exchangeRate).div(EXCHANGE_RATE),
//            userShare[user].amount.sub(interestAmount)
//        );
//    }

    function getDepositedAmount(address user) public view returns (uint256) {
        return lenderDepositAmount[user];
    }

    function getMaxBorrowAmount(address user) public view returns (uint256) {
        return fund.getRemainShare(user).mul(ltvRate).div(MAX_LTV_RATE);
    }

    function getExpectedCollateralAmount(uint256 amount) public view returns (
        uint256, uint256
    ) {
        uint256 expectedCollateralAmount = amount.mul(MAX_LTV_RATE).div(ltvRate);
        uint256 interestAmount = expectedCollateralAmount.mul(interestRate).div(MAX_INTEREST_RATE);

        return (expectedCollateralAmount, interestAmount);
    }

    function isFilled () private view returns (bool) {
        return (maxTotalAllocation == totalLockedDepositAmount);
    }

    function deposit (uint256 amount) public {
        address sender = msg.sender;
        uint256 remainAllocation = maxTotalAllocation.sub(totalLockedDepositAmount);
        uint256 remainUserAllocation = maxUserAllocation.sub(lenderDepositAmount[sender]);
        require(!isFilled(), "exceed max allocation");
        require(remainUserAllocation > 0, "exceed max user allocation");
        require(lendToken.allowance(tx.origin, address(this)) >= amount, "insufficient");
        uint256 actualAmount = remainAllocation >= amount ? amount : remainAllocation;
        actualAmount = remainUserAllocation >= actualAmount ? actualAmount : remainUserAllocation;

        lendToken.safeTransferFrom(sender, address(this), actualAmount);

        if (lenderDepositAmount[sender] == 0) {
            totalLender = uint32(totalLender.add(1));
        }
        lenderDepositAmount[sender] = lenderDepositAmount[sender].add(actualAmount);
        totalLockedDepositAmount = totalLockedDepositAmount.add(actualAmount);
        totalCurrentDepositAmount = totalLockedDepositAmount;
        totalRemainDepositAmountAfterDistribution = totalCurrentDepositAmount;

        emit Deposit(
            sender, actualAmount, lenderDepositAmount[sender]
        );
    }

    function withdraw () public {
        // Todo: withdraw 가능한 시점인 지 체크 (IDO 종료이후)
        // Todo: 현재 예치한 금액 체크
        // Todo: 남은 share 할 금액이 있는 지 체크
        address sender = msg.sender;
        uint256 depositAmount = lenderDepositAmount[sender];
        uint256 lenderDepositPercent = depositAmount.mul(MAX_PERCENT_RATE).div(totalLockedDepositAmount);
        uint256 returnDepositAmount = totalCurrentDepositAmount.mul(lenderDepositPercent).div(MAX_PERCENT_RATE);
        fund.lenderClaim(sender, lenderDepositPercent, MAX_PERCENT_RATE);
        lendToken.safeTransfer(sender, returnDepositAmount);

        totalRemainDepositAmountAfterDistribution = totalRemainDepositAmountAfterDistribution.sub(returnDepositAmount);
        lenderDepositAmount[sender] = 0;

        emit Withdraw(sender, returnDepositAmount);
    }

    function borrow (uint256 amount) public {
        // Todo: 현재 deposit amount 가 충분한 지 체크
        address sender = msg.sender;
        uint256 additionalCollateralAmount = amount.mul(MAX_LTV_RATE).div(ltvRate);
        fund.increaseCollateral(sender, additionalCollateralAmount);
        lendToken.safeTransfer(sender, amount);

        totalCurrentDepositAmount = totalCurrentDepositAmount.sub(amount);
        totalRemainDepositAmountAfterDistribution = totalCurrentDepositAmount;

        emit Borrow(sender, amount);
    }

    function repay (uint amount) public {
        // Todo: 기간 체크
        require(lendToken.allowance(msg.sender, address(this)) >= amount, "insufficient token amount");
        address sender = msg.sender;
        uint256 unlockCollateralAmount = amount.mul(MAX_LTV_RATE).div(ltvRate);
        uint256 interestAmount = unlockCollateralAmount.mul(interestRate).div(MAX_INTEREST_RATE);
        fund.decreaseCollateral(sender, interestAmount, unlockCollateralAmount);
        lendToken.transferFrom(sender, address(this), amount);

        totalCurrentDepositAmount = totalCurrentDepositAmount.add(amount);
        totalRemainDepositAmountAfterDistribution = totalCurrentDepositAmount;

        emit Repay(sender, amount, interestAmount);
    }
}