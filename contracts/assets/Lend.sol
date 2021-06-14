// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeMath} from '@openzeppelin/contracts/utils/math/SafeMath.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {Fund, IFund} from "../Fund.sol";
import {Operator} from '../access/Operator.sol';
import "hardhat/console.sol";


contract Lend is Operator {
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

    enum Phase { Deposit, Borrow }
    struct Period {
        uint256 period;
        uint256 periodFinish;
        uint256 startTime;
    }
    mapping (Phase => Period) public phasePeriod;

    uint32 constant MAX_LTV_RATE = 10000;
    uint32 constant MAX_INTEREST_RATE = 10000;
    uint256 constant MAX_PERCENT_RATE = 1e18;

    mapping (address => uint256) lenderDepositAmount;

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

    modifier onPeriod (Phase phase) {
        require(
            phasePeriod[phase].startTime <= block.timestamp && block.timestamp < phasePeriod[phase].periodFinish,
            "invalid period"
        );
        _;
    }

    modifier isFilled () {
        require(
            maxTotalAllocation > totalLockedDepositAmount, "exceed max allocation"
        );
        _;
    }

    constructor (
        address _fundAddress,
        address _lendTokenAddress,
        uint256 _maxTotalAllocation,
        uint256 _maxUserAllocation,
        uint256 _ltvRate,
        uint256 _interestRate
    ) Operator() {
        // Todo: sale amount 를 받아서 maxAllocation 설정하기
        fund = IFund(_fundAddress);
        lendToken = IERC20(_lendTokenAddress);
        maxTotalAllocation = _maxTotalAllocation;
        maxUserAllocation = _maxUserAllocation;
        ltvRate = _ltvRate;
        interestRate = _interestRate;
    }

    function setPeriod (Phase _phase, uint256 _startTime, uint256 _period)
        public
        onlyOwner
    {
        // Todo: if period has been passed, revert
        Period storage period = phasePeriod[_phase];
        period.period = _period;
        period.startTime = _startTime;
        period.periodFinish = _startTime.add(_period);
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

    function deposit (uint256 amount) public onPeriod(Phase.Deposit) isFilled() {
        address sender = msg.sender;
        uint256 actualAmount = _getActualDepositAmount(sender, amount);

        lendToken.safeTransferFrom(sender, address(this), actualAmount);
        _updateDepositInfo(sender, actualAmount);

        emit Deposit(
            sender, actualAmount, lenderDepositAmount[sender]
        );
    }

    function _getActualDepositAmount (address sender, uint256 amount) private view returns (uint256) {
        uint256 remainAllocation = maxTotalAllocation.sub(totalLockedDepositAmount);
        uint256 remainUserAllocation = maxUserAllocation.sub(lenderDepositAmount[sender]);

        require(remainUserAllocation > 0, "exceed max user allocation");
        require(lendToken.allowance(sender, address(this)) >= amount, "insufficient");
        uint256 actualAmount = remainAllocation >= amount ? amount : remainAllocation;
        actualAmount = remainUserAllocation >= actualAmount ? actualAmount : remainUserAllocation;

        return actualAmount;
    }

    function _updateDepositInfo(address sender, uint256 actualAmount) private {
        lenderDepositAmount[sender] = lenderDepositAmount[sender].add(actualAmount);

        if (lenderDepositAmount[sender] == 0) {
            totalLender = uint32(totalLender.add(1));
        }
        totalLockedDepositAmount = totalLockedDepositAmount.add(actualAmount);
        totalCurrentDepositAmount = totalLockedDepositAmount;
        totalRemainDepositAmountAfterDistribution = totalCurrentDepositAmount;
    }

    function withdraw () public {
        require(
            phasePeriod[Phase.Borrow].periodFinish > block.timestamp, "can not withdraw on borrow phase"
        );
        require(lenderDepositAmount[msg.sender] > 0, "no token to withdraw");
        address sender = msg.sender;
        (uint256 lenderDepositPercent, uint256 returnDepositAmount) = _getReturnAmountByDepositPercent(sender);
        lenderDepositAmount[sender] = 0;
        fund.lenderClaim(sender, lenderDepositPercent, MAX_PERCENT_RATE);
        lendToken.safeTransfer(sender, returnDepositAmount);

        totalRemainDepositAmountAfterDistribution = totalRemainDepositAmountAfterDistribution.sub(returnDepositAmount);

        emit Withdraw(sender, returnDepositAmount);
    }

    function _getReturnAmountByDepositPercent (address sender) private view returns (uint256, uint256) {
        uint256 lenderDepositPercent = lenderDepositAmount[sender].mul(MAX_PERCENT_RATE).div(totalLockedDepositAmount);
        uint256 returnDepositAmount = totalCurrentDepositAmount.mul(lenderDepositPercent).div(MAX_PERCENT_RATE);

        return (lenderDepositPercent, returnDepositAmount);
    }


    function borrow (uint256 amount) public onPeriod(Phase.Borrow) {
        // Todo: 현재 deposit amount 가 충분한 지 체크
        address sender = msg.sender;
        uint256 additionalCollateralAmount = amount.mul(MAX_LTV_RATE).div(ltvRate);
        fund.increaseCollateral(sender, additionalCollateralAmount);
        lendToken.safeTransfer(sender, amount);

        totalCurrentDepositAmount = totalCurrentDepositAmount.sub(amount);
        totalRemainDepositAmountAfterDistribution = totalCurrentDepositAmount;

        emit Borrow(sender, amount);
    }

    function repay (uint amount) public onPeriod(Phase.Borrow) {
        require(lendToken.allowance(msg.sender, address(this)) >= amount, "insufficient token amount");
        address sender = msg.sender;
        uint256 unlockCollateralAmount = amount.mul(MAX_LTV_RATE).div(ltvRate);
        uint256 interestAmount = unlockCollateralAmount.mul(interestRate).div(MAX_INTEREST_RATE);
        fund.decreaseCollateral(sender, interestAmount, unlockCollateralAmount);
        lendToken.safeTransferFrom(sender, address(this), amount);

        totalCurrentDepositAmount = totalCurrentDepositAmount.add(amount);
        totalRemainDepositAmountAfterDistribution = totalCurrentDepositAmount;

        emit Repay(sender, amount, interestAmount);
    }
}
