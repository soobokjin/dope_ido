// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Fund} from  './assets/Fund.sol';

import {Stake} from './assets/Stake.sol';

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

    function changeOwner (address _owner) public {
        require(msg.sender == owner, "only owner can change");
        emit OwnerChanged(owner, _owner);
        owner = _owner;
    }

    function createDope (
        address _stakeTokenAddress,
        uint256 _minLockupAmount,
        uint256 _requiredStakeAmount,
        uint32 _requiredRetentionPeriod,
        address _treasuryAddress,
        address _exchangeTokenAddress
    ) public returns (address stakeAddress, address fundAddress) {
        stakeAddress = _deployStake(
            _stakeTokenAddress,
            _minLockupAmount,
            _requiredStakeAmount,
            _requiredRetentionPeriod
        );
        fundAddress = _deployFund(
            _treasuryAddress,
            _exchangeTokenAddress,
            stakeAddress
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
        IStake stake = new Stake(
            _stakeTokenAddress,
            _minLockupAmount,
            _requiredStakeAmount,
            _requiredRetentionPeriod
        );
        stake.transferOwnership(msg.sender);

        return address(stake);
    }

    function _deployFund (
        address _treasuryAddress,
        address exchangeTokenAddress,
        address stakeAddress
    ) private returns (address) {
        IFund fund = new Fund(
            _treasuryAddress,
            exchangeTokenAddress,
            stakeAddress
        );
        fund.transferOwnership(msg.sender);

        return address(fund);
    }


}
