pragma solidity ^0.8.0;

import {SafeMath} from '@openzeppelin/contracts/utils/math/SafeMath.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IIDOPeriod} from "./utils/Period.sol";
import {ILend} from "./assets/Lend.sol";
import {IStake} from "./assets/Stake.sol";
import "hardhat/console.sol";

// contract 에서는 erc token 의 decimals 에 대해서 고려하지 않는다. (호출자 책임)
// Todo: Ownable 적용
// Todo: initializing DOPE
// Todo: code refactoring
// Todo: method define
// Todo: modifier, require
// Todo: backer, lender cnt 기록
// Todo: safeERC 사용

struct Share {
    // amount 는 Swap 시점의 USDT 량과 동일
    uint256 amount;
    uint256 collateralAmount;
    bool isSwapped;
}

contract DOPE {
    using SafeMath for uint;
    using SafeMath for uint8;
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
    address public treasuryAddress;
    uint256 public saleTokenAmount;
    uint256 public totalFundedAmount;
    uint256 exchangeRate;

    uint32 public totalBacker;
    uint256 public maxUserFundingAllocation;

    mapping (address => Share) public userShare;
    uint256 public totalRemainShareAfterDistribution;
    uint256 public totalLockedShare;
    uint256 public interestRate;
    uint256 public ltvRate;

    IERC20 public saleToken;
    IERC20 public exchangeToken;
    IStake public stakeContract;
    ILend public lendContract;
    IIDOPeriod public periodContract;

    constructor (
        string memory _saleTokenName,

        address _saleTokenAddress,
        uint256 _saleTokenAmount,

        address _exchangeTokenAddress,
        address _treasuryAddress,
        address _stakeAddress,
        address _periodAddress,
        uint256 _maxUserFundingAllocation,
        uint256 _exchangeRate,
        uint256 _interestRate,
        uint256 _ltvRate
            // 소수점 둘 째 자리까지 표현. e.g. 50% -> 5000, 3.12% -> 312

    ) {
        // Todo: Rate 가 10000 을 넘길 수 없음
        // Check Todo: 설정은 무조건 우리만 변경가능?
        // Check Todo: 설정 변경이 가능한 기간?
        _admins.push(msg.sender);
        saleTokenName = _saleTokenName;
        saleTokenAddress = _saleTokenAddress;
        saleTokenAmount = _saleTokenAmount;
        treasuryAddress = _treasuryAddress;

        saleToken = IERC20(_saleTokenAddress);
        exchangeToken = IERC20(_exchangeTokenAddress);

        stakeContract = IStake(_stakeAddress);
        lendContract = ILend(_exchangeTokenAddress);
        periodContract = IIDOPeriod(_periodAddress);

        maxUserFundingAllocation = _maxUserFundingAllocation;
        exchangeRate = _exchangeRate;
        interestRate = _interestRate;
        ltvRate = _ltvRate;
    }

    // -------------------- public getters -----------------------
    function setSaleToken() public {
        // Todo: fallback 으로 수정 고려
        require(saleToken.allowance(treasuryAddress, address(this)) == saleTokenAmount, "insufficient");
        saleToken.safeTransferFrom(treasuryAddress, address(this), saleTokenAmount);
    }

    function getTargetFundingAmount() public view returns (uint256) {
        return saleTokenAmount.mul(EXCHANGE_RATE).div(exchangeRate);
    }

    // stake
    function getCurrentStakeAmount (address user) public view returns (uint256) {
        return stakeContract.getCurrentStakeAmountOf(user);
    }

    // funding
    function getShareAndCollateral (address user) public view returns (uint256, uint256) {
        uint256 shareAmount = userShare[user].amount;
        uint256 collateralAmount = userShare[user].collateralAmount;

        return (shareAmount.sub(collateralAmount), collateralAmount);
    }

    // lend
    function getDepositedAmount(address user) public view returns (uint256) {
        return lendContract.getDepositedAmount(user);
    }

    function getExpectedExchangeAmount(uint256 amount) public view returns (uint256) {
        return amount.mul(exchangeRate).div(EXCHANGE_RATE);
    }

    function getExpectedRepayInterest(address user, uint256 amount) public view returns (uint256, uint256, uint256) {
        // Todo: 함수로 중복 구현 제거
        uint256 unlockCollateralAmount = amount.mul(MAX_LTV_RATE).div(ltvRate);
        uint256 interestAmount = unlockCollateralAmount.mul(interestRate).div(MAX_INTEREST_RATE);

        return (
            interestRate,
            interestAmount.mul(exchangeRate).div(EXCHANGE_RATE),
            userShare[user].amount.sub(interestAmount)
        );
    }

    function getMaxBorrowAmount(address user) public view returns (uint256) {
        // Todo: 0 원 처리
        uint256 remainShare = userShare[user].amount.sub(userShare[user].collateralAmount);
        return remainShare.mul(ltvRate).div(MAX_LTV_RATE);
    }

    function getExpectedCollateralAmount(uint256 amount) public view returns (
        uint256, uint256
    ) {
        uint256 expectedCollateralAmount = amount.mul(MAX_LTV_RATE).div(ltvRate);
        uint256 interestAmount = expectedCollateralAmount.mul(interestRate).div(MAX_INTEREST_RATE);

        return (expectedCollateralAmount, interestAmount);
    }

    // -------------------- public set methods ------------------------

    function stake (uint256 amount) public {
        require(periodContract.phaseIn(IIDOPeriod.Phase.Stake), "not in stake period");
        // Todo: 최소 lockup 개수 체크
        // Todo: amount 만큼 가져올 수 있는 지 체크
        // Todo: stake 기간 체크
        stakeContract.stake(amount);
    }

    function unStake (uint256 amount) public {
        require(periodContract.phaseIn(IIDOPeriod.Phase.Stake), "not in stake period");
        stakeContract.unStake(amount);
    }

    function fundSaleToken (uint amount) public {
        // Todo: swap 가능한 시기인 지 체크
        // Todo: 한 개인이 최대 구매가능한 수량 한정하기 (maxAllocationPerUser)
        // Todo: stake 조건 체크
        // Todo: whitelist 여부 체크
        // Todo: backer 기록

        uint256 (start, end) = periodContract.getStartAndEndPhaseOf(IIDOPeriod.Phase.Stake);
        require(stakeContract.isSatisfied(start, end), "not permission: stake");

        exchangeToken.safeTransferFrom(msg.sender, treasuryAddress, amount);
        userShare[msg.sender] = Share(amount, 0, false);

        totalFundedAmount = totalFundedAmount.add(amount);
        totalBacker = uint32(totalBacker.add(1));

        emit Funded(msg.sender, amount);
    }

    function depositTokenForLend (uint256 amount) public {
        // Todo: deposit 가능한 시점인 지 체크
        lendContract.deposit(amount);
    }

    function withdrawLentToken () public {
        // Todo: withdraw 가능한 시점인 지 체크 (IDO 종료이후)
        // Todo: amount 양수 체크
        // Todo: 현재 예치한 금액 체크
        // Todo: 남은 share 할 금액이 있는 지 체크
        address sender = msg.sender;
        uint256 (lenderDepositPercent, percentRate) = lendContract.withdraw();
        uint256 returnShareAmount = totalLockedShare.mul(lenderDepositPercent).div(percentRate);
        uint256 swapAmount = returnShareAmount.mul(exchangeRate).div(EXCHANGE_RATE);

        saleToken.safeTransfer(sender, swapAmount);
        totalRemainShareAfterDistribution = totalRemainShareAfterDistribution.sub(returnShareAmount);

        emit Claimed(
            sender, swapAmount
        );
    }

    // Todo: 대출금을 받는 식으로 수정
    function borrow (uint256 amount) public {
        // Todo: lend 가능한 시점인 지 체크
        // Todo: 기본적인 금액 체크
        // Todo: 담보가능한 금액이 있는 지 체크
        // Todo: 현재 deposit amount 가 충분한 지 체크
        address sender = msg.sender;
        Share storage _userShare = userShare[sender];
        uint256 additionalCollateralAmount = amount.mul(MAX_LTV_RATE).div(ltvRate);
        uint256 remainShare = _userShare.amount.sub(_userShare.collateralAmount);
        require(remainShare >= additionalCollateralAmount, "insufficient share");

        lendContract.sendLentTokenTo(amount);
        _userShare.collateralAmount = _userShare.collateralAmount.add(additionalCollateralAmount);
        totalLockedShare = totalLockedShare.add(additionalCollateralAmount);
        totalRemainShareAfterDistribution = totalLockedShare;

        emit Borrow(sender, amount);
        emit CollateralIncreased(sender, additionalCollateralAmount, _userShare.collateralAmount);
    }

    function repay (uint256 amount) public {
        // Todo: repay 가능한 시점인 지 체크
        // Todo: amount 금액 체크
        // Todo: IDO 참여 여부 체크
        address sender = msg.sender;
        Share storage _userShare = userShare[sender];
        // 적어진 금액에서 계산하므로 실질적으로 조금 더 적은량이 unlock 됨
        uint256 unlockCollateralAmount = amount.mul(MAX_LTV_RATE).div(ltvRate);
        uint256 interestAmount = unlockCollateralAmount.mul(interestRate).div(MAX_INTEREST_RATE);
        uint256 unlockShare = unlockCollateralAmount.sub(interestAmount);

        lendContract.repayLentTokenFrom(amount);
        _userShare.amount = _userShare.amount.sub(interestAmount);
        _userShare.collateralAmount = _userShare.collateralAmount.sub(unlockCollateralAmount);
        totalLockedShare = totalLockedShare.sub(unlockShare);
        totalRemainShareAfterDistribution = totalLockedShare;

        emit Repay(sender, amount, interestAmount, _userShare.amount);
        emit CollateralDecreased(sender, unlockCollateralAmount, _userShare.collateralAmount);
    }

    function claim() public {
        // Todo: swap 가능한 시기인 지 체크
        // Todo: 이미 swap 했는 지 체크
        address sender = msg.sender;
        Share storage _share = userShare[sender];
        uint finalShare = _share.amount.sub(_share.collateralAmount);
        // Todo: solidity 의 percent 처리 확인하기
        uint swapAmount = finalShare.mul(exchangeRate).div(EXCHANGE_RATE);

        saleToken.safeTransfer(sender, swapAmount);
        _share.isSwapped = true;

        emit Claimed(sender, swapAmount);
    }
}
