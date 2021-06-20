// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeMath} from '@openzeppelin/contracts/utils/math/SafeMath.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {Context, Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {Initializable} from '@openzeppelin/contracts/proxy/utils/Initializable.sol';
import {Operator} from '../access/Operator.sol';

import "hardhat/console.sol";


interface IStake {
    function initialize (bytes memory args) external;
    function initPayload (
        address _stakeTokenAddress,
        uint256 _minLockupAmount,
        uint256 _requiredStakeAmount,
        uint32 _requiredRetentionPeriod
    ) external view returns (bytes memory);
    function isSatisfied (address user) external returns (bool);
}


contract Stake is IStake, Operator, Initializable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using SafeMath for uint32;
    using SafeMath for uint8;

    event Staked(
        address indexed user,
        uint256 stakeAmount,
        uint256 totalStakedAmount,
        uint256 blockTime
    );

    event UnStaked(
        address indexed user,
        uint256 unStakeAmount,
        uint256 totalStakedAmount,
        uint256 blockTime
    );

    struct Period {
        uint256 period;
        uint256 periodFinish;
        uint256 startTime;
    }

    IERC20 public stakeToken;
    uint32 public requiredRetentionPeriod;
    uint256 public requiredStakeAmount;
    mapping(address => uint[]) userStakeChangedBlockTime;
    mapping(address => mapping(uint256 => uint256)) userStakeAmountByBlockTime;

    uint256 public minLockupAmount;
    Period public stakePeriod;

    modifier onPeriod () {
        require(
            stakePeriod.startTime <= block.timestamp && block.timestamp < stakePeriod.periodFinish,
            "not stake period"
        );
        _;
    }

    function initialize (bytes memory args) public override initializer {
        (
            address _stakeTokenAddress,
            uint256 _minLockupAmount,
            uint256 _requiredStakeAmount,
            uint32 _requiredRetentionPeriod
        ) = abi.decode(args, (address, uint256, uint256, uint32));

        stakeToken = IERC20(_stakeTokenAddress);
        minLockupAmount = _minLockupAmount;
        requiredStakeAmount = _requiredStakeAmount;
        // Timestamp
        requiredRetentionPeriod = _requiredRetentionPeriod;
    }

    function initPayload (
        address _stakeTokenAddress,
        uint256 _minLockupAmount,
        uint256 _requiredStakeAmount,
        uint32 _requiredRetentionPeriod
    ) public view override returns (bytes memory) {
        return abi.encode(
            _stakeTokenAddress,
            _minLockupAmount,
            _requiredStakeAmount,
            _requiredRetentionPeriod
        );
    }

    function setPeriod (uint256 _startTime, uint256 _period)
        public
        onlyOwner
    {
        stakePeriod.period = _period;
        stakePeriod.startTime = _startTime;
        stakePeriod.periodFinish = _startTime.add(_period);
    }

    function setRequiredStakeAmount (uint256 amount) public onlyOwner {
        requiredStakeAmount = amount;
    }

    function setRequiredRetentionPeriod (uint32 period) public onlyOwner {
        requiredRetentionPeriod = period;
    }

    function getCurrentStakeAmount (address user) public view returns (uint256) {
        uint256 length = userStakeChangedBlockTime[user].length;
        if (length == 0) {
            return 0;
        }
        uint256 lastBlockTime = userStakeChangedBlockTime[user][length - 1];
        return userStakeAmountByBlockTime[user][lastBlockTime];
    }

    function stake (uint256 amount) public onPeriod {
        require(stakeToken.allowance(_msgSender(), address(this)) >= amount, "insufficient allowance");
        require(amount >= minLockupAmount, "insufficient amount");
        address sender = _msgSender();
        stakeToken.safeTransferFrom(sender, address(this), amount);
        _updateStakeInfo(sender, amount);

        emit Staked(
            msg.sender, amount, userStakeAmountByBlockTime[sender][block.timestamp], block.timestamp
        );
    }

    function _updateStakeInfo (address sender, uint256 amount) private {
        uint256 historyLength = userStakeChangedBlockTime[sender].length;

        if (historyLength == 0) {
            userStakeChangedBlockTime[sender].push(block.timestamp);
            userStakeAmountByBlockTime[sender][block.timestamp] = amount;
        }
        else {
            uint256 lastChangedBlockTime = userStakeChangedBlockTime[sender][historyLength.sub(1)];
            uint256 lastStakedAmount = userStakeAmountByBlockTime[sender][lastChangedBlockTime];
            userStakeChangedBlockTime[sender].push(block.timestamp);
            userStakeAmountByBlockTime[sender][block.timestamp] = lastStakedAmount.add(amount);
        }
    }

    function unStake (uint256 amount) public {
        // Todo: call unStake when succeed to fund
        require(userStakeChangedBlockTime[_msgSender()].length > 0, "stake amount is 0");
        address sender = _msgSender();
        uint256 blockTime = block.timestamp;
        uint256 historyLength = userStakeChangedBlockTime[sender].length;
        uint256 lastChangedBlockTime = userStakeChangedBlockTime[sender][historyLength.sub(1)];
        uint256 stakedAmount = userStakeAmountByBlockTime[sender][lastChangedBlockTime];
        require(stakedAmount >= amount, "invalid amount. stakedAmount < amount");

        userStakeAmountByBlockTime[sender][blockTime] = stakedAmount.sub(amount);
        userStakeChangedBlockTime[sender].push(blockTime);
        stakeToken.safeTransfer(sender, amount);

        emit UnStaked(
            msg.sender, amount, userStakeAmountByBlockTime[sender][blockTime], blockTime
        );
    }

    function isSatisfied (address user) external view override returns (bool) {
        if (userStakeChangedBlockTime[user].length == 0) {
            return false;
        }
        uint256 satisfiedPeriod;
        uint256 stakeAmount;
        uint256 changedBlockTime;
        uint256 changedStakeAmount;
        uint256 prevBlockTime = stakePeriod.startTime;
        uint256 endBlockTime = (
        stakePeriod.periodFinish > block.timestamp
        ) ? block.timestamp : stakePeriod.periodFinish;

        for (uint8 i ; i < userStakeChangedBlockTime[user].length ; i++) {
            changedBlockTime = userStakeChangedBlockTime[user][i];
            changedStakeAmount = userStakeAmountByBlockTime[user][changedBlockTime];
            satisfiedPeriod = _calcSatisfiedPeriod(stakeAmount, satisfiedPeriod, changedBlockTime.sub(prevBlockTime));
            stakeAmount = changedStakeAmount;
            prevBlockTime = changedBlockTime;
        }
        satisfiedPeriod = _calcSatisfiedPeriod(
            stakeAmount, satisfiedPeriod, endBlockTime.sub(changedBlockTime)
        );
        return (satisfiedPeriod >= requiredRetentionPeriod) ? true: false;
    }

    function _calcSatisfiedPeriod(
        uint256 stakeAmount, uint256 satisfiedPeriod, uint256 retentionPeriod
    ) private view returns (uint256) {
        return stakeAmount >= requiredStakeAmount ? satisfiedPeriod.add(retentionPeriod): 0;
    }
}
