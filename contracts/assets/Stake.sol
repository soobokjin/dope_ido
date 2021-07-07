// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeMath} from '@openzeppelin/contracts/utils/math/SafeMath.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {Context, Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {Initializable} from '@openzeppelin/contracts/proxy/utils/Initializable.sol';

import {Operator} from '../access/Operator.sol';
import {MerkleProof} from '../utils/MerkleProof.sol';

import "hardhat/console.sol";


interface IStake {
    function initialize (bytes memory args) external;
    function initPayload (
        address _stakeTokenAddress
    ) external pure returns (bytes memory);
    function isWhiteListed (
        address _user,
        address _saleToken,
        bytes32[] memory _proof,
        uint32 _index
    ) external returns (bool);
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

    struct StakeInfo {
        uint[] stakeChangedBlockTimeList;
        mapping(uint256 => uint256) stakeAmountByBlockTime;
    }

    // TODO: mapping key should be sale token and struct user info
    mapping(address => mapping(address => StakeInfo)) userStakeInfoByStakeToken;
    mapping(address => mapping(address => uint[])) userStakeChangedBlockTime;
    mapping(address => mapping(address => mapping(uint256 => uint256))) userStakeAmountByBlockTime;
    mapping(address => bytes32) saleTokenMerkleRootWhiteList;
    mapping(address => bool) isStakeToken;


    modifier isRegistered (address _stakeTokenAddress) {
        require(isStakeToken[_stakeTokenAddress] == true, "Stake: invalid stake token");
        _;
    }

    function initialize () public override initializer {
        setRole(_msgSender(), _msgSender());
    }

    function setStakeToken (address _stakeTokenAddress) public onlyOwner {
        isStakeToken[_stakeTokenAddress] = true;
    }

    function getCurrentStakeAmount (
        address _user,
        address _stakeTokenAddress
    ) public view  isRegistered(_stakeTokenAddress) returns (uint256) {
        StakeInfo memory userStakeInfo = userStakeInfoByStakeToken[_stakeTokenAddress][_user];
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

    function registerSaleTokenWhiteList(
        address _saleToken,
        bytes32 _saleTokenMerkleRootWhiteList
    ) public onlyOwner {
        saleTokenMerkleRootWhiteList[_saleToken] = _saleTokenMerkleRootWhiteList;
    }

    function stake (
        uint256 _amount,
        address _stakeTokenAddress
    ) public isRegistered(_stakeTokenAddress) {
        IERC20(_stakeTokenAddress).safeTransferFrom(_msgSender(), address(this), _amount);
        StakeInfo memory userStakeInfo = userStakeInfoByStakeToken[_stakeTokenAddress][_msgSender()];
        _updateStakeInfo(userStakeInfo, _amount);

        emit Staked(
            _msgSender(),
            _stakeTokenAddress,
            _amount,
            userStakeInfo.stakeAmountByBlockTime[block.timestamp],
            block.timestamp
        );
    }

    function _updateStakeInfo (StakeInfo memory _userStakeInfo, uint256 _amount) private {
        StakeInfo memory userStakeInfo = userStakeInfoByStakeToken[_stakeTokenAddress][_msgSender()];
        uint256 historyLength = _userStakeInfo.stakeAmountByBlockTime.length;

        _userStakeInfo.stakeChangedBlockTimeList.push(block.timestamp);
        if (historyLength == 0) {
            _userStakeInfo.stakeChangedBlockTimeList[block.timestamp] = _amount;
        }
        else {
            uint256 stakedAmount = _getUserStakeAmount(_stakeTokenAddress);
            _userStakeInfo.stakeChangedBlockTimeList[block.timestamp] = stakedAmount.add(_amount);
        }

        userStakeInfoByStakeToken[_stakeTokenAddress][_msgSender()] = userStakeInfo;
    }

    function unStake (uint256 _amount, address _stakeTokenAddress) public isRegistered(_stakeTokenAddress) {
        StakeInfo memory userStakeInfo = userStakeInfoByStakeToken[_stakeTokenAddress][_msgSender()];
        require(userStakeInfo.stakeChangedBlockTimeList.length > 0, "Stake: stake amount is 0");
        uint256 stakedAmount = _getUserStakeAmount(userStakeInfo, _stakeTokenAddress);
        require(stakedAmount >= _amount, "invalid amount. stakedAmount < amount");

        userStakeInfo.stakeChangedBlockTimeList.push(block.timestamp);
        userStakeInfo.stakeAmountByBlockTime[block.timestamp] = stakedAmount.sub(_amount);
        userStakeInfoByStakeToken[_stakeTokenAddress][_msgSender()] = userStakeInfo;
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
        StakeInfo memory _userStakeInfo,
        uint256 _blockTimeListLength
    ) internal view returns (uint256) {
        uint256 lastChangedBlockTime = _userStakeInfo.stakeChangedBlockTimeList[_blockTimeListLength.sub(1)];
        return _userStakeInfo.stakeAmountByBlockTime[lastChangedBlockTime];
    }

    function isWhiteListed (
        address _user,
        address _saleToken,
        bytes32[] memory _proof,
        uint32 _index
    ) external view override returns (bool) {
        require(saleTokenMerkleRootWhiteList[_saleToken] != 0, "Stake: whitelist not set");

        return MerkleProof.verify(
            keccak256(abi.encodePacked(_user)),
            saleTokenMerkleRootWhiteList[_saleToken],
            _proof,
            _index
        );
    }
}
