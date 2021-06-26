// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IStake} from "./Stake.sol";
import {Operator} from "../access/Operator.sol";

import "hardhat/console.sol";

// contract 에서는 erc token 의 decimals 에 대해서 고려하지 않는다. (호출자 책임)

interface IFund {
    struct SaleStrategy {
        address senderAddress;
        uint256 targetAmount;
        uint256 exchangeRate;
        uint256 userMinFundingAmount;
        uint256 userMaxFundingAmount;
    }

    struct SalePeriod {
        uint256 fundStartTime;
        uint256 fundingPeriod;
        uint256 releaseTime;
    }

    function initialize(bytes memory args) external;

    function initPayload(
        address _saleTokenAddress,
        address exchangeTokenAddress,
        address stakeAddress,
        address _treasuryAddress
    ) external pure returns (bytes memory);

    function fund(uint256 amount) external;
}

contract Fund is IFund, Operator, Initializable {
    using SafeMath for uint256;
    using SafeMath for uint32;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    event Funded(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 exchangeRate
    );

    event Claimed(address indexed user, address indexed token, uint256 amount);

    struct Period {
        uint256 period;
        uint256 periodFinish;
        uint256 startTime;
    }

    struct FundInfo {
        uint256 amount;
        bool isClaimed;
    }
    uint256 constant EXCHANGE_RATE = 10**6;

    Period public fundPeriod;
    uint256 public releaseTime;

    IERC20 public saleToken;
    IERC20 public exchangeToken;
    IStake public stakeContract;

    // target amount to get exchange token
    uint256 public targetAmount;
    uint256 exchangeRate;
    uint256 public userMinFundingAmount;
    uint256 public userMaxFundingAmount;
    address public treasuryAddress;

    // expressed to six decimal places. e.g. exchange_rate 1 means 0.000001
    mapping(address => FundInfo) public userFundInfo;

    uint32 public totalBacker;
    uint256 public totalFundedAmount;

    modifier onPeriod() {
        require(
            fundPeriod.startTime <= block.timestamp &&
                block.timestamp < fundPeriod.periodFinish,
            "not on funding period"
        );
        _;
    }

    function initialize(bytes memory args) public override initializer {
        (
            address _saleTokenAddress,
            address _exchangeTokenAddress,
            address _stakeAddress,
            address _treasuryAddress
        ) = abi.decode(args, (address, address, address, address));

        saleToken = IERC20(_saleTokenAddress);
        exchangeToken = IERC20(_exchangeTokenAddress);
        stakeContract = IStake(_stakeAddress);
        treasuryAddress = _treasuryAddress;

        setRole(_msgSender(), _msgSender());
    }

    function initPayload(
        address _saleTokenAddress,
        address _exchangeTokenAddress,
        address _stakeAddress,
        address _treasuryAddress
    ) public pure override returns (bytes memory) {
        return
            abi.encode(
                _saleTokenAddress,
                _exchangeTokenAddress,
                _stakeAddress,
                _treasuryAddress
            );
    }

    function setSaleToken(SaleStrategy memory _strategy) public onlyOwner {
        // targetAmount is dollar (not sale token amount)
        targetAmount = _targetAmount;
        exchangeRate = _exchangeRate;
        userMinFundingAmount = _userMinFundingAmount;
        userMaxFundingAmount = _userMaxFundingAmount;

        uint256 totalSaleTokenAmount = targetAmount.mul(exchangeRate).div(
            EXCHANGE_RATE
        );
        saleToken.safeTransferFrom(
            _senderAddress,
            address(this),
            totalSaleTokenAmount
        );
    }

    function setPeriod(SalePeriod memory _period) public onlyOwner {
        fundPeriod.period = _fundingPeriod;
        fundPeriod.startTime = _fundStartTime;
        fundPeriod.periodFinish = _fundStartTime.add(_fundingPeriod);
        releaseTime = _releaseTime;
    }

    // -------------------- public getters -----------------------
    function getTotalSaleTokenAmount() public view returns (uint256) {
        return targetAmount.mul(exchangeRate).div(EXCHANGE_RATE);
    }

    function getTargetAmount() public view returns (uint256) {
        return targetAmount;
    }

    function getExpectedExchangeAmount(uint256 amount)
        public
        view
        returns (uint256)
    {
        return amount.mul(exchangeRate).div(EXCHANGE_RATE);
    }

    function getFundedAmount(address user) public view returns (uint256) {
        return userFundInfo[user].amount;
    }

    function getClaimedAmount(address user) public view returns (uint256) {
        if (userFundInfo[user].isClaimed == false) {
            return 0;
        }
        uint256 amount = userFundInfo[user].amount;
        return amount.mul(exchangeRate).div(EXCHANGE_RATE);
    }

    // ================================================================= tx

    function fund(uint256 amount) public override onPeriod {
        // Todo: Whitelist
        require(targetAmount > 0, "sale token is not set");

        FundInfo memory _info = userFundInfo[_msgSender()];

        require(_info.amount == 0, "already funded");
        require(
            _info.amount.add(amount) >= userMinFundingAmount,
            "under min allocation"
        );
        require(
            _info.amount.add(amount) <= userMaxFundingAmount,
            "exceed max allocation"
        );

        // update

        userFundInfo[_msgSender()] = _info;

        require(
            stakeContract.isSatisfied(_msgSender()),
            "dissatisfy stake conditions"
        );
        require(totalFundedAmount <= targetAmount, "funding has been finished");
        uint256 availableAmount = _getAvailableAmount(amount);

        // if lock up period is exist, do not swap.
        _fund(availableAmount);

        if (block.timestamp >= releaseTime) {
            _claim();
        }
    }

    function _getAvailableAmount(uint256 amount)
        private
        view
        returns (uint256)
    {
        uint256 remainAmount = targetAmount.sub(totalFundedAmount);
        return remainAmount >= amount ? amount : remainAmount;
    }

    function _fund(uint256 amount) private nonReentrent {
        // Todo: token fallback
        userFundInfo[_msgSender()].amount = userFundInfo[_msgSender()]
        .amount
        .add(amount);

        totalFundedAmount = totalFundedAmount.add(amount);
        totalBacker = uint32(totalBacker.add(1)); // the graph | etherscan

        exchangeToken.safeTransferFrom(_msgSender(), treasuryAddress, amount); // caller fund.sol

        emit Funded(_msgSender(), address(tokenAddr), amount); // TODO: add token address
    }

    function claim() public {
        require(releaseTime <= block.timestamp, "token is not released");
        require(
            userFundInfo[_msgSender()].isClaimed == false,
            "already claimed"
        );
        _claim();
    }

    function _claim() internal {
        uint256 amount = userFundInfo[_msgSender()].amount;
        userFundInfo[_msgSender()].isClaimed = true;

        uint256 swapAmount = amount.mul(exchangeRate).div(EXCHANGE_RATE);
        saleToken.safeTransfer(_msgSender(), swapAmount);

        emit Claimed(_msgSender(), address(tokenAddr), swapAmount); // TODO: add token address
    }

    function emergencyWithdraw(
        IERC20 token,
        uint256 amount,
        address to
    ) public onlyOwner {
        // require(address(token) != address(saleToken), "NO");

        // TODO: yes

        emit LoveAndPeace();
    }

    function emergencyWithdraw(uint256 amount, address to)
        public
        payable
        onlyOwner
    {
        send(amount, to); // TODO: fix
    }
}
