// SPDX-License-Identifier: MIT
// TODO: 0.9.0
pragma solidity >=0.8.0 <0.9.0;

import {SafeMath} from '@openzeppelin/contracts/utils/math/SafeMath.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {Context, Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {Initializable} from '@openzeppelin/contracts/proxy/utils/Initializable.sol';

import {Operator} from '../access/Operator.sol';
import {MerkleProof} from '../utils/MerkleProof.sol';

import "hardhat/console.sol";


// TODO: register

interface IStake {
    function initialize () external;
    event Staked(
        address indexed user,
        address indexed stakeTokenAddress,
        uint256 stakeAmount,
        uint256 totalStakedAmount,
        uint256 blockTime
    );
    event UnStaked(
        address indexed user,
        address indexed stakeTokenAddress,
        uint256 unStakeAmount,
        uint256 totalStakedAmount,
        uint256 blockTime
    );
}


contract Stake is IStake, Operator, Initializable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using SafeMath for uint32;
    using SafeMath for uint8;

    event Staked(
        address indexed user,
        address indexed stakeTokenAddress,
        uint256 stakeAmount,
        uint256 totalStakedAmount,
        uint256 blockTime
    );

    event UnStaked(
        address indexed user,
        address indexed stakeTokenAddress,
        uint256 unStakeAmount,
        uint256 totalStakedAmount,
        uint256 blockTime
    );

    event StakeTokenRegistered(
        address stakeTokenAddress
    );

    event StakeTokenActiveChanged(
        address stakeTokenAddress,
        bool isActive
    );

    struct StakeInfo {
        uint[] stakeChangedBlockTimeList;
        mapping(uint256 => uint256) stakeAmountByBlockTime;
    }

    struct StakeTokenInfo {
        bool isRegistered;
        bool isActive;
    }

    // TODO: mapping key should be sale token and struct user info
    // [{a, a}] , storage 접근 X)
    // prettier, prettier-plugin-solidity
    mapping(address => mapping(address => StakeInfo)) userStakeInfoByStakeToken;
    mapping(address => StakeTokenInfo) stakeTokenInfo;

    modifier isRegistered (address _stakeTokenAddress) {
        require(stakeTokenInfo[_stakeTokenAddress].isRegistered == true, "Stake: stake token not registered");
        _;
    }

    modifier isActivated (address _stakeTokenAddress) {
        require(stakeTokenInfo[_stakeTokenAddress].isActive == true, "Stake: stake token not activated");
        _;
    }

    function initialize () public override initializer {
        setRole(_msgSender(), _msgSender());
    }

    function registerStakeToken(address _stakeTokenAddress) public onlyOwner {
        bool isRegistered = true;
        bool isActive = true;
        stakeTokenInfo[_stakeTokenAddress] = StakeTokenInfo(isRegistered, isActive);

        emit StakeTokenRegistered(_stakeTokenAddress);
        emit StakeTokenActiveChanged(_stakeTokenAddress, isActive);
    }

    function changeStakeTokenActivation(
        address _stakeTokenAddress,
        bool _active
    ) isRegistered(_stakeTokenAddress) public onlyOwner {
        StakeTokenInfo memory tokenInfo = stakeTokenInfo[_stakeTokenAddress];
        tokenInfo.isActive = _active;

        stakeTokenInfo[_stakeTokenAddress] = tokenInfo;

        emit StakeTokenActiveChanged(_stakeTokenAddress, _active);
    }

    function IsStakeTokenRegistered (address _stakeTokenAddress) public view returns (bool) {
        return stakeTokenInfo[_stakeTokenAddress].isRegistered;
    }

    function IsStakeTokenActivated (address _stakeTokenAddress) public view returns (bool) {
        return stakeTokenInfo[_stakeTokenAddress].isActive;
    }

    function getCurrentStakeAmount (
        address _user,
        address _stakeTokenAddress
    ) public view  isRegistered(_stakeTokenAddress) returns (uint256) {
        StakeInfo storage userStakeInfo = userStakeInfoByStakeToken[_stakeTokenAddress][_user];
        uint256 length = userStakeInfo.stakeChangedBlockTimeList.length;
        if (length == 0) {
            return 0;
        }

        uint256 lastBlockTime = userStakeInfo.stakeChangedBlockTimeList[length.sub(1)];
        return userStakeInfo.stakeAmountByBlockTime[lastBlockTime];
    }

    function getStakeAmountByBlockTime (
        address _user,
        address _stakeTokenAddress,
        uint256 _blockTime
    ) public view  isRegistered(_stakeTokenAddress) returns (uint256) {
        return userStakeInfoByStakeToken[_stakeTokenAddress][_user].stakeAmountByBlockTime[_blockTime];
    }

    function stake (
        address _stakeTokenAddress,
        uint256 _amount
    ) public isRegistered(_stakeTokenAddress) isActivated(_stakeTokenAddress) {
        IERC20(_stakeTokenAddress).safeTransferFrom(_msgSender(), address(this), _amount);
        StakeInfo storage userStakeInfo = userStakeInfoByStakeToken[_stakeTokenAddress][_msgSender()];
        _increaseStakeInfo(userStakeInfo, _amount);

        emit Staked(
            _msgSender(),
            _stakeTokenAddress,
            _amount,
            userStakeInfo.stakeAmountByBlockTime[block.timestamp],
            block.timestamp
        );
    }

    function _increaseStakeInfo(StakeInfo storage _userStakeInfo, uint256 _amount) private {
        uint256 historyLength = _userStakeInfo.stakeChangedBlockTimeList.length;

        _userStakeInfo.stakeChangedBlockTimeList.push(block.timestamp);
        if (historyLength == 0) {
            _userStakeInfo.stakeAmountByBlockTime[block.timestamp] = _amount;
        }
        else {
            uint256 stakedAmount = _getUserStakeAmount(_userStakeInfo, historyLength);
            _userStakeInfo.stakeAmountByBlockTime[block.timestamp] = stakedAmount.add(_amount);
        }
    }

    function unStake (address _stakeTokenAddress, uint256 _amount) public isRegistered(_stakeTokenAddress) {
        StakeInfo storage userStakeInfo = userStakeInfoByStakeToken[_stakeTokenAddress][_msgSender()];
        uint256 historyLength = userStakeInfo.stakeChangedBlockTimeList.length;
        require(historyLength > 0, "Stake: stake amount is 0");
        uint256 stakedAmount = _getUserStakeAmount(userStakeInfo, historyLength);
        require(stakedAmount >= _amount, "Stake: invalid amount. stakedAmount < amount");

        userStakeInfo.stakeChangedBlockTimeList.push(block.timestamp);
        userStakeInfo.stakeAmountByBlockTime[block.timestamp] = stakedAmount.sub(_amount);

        IERC20(_stakeTokenAddress).safeTransfer(_msgSender(), _amount);

        emit UnStaked(
            _msgSender(),
            _stakeTokenAddress,
            _amount,
            userStakeInfo.stakeAmountByBlockTime[block.timestamp],
            block.timestamp
        );
    }

    function _getUserStakeAmount(
        StakeInfo storage _userStakeInfo,
        uint256 _blockTimeListLength
    ) internal view returns (uint256) {
        uint256 lastChangedBlockTime = _userStakeInfo.stakeChangedBlockTimeList[_blockTimeListLength.sub(1)];
        return _userStakeInfo.stakeAmountByBlockTime[lastChangedBlockTime];
    }
}
