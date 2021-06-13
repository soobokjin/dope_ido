import { ethers, network } from "hardhat";
import chai from "chai";
import { solidity } from "ethereum-waffle";
import { BigNumber, Contract, ContractFactory } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { increaseTime, latestBlocktime } from "../../utils";

chai.use(solidity);
const {expect} = chai;


describe("Stake", () => {
    const MINUTES: number = 60;
    const HOUR: number = MINUTES * 60;
    const DAY: number = HOUR * 24;

    const saleTokenMintAmount: number = 10 ** 10;
    let minStakeAmount: number = 10000;
    let minRetentionPeriod: number = 1;
    let stakeOwner: SignerWithAddress;

    let stake: ContractFactory;
    let stakeToken: ContractFactory;

    let stakeContract: Contract;
    let stakeTokenContract: Contract;

    before("Setup accounts", async () => {
        [stakeOwner] = await ethers.getSigners();
    });

    beforeEach("fetch token contract factories", async () => {
        stakeToken = await ethers.getContractFactory('ERC20Mintable');
        stakeTokenContract = await stakeToken.connect(stakeOwner).deploy(
            "stakeToken",
            "STK",
            saleTokenMintAmount
        );
    });

    beforeEach("fetch stake contract factories", async () => {
        let defaultTimeBefore: number = DAY
        stake = await ethers.getContractFactory('Stake');
        stakeContract = await stake.connect(stakeOwner).deploy(
            stakeTokenContract.address,
            minStakeAmount,
            minRetentionPeriod,
        );

        // set on stake period
        await stakeContract.connect(stakeOwner).setPeriod(
            await latestBlocktime() - defaultTimeBefore,
            defaultTimeBefore + DAY
        );
    });

    it("when try to stake before stake period, should revert", async () => {
        let stakeAmount: number = 100000;
        let timeAfter: number = HOUR;
        await stakeContract.connect(stakeOwner).setPeriod(
            await latestBlocktime() + timeAfter,
            timeAfter
        );

        await stakeTokenContract.connect(stakeOwner).approve(stakeContract.address, stakeAmount);
        await expect(stakeContract.connect(stakeOwner).stake(stakeAmount)).to.be.revertedWith(
            "not stake period"
        );
        expect(await stakeContract.getCurrentStakeAmount(stakeOwner.address)).to.eq(0);
    });

    it("when try to stake after end stake period, should revert", async () => {
        let stakeAmount: number = 100000;
        let timeBefore: number = HOUR;
        await stakeContract.connect(stakeOwner).setPeriod(
            await latestBlocktime() - timeBefore,
            timeBefore - 1
        );

        await stakeTokenContract.connect(stakeOwner).approve(stakeContract.address, stakeAmount);
        await expect(stakeContract.connect(stakeOwner).stake(stakeAmount)).to.be.revertedWith(
            "not stake period"
        );
        expect(await stakeContract.getCurrentStakeAmount(stakeOwner.address)).to.eq(0);
    });

    it("when try to stake more than allowance amount, should revert", async () => {
        let stakeAmount: number = 100000;

        await stakeTokenContract.connect(stakeOwner).approve(stakeContract.address, stakeAmount);
        await expect(stakeContract.connect(stakeOwner).stake(stakeAmount + 1)).to.be.revertedWith(
            "insufficient allowance"
        );
        expect(await stakeContract.getCurrentStakeAmount(stakeOwner.address)).to.eq(0);
    });

    it("when stake under min stake amount, should revert", async () => {
        let stakeAmount: number = minStakeAmount - 1;

        await stakeTokenContract.connect(stakeOwner).approve(stakeContract.address, stakeAmount);
        await expect(stakeContract.connect(stakeOwner).stake(stakeAmount)).to.be.revertedWith(
            "insufficient amount"
        );
        expect(await stakeContract.getCurrentStakeAmount(stakeOwner.address)).to.eq(0);
    });

    it("success with valid stake amount", async () => {
        let stakeAmount: number = minStakeAmount + 1;
        let allowance_result: boolean = Boolean(
            await stakeTokenContract.connect(stakeOwner).increaseAllowance(stakeContract.address, stakeAmount)
        );
        expect(allowance_result).to.eq(true);
        await stakeContract.connect(stakeOwner).stake(stakeAmount);
        expect(await stakeContract.getCurrentStakeAmount(stakeOwner.address)).to.eq(stakeAmount);
    });
});
