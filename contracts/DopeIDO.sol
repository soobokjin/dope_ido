pragma solidity ^0.8.0;

import {ERC20} from './ERC20.sol';
import {IERC20} from './IERC20.sol';

/*
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

struct Share {
    uint256 amount;
    uint256 collateralAmount;
    bool isSwapped;
}

contract IDOPlatform {

    address[] private _admins;
    string public saleTokenName;
    address public saleTokenAddress;
    uint public saleTokenAmount;

    address public exchangeTokenAddress;
    // Todo: 정수로 소수 계산하도록 하기
    uint256 exchangeRate;
    mapping (address => Share) public userShare;
    uint256 public totalInterest;

    address public treasuryAddress;
    address public stakeTokenAddress;
    mapping (address => uint[]) userStakeChangedBlockNums;
    mapping (address => mapping (uint256 => uint256)) userStakeAmountByBlockNum;

    Period public iDOPeriod;

    constructor (
        string _saleTokenName,
        address _saleTokenAddress,
        uint _saleTokenAmount,
        address _exchangeTokenAddress,
        uint8 _exchangeRate,
        address _treasuryAddress,
        address _stakeTokenAddress
    ) {
        _admins.push(msg.sender);

        saleTokenName = _saleTokenName;
        saleTokenAddress = _saleTokenAddress;
        saleTokenAmount = _saleTokenAmount;
        exchangeTokenAddress = _exchangeTokenAddress;
        exchangeRate = _exchangeRate;
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
        iDOPeriod = period(
            _startIDOBlockNum,
            _startSwapBlockNum,
            _endSwapBlockNum,
            _startDepositLoanBlockNum,
            _endDepositLoanBlockNum,
            _endIDOBlockNum
        );
        return true;
    }

    function stake (uint amount) public virtual {
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

    function unStake (uint amount) public virtual {
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

    function acquireShareOfSaleToken (uint amount) public virtual {
        // Todo: 한 개인이 최대 구매가능한 수량 한정하기
        // Todo: swap 가능한 시기인 지 체크
        // Todo: stake 조건 체크
        // Todo: whitelist 여부 체크

        ERC20 fromToken = ERC20(exchangeTokenAddress);
        fromToken.transferFrom(msg.sender, treasuryAddress, amount);
        userShare[msg.sender] = Share(amount, 0);
    }

    function claimSaleToken () public virtual {
        // Todo: swap 가능한 시기인 지 체크
        // Todo: 이미 swap 했는 지 체크
        Share _share = userShare[msg.sender];
        uint finalShare = _share.amount - _share.collateralAmount;
        // Todo: solidity 의 percent 처리 확인하기
        uint swapAmount = (finalShare * exchangeRate) / 10000;

        IERC20(saleTokenAddress).transfer(msg.sender, swapAmount);
        _share.isSwapped = true;
    }




}


