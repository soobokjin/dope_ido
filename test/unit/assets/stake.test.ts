import {ethers, network} from "hardhat";
import chai from "chai";
import {solidity} from "ethereum-waffle";
import {BigNumber, Contract, ContractFactory} from "ethers";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import {increaseTime, latestBlocktime} from "../../utils";

chai.use(solidity);
const {expect} = chai;


describe("Stake", () => {
    const MINUTES: number = 60;
    const HOUR: number = MINUTES * 60;
    const DAY: number = HOUR * 24;

    const saleTokenMintAmount: number = 10 ** 10;
    let minLockUpAmount: number = 10000;
    let requiredStakeAmount: number = 100000;
    let requiredRetentionPeriod: number = 4 * DAY;
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
        let args;
        stake = await ethers.getContractFactory('Stake');
        stakeContract = await stake.connect(stakeOwner).deploy(

        );
        args = await stakeContract.initPayload(
            stakeTokenContract.address,
            minLockUpAmount,
            requiredStakeAmount,
            requiredRetentionPeriod,
        );

        // set on stake period
        await stakeContract.connect(stakeOwner).initialize(args);
        await stakeContract.connect(stakeOwner).setPeriod(
            await latestBlocktime() - defaultTimeBefore,
            defaultTimeBefore + DAY
        );
    });

    // ================================== Stake ==================================
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
        expect(await stakeTokenContract.balanceOf(stakeOwner.address)).to.eq(saleTokenMintAmount);
        expect(await stakeTokenContract.balanceOf(stakeContract.address)).to.eq(0);
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
        expect(await stakeTokenContract.balanceOf(stakeOwner.address)).to.eq(saleTokenMintAmount);
        expect(await stakeTokenContract.balanceOf(stakeContract.address)).to.eq(0);
    });

    it("when try to stake more than allowance amount, should revert", async () => {
        let stakeAmount: number = 100000;
        await stakeTokenContract.connect(stakeOwner).approve(stakeContract.address, stakeAmount);

        await expect(stakeContract.connect(stakeOwner).stake(stakeAmount + 1)).to.be.revertedWith(
            "insufficient allowance"
        );
        expect(await stakeContract.getCurrentStakeAmount(stakeOwner.address)).to.eq(0);
        expect(await stakeTokenContract.balanceOf(stakeOwner.address)).to.eq(saleTokenMintAmount);
        expect(await stakeTokenContract.balanceOf(stakeContract.address)).to.eq(0);
    });

    it("when stake under min lockup amount, should revert", async () => {
        let stakeAmount: number = minLockUpAmount - 1;
        await stakeTokenContract.connect(stakeOwner).approve(stakeContract.address, stakeAmount);

        await expect(stakeContract.connect(stakeOwner).stake(stakeAmount)).to.be.revertedWith(
            "insufficient amount"
        );
        expect(await stakeContract.getCurrentStakeAmount(stakeOwner.address)).to.eq(0);
        expect(await stakeTokenContract.balanceOf(stakeOwner.address)).to.eq(saleTokenMintAmount);
        expect(await stakeTokenContract.balanceOf(stakeContract.address)).to.eq(0);
    });

    it("success with valid stake amount", async () => {
        let stakeAmount: number = requiredStakeAmount + 1;
        await stakeTokenContract.connect(stakeOwner).increaseAllowance(stakeContract.address, stakeAmount);

        await stakeContract.connect(stakeOwner).stake(stakeAmount);

        expect(await stakeContract.getCurrentStakeAmount(stakeOwner.address)).to.eq(stakeAmount);
        expect(await stakeTokenContract.balanceOf(stakeOwner.address)).to.eq(saleTokenMintAmount - stakeAmount);
        expect(await stakeTokenContract.balanceOf(stakeContract.address)).to.eq(stakeAmount);
    });

    // ================================== isSatisfied ==================================
    it("success with multiple staking", async () => {
        // GIVEN:
        let stakeAmount: number = requiredStakeAmount;
        await stakeContract.connect(stakeOwner).setPeriod(await latestBlocktime() - 1, 5 * DAY);

        // WHEN:
        await stakeTokenContract.connect(stakeOwner).increaseAllowance(stakeContract.address, stakeAmount);
        await stakeContract.connect(stakeOwner).stake(stakeAmount);
        await increaseTime(2 * DAY);
        expect(Boolean(await stakeContract.isSatisfied(stakeOwner.address))).to.eq(false);

        let additionalLockup: number = minLockUpAmount
        await stakeTokenContract.connect(stakeOwner).increaseAllowance(stakeContract.address, additionalLockup);
        await stakeContract.connect(stakeOwner).stake(additionalLockup);
        await increaseTime(4 * DAY);

        // THEN:
        expect(Boolean(await stakeContract.isSatisfied(stakeOwner.address))).to.eq(true);
        expect(await stakeContract.getCurrentStakeAmount(stakeOwner.address)).to.eq(
            stakeAmount + additionalLockup
        );
    });

    it("when unstake under required amount should not satisfy", async () => {
        // GIVEN:
        let stakeAmount: number = requiredStakeAmount;
        await stakeContract.connect(stakeOwner).setPeriod(await latestBlocktime() - 1, 5 * DAY);

        // WHEN:
        await stakeTokenContract.connect(stakeOwner).increaseAllowance(stakeContract.address, stakeAmount);
        await stakeContract.connect(stakeOwner).stake(stakeAmount);
        await increaseTime(3 * DAY);

        let unLockupAmount: number = 1
        await stakeContract.connect(stakeOwner).unStake(unLockupAmount);
        await increaseTime(3 * DAY);

        // THEN:
        expect(Boolean(await stakeContract.isSatisfied(stakeOwner.address))).to.eq(false);
        expect(await stakeContract.getCurrentStakeAmount(stakeOwner.address)).to.eq(
            stakeAmount - unLockupAmount
        );
    });

    it("when do not stake, not satisfy", async () => {
        // GIVEN:
        await stakeContract.connect(stakeOwner).setPeriod(await latestBlocktime() - 1, 5 * DAY);

        // WHEN:
        await increaseTime(6 * DAY);

        // THEN:
        expect(Boolean(await stakeContract.isSatisfied(stakeOwner.address))).to.eq(false);
        expect(await stakeContract.getCurrentStakeAmount(stakeOwner.address)).to.eq(0);
    });

    // ================================== unStake ==================================
    it("when try to unstake more then staked amount, should revert ", async () => {
        let stakeAmount: number = requiredStakeAmount;
        let unStakeAmount: number = stakeAmount + 1;

        await stakeTokenContract.connect(stakeOwner).increaseAllowance(stakeContract.address, stakeAmount);
        await stakeContract.connect(stakeOwner).stake(stakeAmount);

        await expect(stakeContract.connect(stakeOwner).unStake(unStakeAmount)).to.be.revertedWith(
            "invalid amount. stakedAmount < amount"
        )
    });

    it("when try to unstake without stake, should revert", async () => {
        let unStakeAmount: number = 1;

        await expect(stakeContract.connect(stakeOwner).unStake(unStakeAmount)).to.be.revertedWith(
            "stake amount is 0"
        )
    });

    it("success unstaking with valid amount", async () => {
        let stakeAmount: number = requiredStakeAmount;
        let unStakeAmount: number = stakeAmount;

        await stakeTokenContract.connect(stakeOwner).increaseAllowance(stakeContract.address, stakeAmount);
        await stakeContract.connect(stakeOwner).stake(stakeAmount);
        expect(await stakeContract.getCurrentStakeAmount(stakeOwner.address)).to.eq(stakeAmount);
        expect(await stakeTokenContract.balanceOf(stakeOwner.address)).to.eq(saleTokenMintAmount - stakeAmount);
        expect(await stakeTokenContract.balanceOf(stakeContract.address)).to.eq(stakeAmount);

        await stakeContract.connect(stakeOwner).unStake(unStakeAmount);
        expect(await stakeContract.getCurrentStakeAmount(stakeOwner.address)).to.eq(0);
        expect(await stakeTokenContract.balanceOf(stakeOwner.address)).to.eq(saleTokenMintAmount);
        expect(await stakeTokenContract.balanceOf(stakeContract.address)).to.eq(0);
    });

    it("success multiple unstake", async () => {
        let stakeAmount: number = requiredStakeAmount;
        let firstUnStakeAmount: number = 10000;
        let secondUnStakeAmount: number = 20000;

        await stakeTokenContract.connect(stakeOwner).increaseAllowance(stakeContract.address, stakeAmount);
        await stakeContract.connect(stakeOwner).stake(stakeAmount);
        expect(await stakeContract.getCurrentStakeAmount(stakeOwner.address)).to.eq(stakeAmount);
        expect(await stakeTokenContract.balanceOf(stakeOwner.address)).to.eq(saleTokenMintAmount - stakeAmount);
        expect(await stakeTokenContract.balanceOf(stakeContract.address)).to.eq(stakeAmount);

        await stakeContract.connect(stakeOwner).unStake(firstUnStakeAmount);
        expect(await stakeContract.getCurrentStakeAmount(stakeOwner.address)).to.eq(
            stakeAmount - firstUnStakeAmount
        );
        await stakeContract.connect(stakeOwner).unStake(secondUnStakeAmount);
        expect(await stakeContract.getCurrentStakeAmount(stakeOwner.address)).to.eq(
            stakeAmount - firstUnStakeAmount - secondUnStakeAmount
        );
        expect(await stakeTokenContract.balanceOf(stakeOwner.address)).to.eq(
            saleTokenMintAmount - (stakeAmount - firstUnStakeAmount - secondUnStakeAmount)
        );
    });
});
