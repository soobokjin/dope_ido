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
        address _stakeTokenAddress,
        uint256 _minLockupAmount,
        uint256 _requiredStakeAmount,
        uint32 _requiredRetentionPeriod
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

    mapping(address => mapping(address => uint[])) userStakeChangedBlockTime;
    mapping(address => mapping(address => mapping(uint256 => uint256))) userStakeAmountByBlockTime;
    mapping(address => bool) isStakeToken;
    mapping(address => bytes32) saleTokenWhiteListMerkleRoot;


    modifier isRegistered (address _stakeTokenAddress) {
        require(isStakeToken[_stakeTokenAddress] == true, "Stake: invalid stake token");
        _;
    }

    function initialize (bytes memory args) public override initializer {
        (
            address _stakeTokenAddress
        ) = abi.decode(args, (address));
        isStakeToken[_stakeTokenAddress] = true;

        setRole(_msgSender(), _msgSender());
    }

    function initPayload (
        address _stakeTokenAddress
    ) public pure override returns (bytes memory) {
        return abi.encode(
            _stakeTokenAddress
        );
    }

    function setStakeToken (address _stakeTokenAddress) public onlyOwner {
        isStakeToken[_stakeTokenAddress] = true;
    }

    function getCurrentStakeAmount (
        address _user,
        address _stakeTokenAddress
    ) public view  isRegistered(_stakeTokenAddress) returns (uint256) {
        uint256 length = userStakeChangedBlockTime[_user][_stakeTokenAddress].length;
        if (length == 0) {
            return 0;
        }
        uint256 lastBlockTime = userStakeChangedBlockTime[_user][length - 1];
        return userStakeAmountByBlockTime[_user][lastBlockTime];
    }

    function registerSaleTokenWhiteList(
        address _saleToken,
        bytes32 _saleTokenWhiteListMerkleRoot
    ) public onlyOwner {
        saleTokenWhiteListMerkleRoot[_saleToken] = _saleTokenWhiteListMerkleRoot;
    }

    function stake (uint256 _amount, address _stakeTokenAddress) public isRegistered(_stakeTokenAddress) {
        require(_amount >= minLockupAmount, "Stake: insufficient amount");
        IERC20(_stakeTokenAddress).safeTransferFrom(_msgSender(), address(this), _amount);
        _updateStakeInfo(_msgSender(), _stakeTokenAddress, _amount);

        emit Staked(
            _msgSender(),
            _stakeTokenAddress,
            _amount,
            userStakeAmountByBlockTime[_msgSender()][block.timestamp],
            block.timestamp
        );
    }

    function _updateStakeInfo (address _sender, address _stakeTokenAddress, uint256 _amount) private {
        uint256 historyLength = userStakeChangedBlockTime[_sender][_stakeTokenAddress].length;

        if (historyLength == 0) {
            userStakeChangedBlockTime[_sender][_stakeTokenAddress].push(block.timestamp);
            userStakeAmountByBlockTime[_sender][_stakeTokenAddress][block.timestamp] = _amount;
        }
        else {
            uint256 stakedAmount = _getUserStakeAmount();
            userStakeChangedBlockTime[_sender][_stakeTokenAddress].push(block.timestamp);
            userStakeAmountByBlockTime[_sender][_stakeTokenAddress][block.timestamp] = stakedAmount.add(_amount);
        }
    }

    function unStake (uint256 _amount, address _stakeTokenAddress) public isRegistered(_stakeTokenAddress) {
        require(userStakeChangedBlockTime[_msgSender()][_stakeTokenAddress].length > 0, "Stake: stake amount is 0");
        uint256 blockTime = block.timestamp;
        uint256 stakedAmount = _getUserStakeAmount();
        require(stakedAmount >= _amount, "invalid amount. stakedAmount < amount");

        userStakeChangedBlockTime[_msgSender()].push(blockTime);
        userStakeAmountByBlockTime[_msgSender()][blockTime] = stakedAmount.sub(_amount);
        IERC20(_stakeTokenAddress).safeTransfer(_msgSender(), _amount);

        emit UnStaked(
            _msgSender(), _stakeTokenAddress, _amount, userStakeAmountByBlockTime[_msgSender()][blockTime], blockTime
        );
    }

    function _getUserStakeAmount() internal view returns (uint256) {
        uint256 historyLength = userStakeChangedBlockTime[_msgSender()][_stakeTokenAddress].length;
        uint256 lastChangedBlockTime = userStakeChangedBlockTime[_msgSender()][_stakeTokenAddress][historyLength.sub(1)];

        return userStakeAmountByBlockTime[_msgSender()][_stakeTokenAddress][lastChangedBlockTime];
    }

    function isWhiteListed (
        address _user,
        address _saleToken,
        bytes32[] memory _proof,
        uint32 _index
    ) external view override returns (bool) {
        require(saleTokenWhiteListMerkleRoot[_saleToken] != 0, "Stake: whitelist not set");

        return MerkleProof.verify(
            _proof,
            saleTokenWhiteListMerkleRoot[_saleToken],
            keccak256(abi.encodePacked(_user)),
            _index
        );
    }
}
