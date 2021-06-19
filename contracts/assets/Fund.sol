// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeMath} from '@openzeppelin/contracts/utils/math/SafeMath.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IStake} from "./Stake.sol";
import {Operator} from '../access/Operator.sol';

import "hardhat/console.sol";

// contract 에서는 erc token 의 decimals 에 대해서 고려하지 않는다. (호출자 책임)
// Todo: initializing DOPE
// Todo: modifier, require


interface IFund {
    function fund (uint256 amount) external;
}


contract Fund is IFund, Operator {
    using SafeMath for uint;
    using SafeMath for uint32;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    event Funded(
        address indexed user,
        uint256 amount
    );

    event Claimed(
        address indexed user,
        uint256 amount
    );

    struct Period {
        uint256 period;
        uint256 periodFinish;
        uint256 startTime;
    }

    struct FundInfo {
        uint256 amount;
        bool isClaimed;
    }

    Period public fundPeriod;
    uint256 public releaseTime;

    // expressed to six decimal places. e.g. exchange_rate 1 means 0.000001
    uint32 constant EXCHANGE_RATE = 10 ** 6;

    address public saleTokenAddress;
    address public treasuryAddress;
    uint256 exchangeRate;
    uint256 public saleTokenAmount;
    uint256 public totalFundedAmount;

    uint32 public totalBacker;
    uint256 public minUserFundingAmount;
    uint256 public maxUserFundingAmount;
    mapping (address => FundInfo) public userFundInfo;

    IERC20 public saleToken;
    IERC20 public exchangeToken;
    IStake public stakeContract;

    modifier onPeriod () {
        require(
            fundPeriod.startTime <= block.timestamp && block.timestamp < fundPeriod.periodFinish,
            "not on funding period"
        );
        _;
    }

    constructor (
        address exchangeTokenAddress,
        address treasuryAddress,
        address stakeAddress
    ) Operator() {
        // Todo: 설정 변경이 가능한 기간?
        treasuryAddress = treasuryAddress;
        exchangeToken = IERC20(exchangeTokenAddress);
        stakeContract = IStake(stakeAddress);
    }

    function setPeriod (uint256 startTime, uint256 period)
        public
        onlyOwner
    {
        fundPeriod.period = period;
        fundPeriod.startTime = startTime;
        fundPeriod.periodFinish = startTime.add(period);
    }

    function setReleaseTime (uint256 _releaseTime) public onlyOwner {
        releaseTime = _releaseTime;
    }

    function setSaleToken (
        address _saleTokenAddress,
        uint256 _saleTokenAmount,
        uint256 _maxUserFundingAllocation,
        uint256 _exchangeRate
    ) public onlyOwner {
        // Todo: fallback
        saleToken = IERC20(_saleTokenAddress);
        saleToken.safeTransferFrom(treasuryAddress, address(this), saleTokenAmount);
        saleTokenAddress = _saleTokenAddress;
        saleTokenAmount = _saleTokenAmount;

        maxUserFundingAmount = _maxUserFundingAllocation;
        exchangeRate = _exchangeRate;
    }

    // -------------------- public getters -----------------------
    function getTargetFundingAmount() public view returns (uint256) {
        return saleTokenAmount.mul(EXCHANGE_RATE).div(exchangeRate);
    }

    function getExpectedExchangeAmount (uint256 amount) public view returns (uint256) {
        return amount.mul(exchangeRate).div(EXCHANGE_RATE);
    }

    function getFundedAmount (address user) public view returns (uint256) {
        return userFundInfo[user].amount;
    }

    function fund (uint256 amount) public onPeriod {
        // Todo: Whitelist
        // Todo: Check if lock up period is need
        require(userFundInfo[msg.sender].amount == 0, "already funded");
        require(amount >= minUserFundingAmount, "under min allocation");
        require(amount <= maxUserFundingAmount, "exceed max allocation");
        require(stakeContract.isSatisfied(msg.sender), "dissatisfy stake conditions");
        require(totalFundedAmount <= saleTokenAmount, "fund is finished");
        uint256 availableAmount = _getAvailableAmount(amount);

        // if lock up period is exist, do not swap.
        _fund(availableAmount);

        if (block.timestamp >= releaseTime) {
            _claim();
        }
    }
    function _getAvailableAmount (uint256 amount) private returns (uint256) {
        uint256 remainAmount = saleTokenAmount.sub(totalFundedAmount);
        return remainAmount >= amount ? amount : remainAmount;
}
    function _fund (uint256 amount) private {
        userFundInfo[msg.sender].amount = userFundInfo[msg.sender].amount.add(amount);
        exchangeToken.safeTransferFrom(msg.sender, treasuryAddress, amount);

        totalFundedAmount = totalFundedAmount.add(amount);
        totalBacker = uint32(totalBacker.add(1));

        emit Funded(msg.sender, amount);
    }
    function claim () public {
        require(releaseTime >= block.timestamp, "token is not released");
        require(userFundInfo[msg.sender].isClaimed == false, "already claimed");
        _claim();
    }

    function _claim () private {
        uint256 amount = userFundInfo[msg.sender].amount;
        userFundInfo[msg.sender].isClaimed = true;

        uint256 swapAmount = amount.mul(exchangeRate).div(EXCHANGE_RATE);
        saleToken.safeTransfer(sender, swapAmount);

        emit Claimed(sender, swapAmount);
    }
}
