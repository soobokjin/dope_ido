pragma solidity ^0.8.0;

import {ERC20} from './ERC20.sol';
import {IERC20} from './IERC20.sol';

/*
saleTokenName
saleTokenAddress
saleTokenAmount
exchangeTokenAddress
treasuryAddress
loanRate
loanPenaltyRate
whiteList
*/

struct Period {
    uint startIDOBlockNum;
    uint startSwapBlockNum;
    uint endSwapBlockNum;
    uint startDepositLoanBlockNum;
    uint endDepositLoanBlockNum;
    uint endIDOBlockNum;
}

contract IDOPlatform {

    address[] private _admins;
    string public saleTokenName;
    address public saleTokenAddress;
    uint public saleTokenAmount;

    address public exchangeTokenAddress;

    address public treasuryAddress;

    address public stakeTokenAddress;
    mapping (address => uint[]) userStakeChangedBlockNums;
    mapping (address => mapping (uint256 => uint256)) userStakeAmountByBlockNum;

    period public idoPeriod;

    constructor (
        string _saleTokenName,
        address _saleTokenAddress,
        uint _saleTokenAmount,
        address _exchangeTokenAddress,
        address _treasuryAddress,
        address _stakeTokenAddress
    ) {
        _admins.push(msg.sender);

        saleTokenName = _saleTokenName;
        saleTokenAddress = _saleTokenAddress;
        saleTokenAmount = _saleTokenAmount;
        exchangeTokenAddress = _exchangeTokenAddress;
        treasuryAddress = _treasuryAddress;
        stakeTokenAddress = _stakeTokenAddress;
    }

    function setPeriods (
        uint _startIDOBlockNum,
        uint _startSwapBlockNum,
        uint _endSwapBlockNum,
        uint _startDepositLoanBlockNum,
        uint _endDepositLoanBlockNum,
        uint _endIDOBlockNum
    ) public virtual returns (bool) {
        // Todo: validate all numbers
        // Todo: only owner can set the period
        idoPeriod = period(
            _startIDOBlockNum,
            _startSwapBlockNum,
            _endSwapBlockNum,
            _startDepositLoanBlockNum,
            _endDepositLoanBlockNum,
            _endIDOBlockNum
        );
        return true;
    }

    function stake (uint amount) {
        require(amount > 0, "invalid amount. should be positive value");
        // Todo: 최소 lockup 개수 체크
        // Todo: amount 만큼 가져올 수 있는 지 체크
        IERC20 token = IERC20(stakeTokenAddress);
        require(token.allowance(msg.sender, address(this)) >= amount, "불 충분한 token 개수");
        uint256 historyLength = userStakeChangedBlockNums[sender].length;
        uint256 blockNumber = block.number;
        address sender = msg.sender;

        // transfer
        token.transferFrom(msg.sender, address(this), amount);
        // record stake history
        if (historyLength == 0) {
            userStakeChangedBlockNums[sender].push(blockNumber);
            userStakeAmount[sender][blockNumber] = amount;
        }
        else {
            uint256 lastChangedBlockNumber = userStakeChangedBlockNums[sender][historyLength - 1];
            uint256 lastStakedAmount = userStakeAmount[sender][lastChangedBlockNumber];
            userStakeChangedBlockNums[sender].push(blockNumber);
            userStakeAmount[sender][blockNumber] += lastStakedAmount + amount;
        }
    }

    function unStake (uint amount) {
        require(amount > 0, "invalid amount. should be positive value");
        require(userStakeChangedBlockNums[sender].length > 0, "stake amount is 0");
        // Todo: amount 가 stake 량보다 작은 지 체크
        IERC20 token = IERC20(stakeTokenAddress);
        uint256 blockNumber = block.number;
        address sender = msg.sender;
        uint256 historyLength = userStakeChangedBlockNums[sender].length;
        uint256 lastChangedBlockNumber = userStakeChangedBlockNums[sender][historyLength - 1];
        uint256 stakedAmount = userStakeAmountByBlockNum[sender][lastChangedBlockNumber];
        require(stakedAmount >= amount, "invalid amount. stakedAmount < amount");

        token.transfer(msg.sender, amount);
        userStakeChangedBlockNums[sender].push(blockNumber);
        userStakeAmountByBlockNum[sender][blockNumber] = stakedAmount - amount;
    }
}


