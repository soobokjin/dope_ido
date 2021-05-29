import { ethers, network } from "hardhat";
import chai from "chai";
import { solidity } from "ethereum-waffle";
import { Contract, ContractFactory } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { accumulateBlockByBlockNumber, accumulateBlockByBlockCnt } from "./utils";
import {deflateRawSync} from "zlib";

chai.use(solidity);
const { expect } = chai;

describe("DOPE", () => {

    const saleTokenMintAmount: number = 10 ** 10;
    let dopeOwner: SignerWithAddress;
    let tokenOwner: SignerWithAddress;
    let investor: SignerWithAddress;
    let lender: SignerWithAddress;

    let DOPE: ContractFactory;
    let saleToken: ContractFactory;
    let Period: ContractFactory;

    let dopeContract: Contract;
    let saleTokenContract: Contract;
    let stableTokenContract: Contract;
    let dopeTokenContract: Contract;
    let PeriodContract: Contract;

    let startStakeBlockNum: number = 0;
    let endStakeBlockNum: number = 19;
    let startFundBlockNum: number = endStakeBlockNum + 1;
    let endFundBlockNum: number = startFundBlockNum + 19;
    let startDepositLoanBlockNum: number = endFundBlockNum + 1;
    let endDepositLoanBlockNum: number = startDepositLoanBlockNum + 19;
    let startBorrowBlockNum: number = endDepositLoanBlockNum + 1;
    let endBorrowBlockNum: number = startBorrowBlockNum + 19;
    let startClaimBlockNum: number = endBorrowBlockNum + 1;

    before("Setup accounts", async () => {
       [tokenOwner, dopeOwner, investor, lender] = await ethers.getSigners();
    });

    before("fetch token contract factories", async () => {
       saleToken = await ethers.getContractFactory('ERC20Mintable');
       saleTokenContract = await saleToken.connect(tokenOwner).deploy(
            "saleToken",
            "STN",
            saleTokenMintAmount
        );
       stableTokenContract = await saleToken.connect(tokenOwner).deploy(
            "stableToken",
            "USD",
            saleTokenMintAmount
        );
       dopeTokenContract = await saleToken.connect(tokenOwner).deploy(
            "DOPEToken",
            "DOPE",
            saleTokenMintAmount
        );
    });
    let investorTokenAmount = 100000;
    let lenderTokenAmount = 100000;
    before("share token to investor and lender", async () => {
        await stableTokenContract.connect(tokenOwner).transfer(investor.address, investorTokenAmount)
        await stableTokenContract.connect(tokenOwner).transfer(lender.address, lenderTokenAmount)
    });

    before("fetch period contract factory", async () => {
       Period = await ethers.getContractFactory('IDOPeriod');
       PeriodContract = await Period.connect(dopeOwner).deploy(
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


    before("fetch dope contract factories", async () => {
       DOPE = await ethers.getContractFactory('DOPE');
       dopeContract = await DOPE.connect(dopeOwner).deploy(
            'STN',
            saleTokenContract.address,
            saleTokenMintAmount,
            stableTokenContract.address,
            tokenOwner.address,
            dopeTokenContract.address,
            PeriodContract.address,
            10 ** 6,
            1000,
            5000,
       );
       await saleTokenContract.connect(tokenOwner).approve(dopeContract.address, saleTokenMintAmount);
       await dopeContract.connect(tokenOwner).putSaleToken();
       expect(await saleTokenContract.balanceOf(tokenOwner.address)).to.eq(0);
       expect(await saleTokenContract.balanceOf(dopeContract.address)).to.eq(10000000000);
    });

    it("stake and unStake", async () => {
        await dopeTokenContract.connect(tokenOwner).approve(dopeContract.address, 1000);
        await dopeContract.connect(tokenOwner).stake(1000);
        await expect(await dopeContract.getStakeAmountOf(tokenOwner.address)).to.eq(1000);
        await dopeContract.connect(tokenOwner).unStake(1000);
        await expect(await dopeContract.getStakeAmountOf(tokenOwner.address)).to.eq(0);
        await accumulateBlockByBlockNumber(startFundBlockNum);
        await expect(dopeContract.connect(tokenOwner).stake(1000)).to.be.revertedWith("not in stake period");
    });

    it("deposit token and lend token from it", async () => {
        // lender Deposit 10000 token
        await stableTokenContract.connect(lender).approve(dopeContract.address, 10000);
        await dopeContract.connect(lender).depositTokenForLend(10000);
        expect(await dopeContract.getDepositedAmount(lender.address)).to.eq(10000);

        // investor Fund 10000 token
        await stableTokenContract.connect(investor).approve(dopeContract.address, 10000);
        await dopeContract.connect(investor).fundSaleToken(10000);
        // expect(await dopeContract.getShareAndCollateral(investor.address)).to.eq([10000, 0]);

        // investor lend 1000 token (Collateral should be 2000)
        await dopeContract.connect(investor).borrow(1000);
        // expect(await dopeContract.getShareAndCollateral(investor.address)).to.eq([10000, 1000]);

        // investor repay 1000 token (Collateral should be 0 and share should be 9800)
        await stableTokenContract.connect(investor).approve(dopeContract.address, 1000);
        await dopeContract.connect(investor).repay(1000);
        // expect(await dopeContract.getShareAndCollateral(investor.address)).to.eq([10000, 1000]);

        // lender withdraw token (200 dope token and 10000 stable token should get)
        await dopeContract.connect(lender).withdrawLentToken();
        expect(await stableTokenContract.balanceOf(lender.address)).to.eq(lenderTokenAmount);
        expect(await saleTokenContract.balanceOf(lender.address)).to.eq(200);

        // investor claim token (100 dope token and 10000 stable token should get)
        await dopeContract.connect(investor).claim();
        expect(await saleTokenContract.balanceOf(investor.address)).to.eq(9800);
    });
});