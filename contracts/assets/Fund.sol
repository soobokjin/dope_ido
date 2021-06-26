// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeMath} from '@openzeppelin/contracts/utils/math/SafeMath.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {Initializable} from '@openzeppelin/contracts/proxy/utils/Initializable.sol';
import {IStake} from "./Stake.sol";
import {Operator} from '../access/Operator.sol';

import "hardhat/console.sol";

// contract 에서는 erc token 의 decimals 에 대해서 고려하지 않는다. (호출자 책임)


interface IFund {
    function initialize (bytes memory args) external;
    function initPayload (
        address _saleTokenAddress,
        address exchangeTokenAddress,
        address stakeAddress,
        address _treasuryAddress
    ) external pure returns (bytes memory);
    function fund (uint256 amount) external;
}


contract Fund is IFund, Operator, Initializable {
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
        uint256 claimedAmount;
    }
    uint256 constant EXCHANGE_RATE = 10 ** 6;

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

    uint256 public totalFundedAmount;

    modifier onPeriod () {
        require(
            fundPeriod.startTime <= block.timestamp && block.timestamp < fundPeriod.periodFinish,
            "not on funding period"
        );
        _;
    }

    function initialize (
        bytes memory args
    ) public override initializer {
        (
            address _saleTokenAddress,
            address _exchangeTokenAddress,
            address _stakeAddress,
            address _treasuryAddress
        ) = abi.decode(args, (address, address, address, address));

        saleToken = IERC20(_saleTokenAddress);
        exchangeToken = IERC20(_exchangeTokenAddress);
        stakeContract = IStake(_stakeAddress);
        treasuryAddress = _treasuryAddress;

        setRole(_msgSender(), _msgSender());
    }

    function initPayload (
        address _saleTokenAddress,
        address _exchangeTokenAddress,
        address _stakeAddress,
        address _treasuryAddress
    ) public pure override returns (bytes memory) {
        return abi.encode(
            _saleTokenAddress,
            _exchangeTokenAddress,
            _stakeAddress,
            _treasuryAddress
        );
    }

    function setSaleToken (
        address _senderAddress,
        uint256 _targetAmount,
        uint256 _exchangeRate,
        uint256 _userMinFundingAmount,
        uint256 _userMaxFundingAmount
    ) public onlyOwner {
        // targetAmount is dollar (not sale token amount)
        targetAmount = _targetAmount;
        exchangeRate = _exchangeRate;
        userMinFundingAmount = _userMinFundingAmount;
        userMaxFundingAmount = _userMaxFundingAmount;

        uint256 totalSaleTokenAmount = targetAmount.mul(exchangeRate).div(EXCHANGE_RATE);
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
        return targetAmount.mul(exchangeRate).div(EXCHANGE_RATE);
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
        if (userFundInfo[user].claimedAmount == 0) {
            return 0;
        }
        return userFundInfo[user].claimedAmount.mul(exchangeRate).div(EXCHANGE_RATE);
    }

    function fund (uint256 amount) public override onPeriod {
        // Todo: Whitelist
        FundInfo memory _info = userFundInfo[_msgSender()];
        require(targetAmount > 0, "FUND: sale token is not set");
        require(totalFundedAmount <= targetAmount, "FUND: funding has been finished");
        require(amount >= userMinFundingAmount, "FUND: under min allocation");
        require(stakeContract.isSatisfied(_msgSender()), "FUND: dissatisfy stake conditions");
        require(_info.amount.add(amount) <= userMaxFundingAmount, "FUND: exceed amount");
        uint256 availableAmount = _getAvailableAmount(amount);

        // if lock up period is exist, do not swap.
        _fund(_info, availableAmount);

        if (block.timestamp >= releaseTime) {
            _claim(_info);
        }
    }
    function _getAvailableAmount (uint256 amount) internal view returns (uint256) {
        uint256 remainAmount = targetAmount.sub(totalFundedAmount);
        return remainAmount >= amount ? amount : remainAmount;
}
    function _fund (FundInfo memory _info, uint256 amount) internal {
        // Todo: token fallback
        _info.amount = _info.amount.add(amount);
        totalFundedAmount = totalFundedAmount.add(amount);
        userFundInfo[_msgSender()] = _info;

        exchangeToken.safeTransferFrom(_msgSender(), treasuryAddress, amount);

        emit Funded(_msgSender(), amount);
    }
    function claim () public {
        FundInfo memory _info = userFundInfo[_msgSender()];
        require(releaseTime <= block.timestamp, "token is not released");
        require(_info.amount.sub(_info.claimedAmount) > 0, "already claimed");

        _claim(_info);
    }

    function _claim (FundInfo memory _info) internal {
        uint256 claimAmount = _info.amount.sub(_info.claimedAmount);
        _info.claimedAmount = _info.claimedAmount.add(claimAmount);
        userFundInfo[_msgSender()] = _info;

        uint256 swapAmount = claimAmount.mul(exchangeRate).div(EXCHANGE_RATE);
        saleToken.safeTransfer(_msgSender(), swapAmount);

        emit Claimed(_msgSender(), swapAmount);
    }
}
