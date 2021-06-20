// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Fund} from  './assets/Fund.sol';
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Stake, IStake} from './assets/Stake.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import "hardhat/console.sol";

contract StakeFactory is Ownable {
    event StakeCreated(
        address indexed stake
    );

    address public implementation;
    address[] public stakeList;

    constructor() {
        Stake stake = new Stake();
        bytes memory payload = stake.initPayload(
            address(0x0),
            0,
            0,
            0
        );
        stake.initialize(payload);
        implementation = address(stake);
    }

    function getStakeAddressOf(uint32 index) public view returns (address) {
        return stakeList[index];
    }

    function createStake(
        // stake
        address _stakeTokenAddress,
        uint256 _minLockupAmount,
        uint256 _requiredStakeAmount,
        uint32 _requiredRetentionPeriod,
        uint256 _startTime,
        uint256 _period
    ) public onlyOwner returns (address) {
        address instance = Clones.clone(implementation);
        Stake stakeInstance = Stake(instance);
        bytes memory payload = stakeInstance.initPayload(
            _stakeTokenAddress, _minLockupAmount, _requiredStakeAmount, _requiredRetentionPeriod
        );
        stakeInstance.initialize(payload);
        stakeInstance.setPeriod(_startTime, _period);
        stakeInstance.transferOwnership(msg.sender);

        stakeList.push(instance);
        emit StakeCreated(instance);

        return instance;
    }

}
