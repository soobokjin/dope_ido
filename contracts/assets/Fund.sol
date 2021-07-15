// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IStake} from "./Stake.sol";
import {Operator} from "../access/Operator.sol";
import {MerkleProof} from "../utils/MerkleProof.sol";

import "hardhat/console.sol";

interface IFund {
    function initialize(bytes memory args) external;

    function initPayload(
        address _saleTokenAddress,
        address exchangeTokenAddress,
        address stakeAddress,
        address _treasuryAddress
    ) external pure returns (bytes memory);

    function fund(
        uint256 _amount,
        bytes32[] memory _proof,
        uint32 _index
    ) external;

    event Funded(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 exchangeRate
    );
    event Claimed(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 exchangeRate
    );
}

contract Fund is IFund, Operator, Initializable {
    using SafeMath for uint256;
    using SafeMath for uint8;
    using SafeMath for uint32;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct Period {
        uint256 period;
        uint256 periodFinish;
        uint256 startTime;
    }

    struct FundInfo {
        uint256 amount;
        uint256 claimedAmount;
    }
    uint256 constant EXCHANGE_RATE = 1e18;

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

    uint256 public totalFundedAmount;
    bytes32 saleTokenMerkleRootWhiteList;

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

    function registerSaleTokenWhiteList(bytes32 _saleTokenMerkleRootWhiteList)
        public
        onlyOwner
    {
        saleTokenMerkleRootWhiteList = _saleTokenMerkleRootWhiteList;
    }

    function getSaleTokenMerkleRootWhiteList() public view returns (bytes32) {
        return saleTokenMerkleRootWhiteList;
    }

    function setSaleToken(
        address _senderAddress,
        uint256 _targetAmount,
        uint256 _exchangeRate,
        uint256 _userMinFundingAmount,
        uint256 _userMaxFundingAmount
    ) public onlyOwner {
        // targetAmount is dollar (not sale token amount)
        targetAmount = _targetAmount;
        userMinFundingAmount = _userMinFundingAmount;
        userMaxFundingAmount = _userMaxFundingAmount;
        exchangeRate = getDecimalAppliedExchangeRate(_exchangeRate);

        uint256 totalSaleTokenAmount = targetAmount.mul(exchangeRate).div(
            EXCHANGE_RATE
        );
        saleToken.safeTransferFrom(
            _senderAddress,
            address(this),
            totalSaleTokenAmount
        );
    }

    function getDecimalAppliedExchangeRate(uint256 _exchangeRate)
        internal
        view
        returns (uint256)
    {
        uint8 exchangeTokenDecimals = ERC20(address(exchangeToken)).decimals();
        uint8 saleTokenDecimals = ERC20(address(saleToken)).decimals();
        uint256 actualExchangeRate;

        if (exchangeTokenDecimals <= saleTokenDecimals) {
            actualExchangeRate = _exchangeRate.mul(
                10**saleTokenDecimals.sub(exchangeTokenDecimals)
            );
        } else {
            actualExchangeRate = _exchangeRate.div(
                10**exchangeTokenDecimals.sub(saleTokenDecimals)
            );
        }

        return actualExchangeRate;
    }

    function setPeriod(
        uint256 _fundStartTime,
        uint256 _fundingPeriod,
        uint256 _releaseTime
    ) public onlyOwner {
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
        if (userFundInfo[user].claimedAmount == 0) {
            return 0;
        }
        return
            userFundInfo[user].claimedAmount.mul(exchangeRate).div(
                EXCHANGE_RATE
            );
    }

    function fund(
        uint256 _amount,
        bytes32[] memory _proof,
        uint32 _index
    ) public override {
        // Todo: Whitelist
        require(
            fundPeriod.startTime <= block.timestamp &&
                block.timestamp < fundPeriod.periodFinish,
            "Fund: not on funding period"
        );
        require(targetAmount > 0, "Fund: sale token is not set");
        require(
            totalFundedAmount <= targetAmount,
            "Fund: funding has been finished"
        );
        require(_amount >= userMinFundingAmount, "Fund: under min allocation");
        require(
            _isWhiteListed(_proof, _index),
            "Fund: dissatisfy stake conditions"
        );

        // if lock up period is exist, do not swap.
        _fund(_amount);

        if (block.timestamp >= releaseTime) {
            _claim();
        }
    }

    function _getAvailableAmount(uint256 amount)
        internal
        view
        returns (uint256)
    {
        return Math.min(amount, targetAmount.sub(totalFundedAmount));
    }

    function _fund(uint256 amount) internal {
        FundInfo memory _info = userFundInfo[_msgSender()];
        require(
            _info.amount.add(amount) <= userMaxFundingAmount,
            "Fund: exceed amount"
        );

        uint256 availableAmount = _getAvailableAmount(amount);
        _info.amount = _info.amount.add(availableAmount);
        totalFundedAmount = totalFundedAmount.add(availableAmount);
        userFundInfo[_msgSender()] = _info;

        exchangeToken.safeTransferFrom(
            _msgSender(),
            treasuryAddress,
            availableAmount
        );

        emit Funded(
            _msgSender(),
            address(saleToken),
            availableAmount,
            exchangeRate
        );
    }

    function claim() public {
        require(releaseTime <= block.timestamp, "Fund: token is not released");

        _claim();
    }

    function _claim() internal {
        FundInfo memory _info = userFundInfo[_msgSender()];
        require(
            _info.amount.sub(_info.claimedAmount) > 0,
            "Fund: already claimed"
        );

        uint256 claimAmount = _info.amount.sub(_info.claimedAmount);
        uint256 swapAmount = claimAmount.mul(exchangeRate).div(EXCHANGE_RATE);
        _info.claimedAmount = _info.claimedAmount.add(claimAmount);
        userFundInfo[_msgSender()] = _info;

        saleToken.safeTransfer(_msgSender(), swapAmount);

        emit Claimed(
            _msgSender(),
            address(saleToken),
            swapAmount,
            exchangeRate
        );
    }

    function _isWhiteListed(bytes32[] memory _proof, uint32 _index)
        internal
        view
        returns (bool)
    {
        require(saleTokenMerkleRootWhiteList != 0, "Stake: whitelist not set");
        bytes32 leaf = keccak256(abi.encodePacked(_msgSender()));

        return
            MerkleProof.verify(
                leaf,
                saleTokenMerkleRootWhiteList,
                _proof,
                _index
            );
    }
}
