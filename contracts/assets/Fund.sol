// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeMath} from '@openzeppelin/contracts/utils/math/SafeMath.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IStake} from "./Stake.sol";
import {Operator} from '../access/Operator.sol';

import "hardhat/console.sol";

// contract 에서는 erc token 의 decimals 에 대해서 고려하지 않는다. (호출자 책임)


interface IFund {
    function transferOwnership(address newOwner) external;
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
    uint32 constant EXCHANGE_RATE = 10 ** 6;

    Period public fundPeriod;
    uint256 public releaseTime;

    IERC20 public saleToken;
    IERC20 public exchangeToken;
    IStake public stakeContract;

    // target amount to get exchange token
    uint256 public targetAmount;
    uint256 exchangeRate;
    uint256 public userMinFundingAmount;
    uint256 public userMaxFundingAmount;
    address public treasuryAddress;

    // expressed to six decimal places. e.g. exchange_rate 1 means 0.000001
    mapping (address => FundInfo) public userFundInfo;

    uint32 public totalBacker;
    uint256 public totalFundedAmount;

    modifier onPeriod () {
        require(
            fundPeriod.startTime <= block.timestamp && block.timestamp < fundPeriod.periodFinish,
            "not on funding period"
        );
        _;
    }

    constructor (
        address _treasuryAddress,
        address exchangeTokenAddress,
        address stakeAddress
    ) Operator() {
        treasuryAddress = _treasuryAddress;
        exchangeToken = IERC20(exchangeTokenAddress);
        stakeContract = IStake(stakeAddress);
    }

    function setSaleToken (
        address _saleTokenAddress,
        address _senderAddress,
        uint256 _targetAmount,
        uint256 _exchangeRate,
        uint256 _userMinFundingAmount,
        uint256 _userMaxFundingAmount
    ) public onlyOwner {
        saleToken = IERC20(_saleTokenAddress);
        targetAmount = _targetAmount;
        exchangeRate = _exchangeRate;
        userMinFundingAmount = _userMinFundingAmount;
        userMaxFundingAmount = _userMaxFundingAmount;

        uint256 totalSaleTokenAmount = _targetAmount.mul(_exchangeRate).div(EXCHANGE_RATE);
        saleToken.safeTransferFrom(_senderAddress, address(this), totalSaleTokenAmount);
    }

    function setPeriod (uint256 _fundStartTime, uint256 _fundingPeriod, uint256 _releaseTime)
        public
        onlyOwner
    {
        fundPeriod.period = _fundingPeriod;
        fundPeriod.startTime = _fundStartTime;
        fundPeriod.periodFinish = _fundStartTime.add(_fundingPeriod);
        releaseTime = _releaseTime;
    }

    // -------------------- public getters -----------------------
    function getTotalSaleTokenAmount() public view returns (uint256) {
        return targetAmount.mul(_exchangeRate).div(EXCHANGE_RATE);
    }

    function getTargetAmount() public view returns (uint256) {
        return targetAmount;
    }

    function getExpectedExchangeAmount (uint256 amount) public view returns (uint256) {
        return amount.mul(exchangeRate).div(EXCHANGE_RATE);
    }

    function getFundedAmount (address user) public view returns (uint256) {
        return userFundInfo[user].amount;
    }

    function getClaimedAmount (address user) public view returns (uint256) {
        if (userFundInfo[user].isClaimed == false) {
            return 0;
        }
        return userFundInfo[user].mul(exchangeRate).div(EXCHANGE_RATE);
    }

    function fund (uint256 amount) public onPeriod {
        // Todo: Whitelist
        require(userFundInfo[msg.sender].amount == 0, "already funded");
        require(amount >= userMaxFundingAmount, "under min allocation");
        require(amount <= userMinFundingAmount, "exceed max allocation");
        require(stakeContract.isSatisfied(msg.sender), "dissatisfy stake conditions");
        require(totalFundedAmount <= targetAmount, "funding has been finished");
        uint256 availableAmount = _getAvailableAmount(amount);

        // if lock up period is exist, do not swap.
        _fund(availableAmount);

        if (block.timestamp >= releaseTime) {
            _claim();
        }
    }
    function _getAvailableAmount (uint256 amount) private returns (uint256) {
        uint256 remainAmount = targetAmount.sub(totalFundedAmount);
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
