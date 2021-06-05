pragma solidity ^0.8.0;

import {SafeMath} from '@openzeppelin/contracts/utils/math/SafeMath.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {Context, Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

interface ILend {
    function repayLentTokenFrom (uint amount) external;
    function getDepositedAmount(address user) external returns (uint256);
    function deposit (uint256 amount) external;
    function withdraw () external returns (uint256, uint256);
    function sendLentTokenTo (uint256 amount) external;

}


contract Lend {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using SafeMath for uint32;

    event Deposit(
        address indexed user,
        uint256 amount,
        uint256 totalDepositAmount
    );

    event Withdraw(
        address indexed user,
        uint256 amount
    );

    uint32 constant MAX_INTEREST_RATE = 10000;
    uint256 constant MAX_PERCENT_RATE = 1e18;

    mapping (address => uint256) lenderDepositAmount;
    IERC20 public lendToken;

    uint32 public totalLender;
    uint256 public maxTotalAllocation;
    uint256 public maxUserAllocation;

    uint256 public totalLockedDepositAmount;
    uint256 public totalCurrentDepositAmount;
    uint256 public totalRemainDepositAmountAfterDistribution;

    constructor (
        address _lendTokenAddress,
        uint256 _maxTotalAllocation,
        uint256 _maxUserAllocation
    ) {
        lendToken = IERC20(_lendTokenAddress);
        maxTotalAllocation = _maxTotalAllocation;
        maxUserAllocation = _maxUserAllocation;
    }
    function getDepositedAmount(address user) public returns (uint256) {
        return lenderDepositAmount[user];
    }

    function isFilled () private returns (bool) {
        return (maxTotalAllocation == totalLockedDepositAmount);
    }

    function deposit (uint256 amount) public {
        address sender = tx.origin;
        uint256 remainAllocation = maxTotalAllocation.sub(maxTotalAllocation);
        uint256 remainUserAllocation = maxUserAllocation.sub(lenderDepositAmount[sender]);
        require(!isFilled(), "exceed max allocation");
        require(remainUserAllocation > 0, "exceed max user allocation");
        require(lendToken.allowance(tx.origin, address(this)) >= amount, "insufficient");
        uint256 actualAmount = remainAllocation >= amount ? amount : remainAllocation;
        actualAmount = remainUserAllocation >= actualAmount ? actualAmount : remainUserAllocation;

        lendToken.safeTransferFrom(sender, address(this), actualAmount);

        if (lenderDepositAmount[sender] == 0) {
            totalLender = uint32(totalLender.add(1));
        }
        lenderDepositAmount[sender] = lenderDepositAmount[sender].add(actualAmount);
        totalLockedDepositAmount = totalLockedDepositAmount.add(actualAmount);
        totalCurrentDepositAmount = totalLockedDepositAmount;
        totalRemainDepositAmountAfterDistribution = totalCurrentDepositAmount;

        emit Deposit(
            sender, actualAmount, lenderDepositAmount[sender]
        );
    }

    function withdraw () public returns (uint256, uint256) {
        // Todo: 현재 예치한 금액 체크
        // Todo: 남은 share 할 금액이 있는 지 체크
        address sender = tx.origin;
        uint256 depositAmount = lenderDepositAmount[sender];
        uint256 lenderDepositPercent = depositAmount.mul(MAX_PERCENT_RATE).div(totalLockedDepositAmount);
        uint256 returnDepositAmount = totalCurrentDepositAmount.mul(lenderDepositPercent).div(MAX_PERCENT_RATE);

        lendToken.safeTransfer(sender, returnDepositAmount);
        totalRemainDepositAmountAfterDistribution = totalRemainDepositAmountAfterDistribution.sub(returnDepositAmount);
        lenderDepositAmount[sender] = 0;

        emit Withdraw(sender, returnDepositAmount);
        return (lenderDepositPercent, MAX_PERCENT_RATE);
    }

    function sendLentTokenTo (uint256 amount) public {
        address sender = tx.origin;

        // send loanAmount to user
        lendToken.safeTransfer(sender, amount);
        // minus loanAmount from the totalDepsitAmount
        totalCurrentDepositAmount = totalCurrentDepositAmount.sub(amount);
        totalRemainDepositAmountAfterDistribution = totalCurrentDepositAmount;
    }

    function repayLentTokenFrom (uint amount) public {
        address sender = tx.origin;
        require(lendToken.allowance(sender, address(this)) >= amount, "insufficient token amount");

        lendToken.transferFrom(sender, address(this), amount);
        totalCurrentDepositAmount = totalCurrentDepositAmount.add(amount);
        totalRemainDepositAmountAfterDistribution = totalCurrentDepositAmount;
    }
}
