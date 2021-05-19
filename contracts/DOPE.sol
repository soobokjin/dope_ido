pragma solidity ^0.8.0;

import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';

/*
loanRate
loanPenaltyRate
whiteList
*/

// contract 에서는 erc token 의 decimals 에 대해서 고려하지 않는다. (호출자 책임)

// Todo: code refactoring
// Todo: method define
// Todo: event
// Todo: modifier, require
// Todo: safeMath 적용


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

contract DOPE {
    using SafeMath for uint;
    using SafeMath for uint8;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint8 constant RATE = 10000;
    // project 관련
    address[] private _admins;
    string public saleTokenName;
    address public saleTokenAddress;
    uint public saleTokenAmount;

    // swap 관련
    address public exchangeTokenAddress;
    // Todo: 정수로 소수 계산하도록 하기
    uint256 exchangeRate;

    // stake 관련
    address public treasuryAddress;
    address public stakeTokenAddress;
    mapping (address => uint[]) userStakeChangedBlockNums;
    mapping (address => mapping (uint256 => uint256)) userStakeAmountByBlockNum;

    // loan 관련
    mapping (address => Share) public userShare;
    // Todo: naming
    uint256 public totalLockedShare;
    uint256 public totalRemainShareAfterDistribution;
    uint256 public interestRate;
    uint256 public depositRate;

    // Todo: naming
    address public lendTokenAddress;
    // 대출 실행시 유동적으로 변경되는 현재 금액
    uint256 public totalLockedDepositAmount;
    uint256 public totalCurrentDepositAmount;
    uint256 public totalRemainDepositAmountAfterDistribution;
    // 대출금 모집 이후 Fix 된 금액
    mapping (address => uint256) lenderDepositAmount;

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

    function stake (uint256 amount) public virtual {
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
            uint256 lastChangedBlockNumber = userStakeChangedBlockNums[sender][historyLength.sub(1)];
            uint256 lastStakedAmount = userStakeAmount[sender][lastChangedBlockNumber];
            userStakeChangedBlockNums[sender].push(blockNumber);

            userStakeAmount[sender][blockNumber] = lastStakedAmount.add(amount);
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
        uint256 lastChangedBlockNumber = userStakeChangedBlockNums[sender][historyLength.sub(1)];
        uint256 stakedAmount = userStakeAmountByBlockNum[sender][lastChangedBlockNumber];
        require(stakedAmount >= amount, "invalid amount. stakedAmount < amount");

        token.transfer(msg.sender, amount);
        userStakeChangedBlockNums[sender].push(blockNumber);
        userStakeAmountByBlockNum[sender][blockNumber] = stakedAmount.sub(amount);
    }

    function acquireShareOfSaleToken (uint amount) public virtual {
        // Todo: swap 가능한 시기인 지 체크
        // Todo: 한 개인이 최대 구매가능한 수량 한정하기
        // Todo: stake 조건 체크
        // Todo: whitelist 여부 체크

        IERC20 fromToken = IERC20(exchangeTokenAddress);
        fromToken.transferFrom(msg.sender, treasuryAddress, amount);
        userShare[msg.sender] = Share(amount, 0);
    }

    function depositLend (uint256 amount) public virtual {
        // Todo: deposit 가능한 시점인 지 체크
        // Todo: amount 양수 체크
        // Todo: allowance 체크
        require(amount > 0, "invalid amount. should be positive value");
        IERC20 token = IERC20(lendTokenAddress);
        require(token.allowance(msg.sender, address(this)) >= amount, "불 충분한 token 개수");

        token.transferFrom(msg.sender, address(this), amount);
        lenderDepositAmount[msg.sender] = lenderDepositAmount[msg.sender].add(amount);
        totalLockedDepositAmount = totalLockedDepositAmount.add(amount);
        totalCurrentDepositAmount = totalLockedDepositAmount;
        totalRemainDepositAmountAfterDistribution = totalCurrentDepositAmount;
    }

    function withdrawLend () public virtual {
        // Todo: withdraw 가능한 시점인 지 체크 (IDO 종료이후)
        // Todo: amount 양수 체크
        // Todo: 현재 예치한 금액 체크
        // Todo: 남은 share 할 금액이 있는 지 체크
        IERC20 token = IERC20(lendTokenAddress);
        uint256 depositAmount = lenderDepositAmount[msg.sender];
        uint256 lenderDepositPercent = depositAmount.div(totalLockedDepositAmount);
        uint256 returnDepositAmount = totalCurrentDepositAmount.mul(lenderDepositPercent);
        uint256 returnShareAmount = totalLockedShare.mul(lenderDepositPercent);
        uint swapAmount = returnShareAmount.mul(exchangeRate).div(RATE);

        IERC20(saleTokenAddress).transfer(msg.sender, swapAmount);
        token.transfer(msg.sender, returnDepositAmount);

        totalRemainShareAfterDistribution = totalRemainShareAfterDistribution.sub(returnShareAmount);
        totalRemainDepositAmountAfterDistribution = totalRemainDepositAmountAfterDistribution.sub(returnDepositAmount);
        lenderDepositAmount[msg.sender] = 0;
    }

    function lend (uint256 collateralAmount_) public virtual {
        // Todo: lend 가능한 시점인 지 체크
        // Todo: 기본적인 금액 체크
        // Todo: 담보가능한 금액이 있는 지 체크
        // Todo: 현재 deposit amount 가 충분한 지 체크
        Share storage _userShare = userShare[msg.sender];
        uint256 remainShare = _userShare.amount.sub(_userShare.collateralAmount);
        uint256 loanAmount = collateralAmount_.mul(depositRate).div(RATE);
        require(remainShare >= collateralAmount_, "insufficient share");

        // send loanAmount to user
        IERC20(lendTokenAddress).transfer(msg.sender, loanAmount);
        // minus loanAmount from the totalDepsitAmount
        totalCurrentDepositAmount = totalCurrentDepositAmount.sub(loanAmount);
        totalRemainDepositAmountAfterDistribution = totalCurrentDepositAmount;
        // update the user collateralAmount;
        _userShare.collateralAmount = _userShare.collateralAmount.add(collateralAmount_);
        // update the totalLockedShare;
        totalLockedShare = totalLockedShare.add(collateralAmount_);
        totalRemainShareAfterDistribution = totalLockedShare;
    }

    function payback(uint256 paybackAmount) public virtual {
        // Todo: payBack 가능한 시점인 지 체크
        // Todo: amount 금액 체크
        // Todo: IDO 참여 여부 체크
        IERC20 token = IERC20(lendTokenAddress);
        require(token.allowance(msg.sender, address(this)) >= paybackAmount, "불 충분한 token 개수");
        Share storage _userShare = userShare[msg.sender];
        uint256 _currentCollateralAmount = _userShare.collateralAmount;
        uint256 returnCollateralAmount = paybackAmount.mul(RATE).div(depositRate);
        uint256 interestAmount = returnCollateralAmount.mul(interestRate).div(RATE);
        uint256 unlockShare = returnCollateralAmount.sub(interestAmount);

        token.transferFrom(msg.sender, this(address), paybackAmount);
        _userShare.amount = _userShare.amount.sub(interestAmount);
        _userShare.collateralAmount = _userShare.collateralAmount.sub(returnCollateralAmount);

        totalCurrentDepositAmount = totalCurrentDepositAmount.add(paybackAmount);
        totalRemainDepositAmountAfterDistribution = totalCurrentDepositAmount;
        totalLockedShare = totalLockedShare.sub(unlockShare);
        totalRemainShareAfterDistribution = totalLockedShare;
    }

    function claimToken () public virtual {
        // Todo: swap 가능한 시기인 지 체크
        // Todo: 이미 swap 했는 지 체크
        Share _share = userShare[msg.sender];
        uint finalShare = _share.amount.sub(_share.collateralAmount);
        // Todo: solidity 의 percent 처리 확인하기
        uint swapAmount = finalShare.mul(exchangeRate).div(RATE);

        IERC20(saleTokenAddress).transfer(msg.sender, swapAmount);
        _share.isSwapped = true;
    }
}
