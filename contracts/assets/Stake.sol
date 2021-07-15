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
    event StakeTokenRegistered(
        address stakeTokenAddress
    );
    event StakeTokenActiveChanged(
        address stakeTokenAddress,
        bool isActive
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

    struct StakeTokenInfo {
        bool isRegistered;
        bool isActive;
    }

    struct StakeHistory {
        uint256 stakedBlockTime;
        uint256 totalStakeAmount;
    }

    mapping(address => StakeTokenInfo) stakeTokenInfo;
    mapping(address => mapping(address => StakeHistory[])) userStakeHistories;

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
        stakeInfo[_stakeTokenAddress] = StakeTokenInfo(isRegistered, isActive);

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

    function isStakeTokenRegistered (address _stakeTokenAddress) public view returns (bool) {
        return stakeTokenInfo[_stakeTokenAddress].isRegistered;
    }

    function isStakeTokenActivated (address _stakeTokenAddress) public view returns (bool) {
        return stakeTokenInfo[_stakeTokenAddress].isActive;
    }

    function getCurrentStakeAmount (
        address _stakeTokenAddress,
        address _user
    ) public view  isRegistered(_stakeTokenAddress) returns (uint256) {
        StakeHistory[] memory stakeHistories = userStakeHistories[_stakeTokenAddress][_user];
        uint256 length = stakeHistories.length;
        if (length == 0) {
            return 0;
        }

        return stakeHistories[length.sub(1)].totalStakeAmount;
    }

    function getStakeHistoryByIndex (
        address _stakeTokenAddress,
        address _user,
        uint256 _index
    ) public view  isRegistered(_stakeTokenAddress) returns (uint256, uint256) {
        StakeHistory memory history = userStakeHistories[_stakeTokenAddress][_user][_index];

        return (history.totalStakeAmount, history.stakedBlockTime);
    }

    function getStakeHistoryLength (
        address _stakeTokenAddress,
        address _user
    ) public view  isRegistered(_stakeTokenAddress) returns (uint256) {
        return userStakeHistories[_stakeTokenAddress][_user].length;
    }

    function stake (
        address _stakeTokenAddress,
        uint256 _amount
    ) public isRegistered(_stakeTokenAddress) isActivated(_stakeTokenAddress) {
        IERC20(_stakeTokenAddress).safeTransferFrom(_msgSender(), address(this), _amount);

        uint256 increasedTotalStakedAmount = _increaseStakeInfo(_stakeTokenAddress, _amount);

        emit Staked(
            _msgSender(),
            _stakeTokenAddress,
            _amount,
            increasedTotalStakedAmount,
            block.timestamp
        );
    }

    function _increaseStakeInfo(address _stakeTokenAddress, uint256 _amount) internal returns (uint256) {
        StakeHistory[] memory stakeHistories = userStakeHistories[_stakeTokenAddress][_msgSender()];
        uint256 historyLength = stakeHistories.length;
        uint256 totalStakedAmount;

        if (historyLength == 0) {
            totalStakedAmount = _amount;
        }
        else {
            totalStakedAmount = stakeHistories[historyLength.sub(1)].totalStakeAmount.add(_amount);
        }
        userStakeHistories[_stakeTokenAddress][_msgSender()].push(StakeHistory(block.timestamp, totalStakedAmount));

        return totalStakedAmount;
    }

    function unStake (address _stakeTokenAddress, uint256 _amount) public isRegistered(_stakeTokenAddress) {
        StakeHistory[] memory stakeHistories = userStakeHistories[_stakeTokenAddress][_msgSender()];
        require(stakeHistories.length > 0, "Stake: stake amount is 0");
        totalStakedAmount = stakeHistories[stakeHistories.length.sub(1)].totalStakeAmount;
        require(totalStakedAmount >= _amount, "Stake: invalid amount. stakedAmount < amount");

        uint256 decreasedTotalStakedAmount = totalStakedAmount.sub(_amount);
        userStakeHistories[_stakeTokenAddress][_msgSender()].push(
            StakeHistory(block.timestamp, decreasedTotalStakedAmount)
        );
        IERC20(_stakeTokenAddress).safeTransfer(_msgSender(), _amount);

        emit UnStaked(
            _msgSender(),
            _stakeTokenAddress,
            _amount,
            decreasedTotalStakedAmount,
            block.timestamp
        );
    }
}
