pragma solidity ^0.8.0;

import {SafeMath} from '@openzeppelin/contracts/utils/math/SafeMath.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {Context, Ownable} from '@openzeppelin/contracts/access/Ownable.sol';


interface IStake {
    function stake (uint256 amount) external;
    function unStake (uint256 amount) external;
    function isSatisfied (uint256 startBlockNum, uint256 endBlockNum) external returns (bool);
    function getCurrentStakeAmountOf (address user) external view returns (uint256);
}


contract Stake is Context, Ownable {
    // Todo: Contract operator migration (DOPE 가 가지도록)
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using SafeMath for uint32;
    using SafeMath for uint8;

    event Staked(
        address indexed user,
        uint256 stakeAmount,
        uint256 totalStakedAmount,
        uint256 blockNumber
    );

    event UnStaked(
        address indexed user,
        uint256 unStakeAmount,
        uint256 totalStakedAmount,
        uint256 blockNumber
    );

    IERC20 public stakeToken;
    uint32 public minRetentionPeriod;
    uint256 public minStakeAmount;

    mapping(address => uint[]) userStakeChangedBlockNums;
    mapping(address => mapping(uint256 => uint256)) userStakeAmountByBlockNum;

    constructor (
        address _stakeTokenAddress,
        uint256 _minStakeAmount,
        uint32 _minRetentionPeriod
    ) {

        stakeToken = IERC20(_stakeTokenAddress);
        minStakeAmount = _minStakeAmount;
        minRetentionPeriod = _minRetentionPeriod;
    }

    function getCurrentStakeAmountOf (address user) public view returns (uint256) {
        uint256 length = userStakeChangedBlockNums[user].length;
        if (length == 0) {
            return 0;
        }
        uint256 lastBlockNumber = userStakeChangedBlockNums[user][length - 1];
        return userStakeAmountByBlockNum[user][lastBlockNumber];
    }

    function stake(uint256 amount) external {
        require(stakeToken.allowance(tx.origin, address(this)) >= amount, "insufficient allowance.");
        address sender = tx.origin;
        uint256 historyLength = userStakeChangedBlockNums[sender].length;
        uint256 blockNumber = block.number;

        stakeToken.safeTransferFrom(sender, address(this), amount);
        if (historyLength == 0) {
            userStakeChangedBlockNums[sender].push(blockNumber);
            userStakeAmountByBlockNum[sender][blockNumber] = amount;
        }
        else {
            uint256 lastChangedBlockNumber = userStakeChangedBlockNums[sender][historyLength.sub(1)];
            uint256 lastStakedAmount = userStakeAmountByBlockNum[sender][lastChangedBlockNumber];
            userStakeChangedBlockNums[sender].push(blockNumber);
            userStakeAmountByBlockNum[sender][blockNumber] = lastStakedAmount.add(amount);
        }

        emit Staked(
            msg.sender, amount, userStakeAmountByBlockNum[sender][blockNumber], blockNumber
        );
    }

    function unStake (uint256 amount) external {
        require(userStakeChangedBlockNums[tx.origin].length > 0, "stake amount is 0");
        address sender = tx.origin;
        uint256 blockNumber = block.number;
        uint256 historyLength = userStakeChangedBlockNums[sender].length;
        uint256 lastChangedBlockNumber = userStakeChangedBlockNums[sender][historyLength.sub(1)];
        uint256 stakedAmount = userStakeAmountByBlockNum[sender][lastChangedBlockNumber];
        require(stakedAmount >= amount, "invalid amount. stakedAmount < amount");

        stakeToken.safeTransfer(sender, amount);
        userStakeChangedBlockNums[sender].push(blockNumber);
        userStakeAmountByBlockNum[sender][blockNumber] = stakedAmount.sub(amount);

        emit UnStaked(
            msg.sender, amount, userStakeAmountByBlockNum[sender][blockNumber], blockNumber
        );
    }

    function isSatisfied (uint256 startBlockNum, uint256 endBlockNum) external returns (bool) {
        // start >=, end <
        if (userStakeChangedBlockNums[tx.origin].length == 0) {
            return false;
        }
        // 한번도 stake 한 적이 없는 경우 false return
        address sender = tx.origin;
        uint256 satisfiedPeriod;
        uint256 stakeAmount;
        uint256 changedBlockNum;
        uint256 changedStakeAmount;
        uint256 prevBlockNum = startBlockNum;

        // Todo: 기간 이전에 stake 하는 경우 반영
        for (uint8 i ; i < userStakeChangedBlockNums[sender].length ; i++) {
            changedBlockNum = userStakeChangedBlockNums[sender][i];
            changedStakeAmount = userStakeAmountByBlockNum[sender][changedBlockNum];
            satisfiedPeriod = stakeAmount >= minStakeAmount ? satisfiedPeriod.add(endBlockNum.sub(changedBlockNum)): 0;
            stakeAmount = changedStakeAmount;
            prevBlockNum = changedBlockNum;
        }
        satisfiedPeriod = stakeAmount >= minStakeAmount ? satisfiedPeriod.add(endBlockNum.sub(changedBlockNum)): 0;

        return (satisfiedPeriod >= minRetentionPeriod) ? true: false;
    }
}
