// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

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
        stake.initialize();
        implementation = address(stake);
    }

    function getStakeAddressOf(uint32 index) public view returns (address) {
        return stakeList[index];
    }

    function createStake(
        address _stakeTokenAddress
    ) public onlyOwner returns (address) {
        address instance = Clones.clone(implementation);
        Stake stakeInstance = Stake(instance);
        stakeInstance.initialize();
        stakeInstance.registerStakeToken(_stakeTokenAddress);
        stakeInstance.transferOwnership(msg.sender);

        stakeList.push(instance);
        emit StakeCreated(instance);

        return instance;
    }

}
