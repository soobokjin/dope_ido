pragma solidity ^0.8.0;

import {SafeMath} from '@openzeppelin/contracts/utils/math/SafeMath.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {Context, Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

struct Period {
    uint256 start;
    uint256 end;
}

enum Phase { Stake, Fund, DepositLoan, Borrow, Claim }


contract IDOPeriod is Context, Ownable {
    Phase[5] private _phases = [Phase.Stake, Phase.Fund, Phase.DepositLoan, Phase.Borrow, Phase.Claim];
    mapping (Phase => Period) private _phasePeriod;

    constructor (
        uint256 _startStakeBlockNum,
        uint256 _endStakeBlockNum,
        uint256 _startFundBlockNum,
        uint256 _endFundBlockNum,
        uint256 _startDepositLoanBlockNum,
        uint256 _endDepositLoanBlockNum,
        uint256 _startBorrowBlockNum,
        uint256 _endBorrowBlockNum,
        uint256 _startClaimBlockNum
    ) {
        _phasePeriod[Phase.Stake] = Period(_startStakeBlockNum, _endStakeBlockNum);
        _phasePeriod[Phase.Fund] = Period(_startFundBlockNum, _endFundBlockNum);
        _phasePeriod[Phase.DepositLoan] = Period(_startDepositLoanBlockNum, _endDepositLoanBlockNum);
        _phasePeriod[Phase.Borrow] = Period(_startBorrowBlockNum, _endBorrowBlockNum);
        _phasePeriod[Phase.Claim] = Period(_startClaimBlockNum, 2**256 - 1);
    }

    function getStartAndEndPhaseOf (Phase phase) public view returns (uint256, uint256) {
        return (_phasePeriod[phase].start, _phasePeriod[phase].end);
    }

    function getCurrentPhases() public view returns (bool[] memory) {
        bool[] memory phases = new bool[](_phases.length);

        for (uint8 i=0; i < _phases.length; i++ ) {
            if (block.number >= _phasePeriod[_phases[i]].start  && block.number <= _phasePeriod[_phases[i]].end) {
                phases[i]= true;
            }
        }

        return phases;
    }

    function isPhaseIn (Phase phase) public view returns (bool) {
        return (block.number >= _phasePeriod[phase].start && block.number <= _phasePeriod[phase].end);
    }

}
