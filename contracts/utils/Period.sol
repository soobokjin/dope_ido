pragma solidity ^0.8.0;

import {SafeMath} from '@openzeppelin/contracts/utils/math/SafeMath.sol';
import {Context, Ownable} from '@openzeppelin/contracts/access/Ownable.sol';


struct Period {
    uint256 start;
    uint256 end;
}

interface IIDOPeriod {
    enum Phase { Stake, Fund, DepositLoan, Borrow, Claim }

    function getStartAndEndPhaseOf(Phase phase) external view returns (uint256, uint256);
    function getCurrentPhases() external view returns (bool[] memory);
    function phaseIn(Phase phase) external view returns (bool);
}

contract IDOPeriod is Context, Ownable {
    enum Phase { Stake, Fund, DepositLoan, Borrow, Claim }

    Phase[5] private _phases = [Phase.Stake, Phase.Fund, Phase.DepositLoan, Phase.Borrow, Phase.Claim];
    mapping (Phase => Period) private _phasePeriod;

    function isValidPeriod(uint256 start, uint256 end) internal pure returns (bool) {
        return (start <= end);
    }

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
        require(isValidPeriod(_startStakeBlockNum, _endStakeBlockNum), 'invalid stake period');
        require(isValidPeriod(_startFundBlockNum, _endFundBlockNum), 'invalid fund period');
        require(isValidPeriod(_startDepositLoanBlockNum, _endDepositLoanBlockNum), 'invalid deposit period');
        require(isValidPeriod(_startBorrowBlockNum, _endBorrowBlockNum), 'invalid borrow period');

        _phasePeriod[Phase.Stake] = Period(_startStakeBlockNum, _endStakeBlockNum);
        _phasePeriod[Phase.Fund] = Period(_startFundBlockNum, _endFundBlockNum);
        _phasePeriod[Phase.DepositLoan] = Period(_startDepositLoanBlockNum, _endDepositLoanBlockNum);
        _phasePeriod[Phase.Borrow] = Period(_startBorrowBlockNum, _endBorrowBlockNum);
        _phasePeriod[Phase.Claim] = Period(_startClaimBlockNum, 2**256 - 1);
    }

    function getStartAndEndPhaseOf (Phase phase) external virtual view returns (uint256, uint256) {
        return (_phasePeriod[phase].start, _phasePeriod[phase].end);
    }

    function getCurrentPhases() external virtual view returns (bool[] memory) {
        bool[] memory phases = new bool[](_phases.length);

        for (uint8 i=0; i < _phases.length; i++ ) {
            if (block.number >= _phasePeriod[_phases[i]].start  && block.number <= _phasePeriod[_phases[i]].end) {
                phases[i]= true;
            }
        }
        return phases;
    }

    function phaseIn (Phase phase) external virtual view returns (bool) {
        return (block.number >= _phasePeriod[phase].start && block.number <= _phasePeriod[phase].end);
    }
}
