// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Fund} from  './assets/Fund.sol';
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Fund, IFund} from './assets/Fund.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

contract DopeFactory is Ownable {
    event FundCreated(address indexed fund);

    address public implementation;
    address[] public fundList;

    constructor() {
        Fund fund = new Fund();
        bytes memory payload = fund.initPayload(
            address(0x0),
            address(0x0),
            address(0x0),
            address(0x0)
        );
        fund.initialize(payload);
        implementation = address(fund);
    }

    function getFundAddressOf(uint32 index) public view returns (address) {
        return fundList[index];
    }

    function createFund (
        address _saleTokenAddress,
        address _exchangeTokenAddress,
        address _stakeAddress,
        address _treasuryAddress
    ) public returns (address stakeAddress) {
        address instance = Clones.cloneDeterministic(
            implementation,
            keccak256(abi.encode(_saleTokenAddress, _exchangeTokenAddress, _stakeAddress, _treasuryAddress))
        );
        bytes memory payload = IFund(instance).initPayload(
            _saleTokenAddress, _exchangeTokenAddress, _stakeAddress, _treasuryAddress
        );
        Fund(instance).initialize(payload);
        fundList.push(instance);

        Fund(instance).transferOwnership(msg.sender);
        emit FundCreated(instance);
        return instance;
    }
}
