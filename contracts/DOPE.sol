pragma solidity ^0.8.0;

import {SafeMath} from '@openzeppelin/contracts/utils/math/SafeMath.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IIDOPeriod} from "./utils/Period.sol";
import "hardhat/console.sol";

// contract 에서는 erc token 의 decimals 에 대해서 고려하지 않는다. (호출자 책임)
// Todo: Ownable 적용
// Todo: initializing DOPE
// Todo: code refactoring
// Todo: method define
// Todo: modifier, require


struct Share {
    // amount 는 Swap 시점의 USDT 량과 동일
    uint256 amount;
    uint256 collateralAmount;
    bool isSwapped;
}

contract DOPE {
    using SafeMath for uint;
    using SafeMath for uint8;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

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

    event Funded(
        address indexed user,
        uint256 amount
    );

    event Deposit(
        address indexed user,
        uint256 amount,
        uint256 totalDepositAmount
    );

    event Withdraw(
        address indexed user,
        uint256 amount
    );

    event Claimed(
        address indexed user,
        uint256 amount
    );

    event Borrow(
        address indexed user,
        uint256 amount
    );

    event CollateralIncreased(
        address indexed user,
        uint256 collateralAmount,
        uint256 totalCollateralAmount
    );

    event CollateralDecreased(
        address indexed user,
        uint256 collateralAmount,
        uint256 totalCollateralAmount
    );

    event Repay(
        address indexed user,
        uint256 repayAmount,
        uint256 interestAmount,
        uint256 totalShareAmount
    );

    uint32 constant EXCHANGE_RATE = 10 ** 6;
    // 소수점 둘 째 자리까지 표현
    uint32 constant MAX_LTV_RATE = 10000;
    uint32 constant MAX_INTEREST_RATE = 10000;
    // project 관련
    address[] private _admins;
    string public saleTokenName;
    address public saleTokenAddress;
    // 전체 판매 금액
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
    uint256 public totalLockedShare;
    uint256 public totalRemainShareAfterDistribution;
    uint256 public interestRate;
    uint256 public ltvRate;

    address public lendTokenAddress;
    // 대출 실행시 유동적으로 변경되는 현재 금액
    uint256 public totalLockedDepositAmount;
    uint256 public totalCurrentDepositAmount;
    uint256 public totalRemainDepositAmountAfterDistribution;
    // 대출금 모집 이후 Fix 된 금액
    mapping (address => uint256) lenderDepositAmount;

    IIDOPeriod public idoPeriod;

    constructor (
        string memory _saleTokenName,
        address _saleTokenAddress,
        uint256 _saleTokenAmount,
        address _exchangeTokenAddress,
        address _treasuryAddress,
        address _stakeTokenAddress,
        address _periodAddress,
        uint256 _exchangeRate,
        uint256 _interestRate,
        uint256 _ltvRate
            // 소수점 둘 째 자리까지 표현. e.g. 50% -> 5000, 3.12% -> 312

    ) {
        // Todo: Rate 가 10000 을 넘길 수 없음
        _admins.push(msg.sender);
        saleTokenName = _saleTokenName;
        saleTokenAddress = _saleTokenAddress;
        saleTokenAmount = _saleTokenAmount;

        exchangeTokenAddress = _exchangeTokenAddress;
        treasuryAddress = _treasuryAddress;
        stakeTokenAddress = _stakeTokenAddress;
        lendTokenAddress = _exchangeTokenAddress;
        idoPeriod = IIDOPeriod(_periodAddress);

        exchangeRate = _exchangeRate;
        interestRate = _interestRate;
        ltvRate = _ltvRate;

    }

    // -------------------- public getters -----------------------
    function putSaleToken() public virtual {
        IERC20 token = IERC20(saleTokenAddress);
        require(token.allowance(treasuryAddress, address(this)) >= saleTokenAmount, "insufficient");
        token.transferFrom(treasuryAddress, address(this), saleTokenAmount);
    }

    // stake
    function getCurrentStakeAmount (address user) public view returns (uint256) {
        uint256 length = userStakeChangedBlockNums[user].length;
        if (length == 0) {
            return 0;
        }
        uint256 lastBlockNumber = userStakeChangedBlockNums[user][length - 1];
        return userStakeAmountByBlockNum[user][lastBlockNumber];
    }

    // funding
    function getShareAndCollateral (address user) public view returns (uint256, uint256) {
        uint256 shareAmount = userShare[user].amount;
        uint256 collateralAmount = userShare[user].collateralAmount;

        return (shareAmount.sub(collateralAmount), collateralAmount);
    }

    // lend
    function getDepositedAmount(address user) public view returns (uint256) {
        return lenderDepositAmount[user];
    }

    // -------------------- public set methods ------------------------

    function getStakeAmountOf (address user) public view returns (uint256) {
        uint256 length = userStakeChangedBlockNums[user].length;
        if (length == 0) {
            return 0;
        }
        uint256 lastBlockNumber = userStakeChangedBlockNums[user][length - 1];
        return userStakeAmountByBlockNum[user][lastBlockNumber];
    }

    function stake (uint256 amount) public virtual {
        require(idoPeriod.phaseIn(IIDOPeriod.Phase.Stake), "not in stake period");
        require(amount > 0, "invalid amount. should be positive value");
        // Todo: 최소 lockup 개수 체크
        // Todo: amount 만큼 가져올 수 있는 지 체크
        IERC20 token = IERC20(stakeTokenAddress);
        require(token.allowance(msg.sender, address(this)) >= amount, "insufficient");
        address sender = msg.sender;
        uint256 historyLength = userStakeChangedBlockNums[sender].length;
        uint256 blockNumber = block.number;

        // transfer
        token.transferFrom(msg.sender, address(this), amount);
        // record stake history
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

    function unStake (uint256 amount) public virtual {
        address sender = msg.sender;
        uint256 blockNumber = block.number;
        require(amount > 0, "invalid amount. should be positive value");
        require(userStakeChangedBlockNums[sender].length > 0, "stake amount is 0");
        // Todo: amount 가 stake 량보다 작은 지 체크
        IERC20 token = IERC20(stakeTokenAddress);
        uint256 historyLength = userStakeChangedBlockNums[sender].length;
        uint256 lastChangedBlockNumber = userStakeChangedBlockNums[sender][historyLength.sub(1)];
        uint256 stakedAmount = userStakeAmountByBlockNum[sender][lastChangedBlockNumber];
        require(stakedAmount >= amount, "invalid amount. stakedAmount < amount");

        token.transfer(msg.sender, amount);
        userStakeChangedBlockNums[sender].push(blockNumber);
        userStakeAmountByBlockNum[sender][blockNumber] = stakedAmount.sub(amount);

        emit UnStaked(
            msg.sender, amount, userStakeAmountByBlockNum[sender][blockNumber], blockNumber
        );
    }

    function fundSaleToken (uint amount) public virtual {
        // Todo: swap 가능한 시기인 지 체크
        // Todo: 한 개인이 최대 구매가능한 수량 한정하기
        // Todo: stake 조건 체크
        // Todo: whitelist 여부 체크

        IERC20 fromToken = IERC20(exchangeTokenAddress);
        fromToken.transferFrom(msg.sender, treasuryAddress, amount);
        userShare[msg.sender] = Share(amount, 0, false);

        emit Funded(msg.sender, amount);
    }

    function depositTokenForLend (uint256 amount) public virtual {
        // Todo: deposit 가능한 시점인 지 체크
        // Todo: minimum amount 체크 (contract 생성시 등록할 수 있도록)
        // Todo: allowance 체크
        require(amount > 0, "invalid amount. should be positive value");
        IERC20 token = IERC20(lendTokenAddress);
        require(token.allowance(msg.sender, address(this)) >= amount, "insufficient");

        token.transferFrom(msg.sender, address(this), amount);
        lenderDepositAmount[msg.sender] = lenderDepositAmount[msg.sender].add(amount);
        totalLockedDepositAmount = totalLockedDepositAmount.add(amount);
        totalCurrentDepositAmount = totalLockedDepositAmount;
        totalRemainDepositAmountAfterDistribution = totalCurrentDepositAmount;

        emit Deposit(
            msg.sender, amount, lenderDepositAmount[msg.sender]
        );
    }

    function withdrawLentToken () public virtual {
        // Todo: withdraw 가능한 시점인 지 체크 (IDO 종료이후)
        // Todo: amount 양수 체크
        // Todo: 현재 예치한 금액 체크
        // Todo: 남은 share 할 금액이 있는 지 체크
        uint256 depositAmount = lenderDepositAmount[msg.sender];
        uint256 lenderDepositPercent = depositAmount.mul(1e18).div(totalLockedDepositAmount);
        uint256 returnDepositAmount = totalCurrentDepositAmount.mul(lenderDepositPercent).div((1e18));
        uint256 returnShareAmount = totalLockedShare.mul(lenderDepositPercent).div(1e18);
        // Todo: solidity 의 percent 처리 확인하기
        uint swapAmount = returnShareAmount.mul(exchangeRate).div(EXCHANGE_RATE);
        console.log(swapAmount);
        console.log(returnDepositAmount);
        IERC20(saleTokenAddress).transfer(msg.sender, swapAmount);
        IERC20 token = IERC20(lendTokenAddress);
        token.transfer(msg.sender, returnDepositAmount);

        totalRemainShareAfterDistribution = totalRemainShareAfterDistribution.sub(returnShareAmount);
        totalRemainDepositAmountAfterDistribution = totalRemainDepositAmountAfterDistribution.sub(returnDepositAmount);
        lenderDepositAmount[msg.sender] = 0;

        emit Withdraw(
            msg.sender, returnDepositAmount
        );
        emit Claimed(
            msg.sender, swapAmount
        );
    }

    // Todo: 대출금을 받는 식으로 수정
    function borrow (uint256 amount) public virtual {
        // Todo: lend 가능한 시점인 지 체크
        // Todo: 기본적인 금액 체크
        // Todo: 담보가능한 금액이 있는 지 체크
        // Todo: 현재 deposit amount 가 충분한 지 체크
        Share storage _userShare = userShare[msg.sender];
        uint256 additionalCollateralAmount = amount.mul(MAX_LTV_RATE).div(ltvRate);
        uint256 remainShare = _userShare.amount.sub(_userShare.collateralAmount);
        require(remainShare >= additionalCollateralAmount, "insufficient share");

        // send loanAmount to user
        IERC20(lendTokenAddress).transfer(msg.sender, amount);
        // minus loanAmount from the totalDepsitAmount
        totalCurrentDepositAmount = totalCurrentDepositAmount.sub(amount);
        totalRemainDepositAmountAfterDistribution = totalCurrentDepositAmount;
        // update the user collateralAmount;
        _userShare.collateralAmount = _userShare.collateralAmount.add(additionalCollateralAmount);
        // update the totalLockedShare;
        totalLockedShare = totalLockedShare.add(additionalCollateralAmount);
        totalRemainShareAfterDistribution = totalLockedShare;

        emit Borrow(
            msg.sender, amount
        );
        emit CollateralIncreased(
            msg.sender, additionalCollateralAmount, _userShare.collateralAmount
        );
    }

    function repay(uint256 amount) public virtual {
        // Todo: repay 가능한 시점인 지 체크
        // Todo: amount 금액 체크
        // Todo: IDO 참여 여부 체크
        IERC20 token = IERC20(lendTokenAddress);
        require(token.allowance(msg.sender, address(this)) >= amount, "insufficient token amount");
        Share storage _userShare = userShare[msg.sender];
        // 적어진 금액에서 계산하므로 실질적으로 조금 더 적은량이 unlock 됨
        uint256 unlockCollateralAmount = amount.mul(MAX_LTV_RATE).div(ltvRate);
        uint256 interestAmount = unlockCollateralAmount.mul(interestRate).div(MAX_INTEREST_RATE);
        uint256 unlockShare = unlockCollateralAmount.sub(interestAmount);

        _userShare.amount = _userShare.amount.sub(interestAmount);
        _userShare.collateralAmount = _userShare.collateralAmount.sub(unlockCollateralAmount);
        totalLockedShare = totalLockedShare.sub(unlockShare);
        totalRemainShareAfterDistribution = totalLockedShare;

        token.transferFrom(msg.sender, address(this), amount);
        totalCurrentDepositAmount = totalCurrentDepositAmount.add(amount);
        totalRemainDepositAmountAfterDistribution = totalCurrentDepositAmount;

        emit Repay(
            msg.sender, amount, interestAmount, _userShare.amount
        );
        emit CollateralDecreased(
            msg.sender, unlockCollateralAmount, _userShare.collateralAmount
        );

    }

    function claim() public virtual {
        // Todo: swap 가능한 시기인 지 체크
        // Todo: 이미 swap 했는 지 체크
        Share storage _share = userShare[msg.sender];
        uint finalShare = _share.amount.sub(_share.collateralAmount);
        // Todo: solidity 의 percent 처리 확인하기
        uint swapAmount = finalShare.mul(exchangeRate).div(EXCHANGE_RATE);

        IERC20(saleTokenAddress).transfer(msg.sender, swapAmount);
        _share.isSwapped = true;

        emit Claimed(msg.sender, swapAmount);
    }
}
