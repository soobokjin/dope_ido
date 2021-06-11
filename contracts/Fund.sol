pragma solidity ^0.8.0;

import {SafeMath} from '@openzeppelin/contracts/utils/math/SafeMath.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IIDOPeriod} from "./utils/Period.sol";
import {IStake} from "./assets/Stake.sol";
import {Operator} from './access/Operator.sol';

import "hardhat/console.sol";

// contract 에서는 erc token 의 decimals 에 대해서 고려하지 않는다. (호출자 책임)
// Todo: initializing DOPE
// Todo: code refactoring
// Todo: method define
// Todo: modifier, require
// Todo: backer, lender cnt 기록
// Todo: safeERC 사용


interface IFund {
    function lenderClaim (address user, uint256 lenderDepositPercent, uint256 percentRate) external;
    function increaseCollateral (address user, uint256 collateralAmount) external;
    function decreaseCollateral (address user, uint256 interestAmount, uint256 unlockCollateralAmount) external;
    function getRemainShare(address user) external view returns (uint256);
}


struct Share {
    uint256 amount;
    uint256 collateralAmount;
    bool isSwapped;
}

contract Fund is Operator {
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


    uint32 constant EXCHANGE_RATE = 10 ** 6;
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

    IERC20 public saleToken;
    IERC20 public exchangeToken;
    IStake public stakeContract;

    constructor (
        string memory _saleTokenName,
        address _saleTokenAddress,
        uint256 _saleTokenAmount,
        address _exchangeTokenAddress,
        address _treasuryAddress,
        uint256 _maxUserFundingAllocation,
        uint256 _exchangeRate
            // 소수점 둘 째 자리까지 표현. e.g. 50% -> 5000, 3.12% -> 312
    ) {
        // Todo: Rate 가 10000 을 넘길 수 없음
        // Todo: 설정 변경이 가능한 기간?
        saleTokenName = _saleTokenName;
        saleTokenAddress = _saleTokenAddress;
        saleTokenAmount = _saleTokenAmount;
        treasuryAddress = _treasuryAddress;
        saleToken = IERC20(_saleTokenAddress);
        exchangeToken = IERC20(_exchangeTokenAddress);
        maxUserFundingAllocation = _maxUserFundingAllocation;
        exchangeRate = _exchangeRate;
    }

    function setContracts (
        address _stakeAddress
    ) public onlyOwner {
        stakeContract = IStake(_stakeAddress);
    }
    // -------------------- public getters -----------------------
    function setSaleToken () public onlyOwner {
        // Todo: fallback 으로 수정 고려
        require(saleToken.allowance(treasuryAddress, address(this)) == saleTokenAmount, "insufficient");
        saleToken.safeTransferFrom(treasuryAddress, address(this), saleTokenAmount);
    }

    function getTargetFundingAmount() public view returns (uint256) {
        return saleTokenAmount.mul(EXCHANGE_RATE).div(exchangeRate);
    }
    // funding
    function getShareAndCollateral (address user) public view returns (uint256, uint256) {
        uint256 shareAmount = userShare[user].amount;
        uint256 collateralAmount = userShare[user].collateralAmount;

        return (shareAmount.sub(collateralAmount), collateralAmount);
    }

    function getExpectedExchangeAmount(uint256 amount) public view returns (uint256) {
        return amount.mul(exchangeRate).div(EXCHANGE_RATE);
    }

    function getRemainShare(address user) public view returns (uint256) {
        return userShare[user].amount.sub(userShare[user].collateralAmount);
    }

    function fundSaleToken (uint amount) public {
        // Todo: Check the period
        // Todo: 한 개인이 최대 구매가능한 수량 한정하기 (maxAllocationPerUser)
        // Todo: stake 조건 체크
        // Todo: whitelist 여부 체크
        exchangeToken.safeTransferFrom(msg.sender, treasuryAddress, amount);
        userShare[msg.sender] = Share(amount, 0, false);

        totalFundedAmount = totalFundedAmount.add(amount);
        totalBacker = uint32(totalBacker.add(1));

        emit Funded(msg.sender, amount);
    }

    function claim () public {
        // Todo: Check the period
        // Todo: Check if already claimed
        address sender = msg.sender;
        Share storage _share = userShare[sender];
        uint finalShare = _share.amount.sub(_share.collateralAmount);
        uint swapAmount = finalShare.mul(exchangeRate).div(EXCHANGE_RATE);

        saleToken.safeTransfer(sender, swapAmount);
        _share.isSwapped = true;

        emit Claimed(sender, swapAmount);
    }

    function lenderClaim (
        address user,
        uint256 lenderDepositPercent,
        uint256 percentRate
    ) public override onlyOperator {
        // Todo: Check the period
        // can not directly call this function (only callable via operator, i.e. Lend contract)
        uint256 returnShareAmount = totalLockedShare.mul(lenderDepositPercent).div(percentRate);
        uint256 swapAmount = returnShareAmount.mul(exchangeRate).div(EXCHANGE_RATE);
        saleToken.safeTransfer(user, swapAmount);

        totalRemainShareAfterDistribution = totalRemainShareAfterDistribution.sub(returnShareAmount);

        emit Claimed(user, swapAmount);
    }

    function increaseCollateral (
        address user,
        uint256 collateralAmount
    ) public override onlyOperator {
        // Todo: Check the user collateralAmount
        // Todo: Check the period
        Share storage _userShare = userShare[user];
        uint256 remainShare = _userShare.amount.sub(_userShare.collateralAmount);
        require(remainShare >= collateralAmount, "insufficient share");

        _increaseCollateral(_userShare, collateralAmount);

        emit CollateralIncreased(user, collateralAmount, _userShare.collateralAmount);
    }

    function _increaseCollateral (Share storage _userShare, uint256 collateralAmount) private {
        _userShare.collateralAmount = _userShare.collateralAmount.add(collateralAmount);

        totalLockedShare = totalLockedShare.add(collateralAmount);
        totalRemainShareAfterDistribution = totalLockedShare;
    }

    function decreaseCollateral (
        address user,
        uint256 interestAmount,
        uint256 unlockCollateralAmount
    ) public override onlyOperator {
        // Todo: Check the user collateralAmount
        // Todo: Check the period
        Share storage _userShare = userShare[user];
        // 적어진 금액에서 계산하므로 실질적으로 조금 더 적은량이 unlock 됨
        require(_userShare.collateralAmount >= unlockCollateralAmount, "exceed collateral amount");
        _decreaseCollateral(_userShare, interestAmount, unlockCollateralAmount);

        emit CollateralDecreased(user, unlockCollateralAmount, _userShare.collateralAmount);
    }

    function _decreaseCollateral (
        Share storage _userShare, uint256 interestAmount, uint256 unlockCollateralAmount
    ) private {
        uint256 unlockShare = unlockCollateralAmount.sub(interestAmount);
        _userShare.amount = _userShare.amount.sub(interestAmount);
        _userShare.collateralAmount = _userShare.collateralAmount.sub(unlockCollateralAmount);

        totalLockedShare = totalLockedShare.sub(unlockShare);
        totalRemainShareAfterDistribution = totalLockedShare;
    }
}
