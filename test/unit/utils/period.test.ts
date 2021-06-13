import { ethers, network } from "hardhat";
import chai from "chai";
import { solidity } from "ethereum-waffle";
import {BigNumber, Contract, ContractFactory} from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { accumulateBlockByBlockNumber, accumulateBlockByBlockCnt } from "../../utils";

chai.use(solidity);
const { expect } = chai;

describe("DOPE", () => {

    let periodOwner: SignerWithAddress;
    let Period: ContractFactory;
    let periodContract: Contract;
    let startStakeBlockNum: number = 0;
    let endStakeBlockNum: number = 9;
    let startFundBlockNum: number = 10;
    let endFundBlockNum: number = 19;
    let startDepositLoanBlockNum: number = 20;
    let endDepositLoanBlockNum: number = 29;
    let startBorrowBlockNum: number = 30;
    let endBorrowBlockNum: number = 49;
    let startClaimBlockNum: number = 50;

    before("Setup accounts", async () => {
       [periodOwner] = await ethers.getSigners();
    });

    before("fetch Period contract factories", async () => {
       Period = await ethers.getContractFactory('IDOPeriod');
       periodContract = await Period.connect(periodOwner).deploy(
           startStakeBlockNum,
           endStakeBlockNum,
           startFundBlockNum,
           endFundBlockNum,
           startDepositLoanBlockNum,
           endDepositLoanBlockNum,
           startBorrowBlockNum,
           endBorrowBlockNum,
           startClaimBlockNum
       );
    });

    it("period", async () => {
        let phaseInfo = await periodContract.getStartAndEndPhaseOf(0)
        expect(phaseInfo).to.eql([BigNumber.from(0), BigNumber.from(9)]);
        expect(await periodContract.getCurrentPhases()).to.eql([true, false, false, false, false]);
        await accumulateBlockByBlockNumber(startFundBlockNum)
        expect(await periodContract.getCurrentPhases()).to.eql([false, true, false, false, false]);
        await accumulateBlockByBlockNumber(startDepositLoanBlockNum)
        expect(await periodContract.getCurrentPhases()).to.eql([false, false, true, false, false]);
        await accumulateBlockByBlockNumber(startBorrowBlockNum)
        expect(await periodContract.getCurrentPhases()).to.eql([false, false, false, true, false]);
    });

});
