// SPDX-License-Identifier: MIT
// solidity coveragy
// gas-reporter

pragma solidity >=0.8.0 <0.9.0;

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
        address _treasuryAddress,
        uint256 _fundStartTime,
        uint256 _fundingPeriod,
        uint256 _releaseTime
    ) public returns (address stakeAddress) {
        address instance = Clones.cloneDeterministic(
            implementation,
            keccak256(abi.encode(_saleTokenAddress, _exchangeTokenAddress, _stakeAddress, _treasuryAddress))
        );
        Fund fundInstance = Fund(instance);
        bytes memory payload = fundInstance.initPayload(
            _saleTokenAddress, _exchangeTokenAddress, _stakeAddress, _treasuryAddress
        );
        fundInstance.initialize(payload);
        fundInstance.setPeriod(_fundStartTime, _fundingPeriod, _releaseTime);
        fundInstance.transferOwnership(msg.sender);

        fundList.push(instance);
        emit FundCreated(instance);

        return instance;
    }
}
