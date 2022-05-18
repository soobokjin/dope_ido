import {ethers} from "hardhat";
import chai from "chai";
import {solidity} from "ethereum-waffle";
import {Contract, ContractFactory} from "ethers";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";

chai.use(solidity);
const {expect} = chai;


describe("Stake", () => {
    const saleTokenMintAmount: number = 10 ** 10;
    let stakeOwner: SignerWithAddress;

    let stake: ContractFactory;
    let stakeToken: ContractFactory;

    let stakeContract: Contract;
    let stakeTokenContract: Contract;
    let unregisteredStakeTokenContract: Contract;

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

        unregisteredStakeTokenContract = await stakeToken.connect(stakeOwner).deploy(
            "unregisterdStakeToken",
            "NON",
            saleTokenMintAmount
        );
    });

    beforeEach("fetch stake contract", async () => {
        stake = await ethers.getContractFactory('Stake');
        stakeContract = await stake.connect(stakeOwner).deploy();
        // set on stake period
        await stakeContract.connect(stakeOwner).initialize();
        await stakeContract.connect(stakeOwner).registerStakeToken(stakeTokenContract.address);
    });

    // ================================== Stake ==================================
    it("stake with un registered stake token should revert", async () => {
        await expect(
            stakeContract.connect(stakeOwner).stake(unregisteredStakeTokenContract.address, 10000)
        ).to.be.revertedWith("Stake: stake token not registered");
    });

    it("stake with valid amount", async () => {
        let stakeAmount: number = 100000;
        await stakeTokenContract.connect(stakeOwner).approve(stakeContract.address, stakeAmount);

        await stakeContract.connect(stakeOwner).stake(stakeTokenContract.address, stakeAmount);

        expect(
            await stakeContract.getCurrentStakeAmount(stakeTokenContract.address, stakeOwner.address)
        ).to.eq(stakeAmount);
        expect(await stakeTokenContract.balanceOf(stakeOwner.address)).to.eq(saleTokenMintAmount - stakeAmount);
        expect(await stakeTokenContract.balanceOf(stakeContract.address)).to.eq(stakeAmount);
    });

    it("unstake with valid amount", async () => {
        let stakeAmount: number = 100000;
        await stakeTokenContract.connect(stakeOwner).approve(stakeContract.address, stakeAmount);
        await stakeContract.connect(stakeOwner).stake(stakeTokenContract.address, stakeAmount);

        await stakeContract.connect(stakeOwner).unStake(stakeTokenContract.address, stakeAmount);

        expect(
            await stakeContract.getCurrentStakeAmount(stakeTokenContract.address, stakeOwner.address)
        ).to.eq(0);
        expect(await stakeTokenContract.balanceOf(stakeOwner.address)).to.eq(saleTokenMintAmount);
        expect(await stakeTokenContract.balanceOf(stakeContract.address)).to.eq(0);
    });
});
