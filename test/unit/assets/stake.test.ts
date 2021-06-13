import { ethers, network } from "hardhat";
import chai from "chai";
import { solidity } from "ethereum-waffle";
import { BigNumber, Contract, ContractFactory } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { increaseTime, latestBlocktime } from "../../utils";

chai.use(solidity);

describe("Stake", () => {
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

    before("fetch token contract factories", async () => {
        stakeToken = await ethers.getContractFactory('ERC20Mintable');
        stakeTokenContract = await stakeToken.connect(stakeOwner).deploy(
            "stakeToken",
            "STK",
            saleTokenMintAmount
        );
    });

    beforeEach("fetch stake contract factories", async () => {
        stake = await ethers.getContractFactory('Stake');
        stakeContract = await stake.connect(stakeOwner).deploy(
            stakeTokenContract.address,
            minStakeAmount,
            minRetentionPeriod,
        );
        await stakeContract.connect(stakeOwner).setPeriod(
            await latestBlocktime() + 3600,
            3600
        );
    });

    it("stake and unstake", async () => {
        await stakeTokenContract.connect(stakeOwner).approve(stakeContract.address, 100000);
        await stakeContract.connect(stakeOwner).stake(100000);
    });
});
