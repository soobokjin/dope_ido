// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Fund} from  './assets/Fund.sol';
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Stake, IStake} from './assets/Stake.sol';

contract DopeFactory {
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);

    event ContractCreated(
        address indexed stake,
        address indexed fund
    );

    struct Dope {
        address stake;
        address fund;
    }

    address public owner;
    Dope[] public createdDopeList;

    constructor() {
        owner = msg.sender;
        emit OwnerChanged(address(0), msg.sender);
    }

//    function changeOwner (address _owner) public {
//        require(msg.sender == owner, "only owner can change");
//        emit OwnerChanged(owner, _owner);
//        owner = _owner;
//    }

    function createDope (
        // stake
        address _stakeTokenAddress,
        uint256 _minLockupAmount,
        uint256 _requiredStakeAmount,
        uint32 _requiredRetentionPeriod,
        // fund
        address _saleTokenAddress,
        address _exchangeTokenAddress,
        address _treasuryAddress
    ) public returns (address stakeAddress, address fundAddress) {
        // initialize with metadata
        // set period

        // give ownership to others

        stakeAddress = _deployStake(
            _stakeTokenAddress,
            _minLockupAmount,
            _requiredStakeAmount,
            _requiredRetentionPeriod
        );

        fundAddress = _deployFund(
            _saleTokenAddress,
            _exchangeTokenAddress,
            stakeAddress,
            _treasuryAddress
        );

         createdDopeList.push(Dope({stake: stakeAddress, fund: fundAddress}));
         emit ContractCreated(stakeAddress, fundAddress);
    }

    function _deployStake (
        address _stakeTokenAddress,
        uint256 _minLockupAmount,
        uint256 _requiredStakeAmount,
        uint32 _requiredRetentionPeriod
    ) private returns (address) {
        Stake stake = new Stake();
        bytes memory payload = stake.initPayload(
            _stakeTokenAddress,
            _minLockupAmount,
            _requiredStakeAmount,
            _requiredRetentionPeriod
        );
        stake.initialize(payload);
        stake.transferOwnership(msg.sender);

        return address(stake);
    }

    function _deployFund (
        address _saleTokenAddress,
        address exchangeTokenAddress,
        address stakeAddress,
        address _treasuryAddress
    ) private returns (address) {
        Fund fund = new Fund{
        salt : keccak256(abi.encode(_saleTokenAddress, exchangeTokenAddress, stakeAddress, _treasuryAddress))
        }();
        fund.transferOwnership(msg.sender);

        return address(fund);
    }


}
