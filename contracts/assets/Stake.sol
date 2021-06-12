pragma solidity ^0.8.0;

import {SafeMath} from '@openzeppelin/contracts/utils/math/SafeMath.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {Context, Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {Operator} from '../access/Operator.sol';

import "hardhat/console.sol";


interface IStake {
    function isSatisfied (address user) external returns (bool);
}


contract Stake is Operator {
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
    uint32 public minRetentionPeriod;
    uint256 public minStakeAmount;

    mapping(address => uint[]) userStakeChangedBlockTime;
    mapping(address => mapping(uint256 => uint256)) userStakeAmountByBlockTime;

    Period public stakePeriod;

    constructor (
        address _stakeTokenAddress,
        uint256 _minStakeAmount,
        uint32 _minRetentionPeriod
    ) Operator() {
        stakeToken = IERC20(_stakeTokenAddress);
        minStakeAmount = _minStakeAmount;
        // Timestamp
        minRetentionPeriod = _minRetentionPeriod;
    }

    function setPeriod (uint256 _startTime, uint256 _period)
        public
        override
        onlyOperator
    {
        stakePeriod.period = _period;
        stakePeriod.startTime = _startTime;
        stakePeriod.periodFinish = _startTime.add(_period);
    }

    modifier onPeriod () {
        require(
            stakePeriod.startTime <= block.timestamp && block.timestamp < stakePeriod.periodFinish,
            "not stake period"
        );
        _;
    }

    function setMinStakeAmount (uint256 amount) public onlyOwner {
        minStakeAmount = amount;
    }

    function setMinRetentionPeriod (uint32 period) public onlyOwner {
        minRetentionPeriod = period;
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
        require(stakeToken.allowance(_msgSender(), address(this)) >= amount, "insufficient allowance.");
        require(amount >= minStakeAmount, "insufficient amount");
        address sender = _msgSender();
        uint256 historyLength = userStakeChangedBlockTime[sender].length;
        uint256 blockTime = block.timestamp;

        stakeToken.safeTransferFrom(sender, address(this), amount);
        if (historyLength == 0) {
            userStakeChangedBlockTime[sender].push(blockTime);
            userStakeAmountByBlockTime[sender][blockTime] = amount;
        }
        else {
            uint256 lastChangedBlockTime = userStakeChangedBlockTime[sender][historyLength.sub(1)];
            uint256 lastStakedAmount = userStakeAmountByBlockTime[sender][lastChangedBlockTime];
            userStakeChangedBlockTime[sender].push(blockTime);
            userStakeAmountByBlockTime[sender][blockTime] = lastStakedAmount.add(amount);
        }

        emit Staked(
            msg.sender, amount, userStakeAmountByBlockTime[sender][blockTime], blockTime
        );
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

        stakeToken.safeTransfer(sender, amount);
        userStakeChangedBlockTime[sender].push(blockTime);
        userStakeAmountByBlockTime[sender][blockTime] = stakedAmount.sub(amount);

        emit UnStaked(
            msg.sender, amount, userStakeAmountByBlockTime[sender][blockTime], blockTime
        );
    }

    function isSatisfied (address user) external override view returns (bool) {
        if (userStakeChangedBlockTime[user].length == 0) {
            return false;
        }
        uint256 satisfiedPeriod;
        uint256 stakeAmount;
        uint256 changedBlockTime;
        uint256 changedStakeAmount;
        uint256 prevBlockTime = stakePeriod.startTime;

        for (uint8 i ; i < userStakeChangedBlockTime[user].length ; i++) {
            changedBlockTime = userStakeChangedBlockTime[user][i];
            changedStakeAmount = userStakeAmountByBlockTime[user][changedBlockTime];
            satisfiedPeriod = updateSatisfiedPeriod(stakeAmount, changedBlockTime.sub(prevBlockTime));
            stakeAmount = changedStakeAmount;
            prevBlockTime = changedBlockTime;
        }
        satisfiedPeriod = updateSatisfiedPeriod(stakeAmount, stakePeriod.periodFinish.sub(changedBlockTime));
        return (satisfiedPeriod >= minRetentionPeriod) ? true: false;
    }

    function updateSatisfiedPeriod (uint256 stakeAmount, uint256 retentionPeriod) private returns (uint256) {
        return stakeAmount >= minStakeAmount ? satisfiedPeriod.add(retentionPeriod): 0;
    }
}
