import { ethers, network } from "hardhat";
import chai from "chai";
import { solidity } from "ethereum-waffle";
import { Contract, ContractFactory } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { accumulateBlockByBlockNumber, accumulateBlockByBlockCnt } from "./utils";

chai.use(solidity);
const { expect } = chai;

describe("DOPE", () => {

    const saleTokenMintAmount: number = 100000000000;
    let tokenOwner: SignerWithAddress;
    let dopeOwner: SignerWithAddress;

    let DOPE: ContractFactory;
    let saleToken: ContractFactory;

    let dopeContract: Contract;
    let saleTokenContract: Contract;

    before("Setup accounts", async () => {
       [tokenOwner] = await ethers.getSigners();
       [dopeOwner] = await ethers.getSigners();
    });

    before("fetch contract factories", async () => {
       DOPE = await ethers.getContractFactory('DOPE');
       saleToken = await ethers.getContractFactory('ERC20Mintable');
       saleTokenContract = await saleToken.connect(tokenOwner).deploy(
            "saleToken",
            "STN",
            saleTokenMintAmount
        );
       dopeContract = await DOPE.connect(dopeOwner).deploy(
            'test',
            saleTokenContract.address,
            1000000,
            saleTokenContract.address,
            saleTokenContract.address,
            saleTokenContract.address,
            5,
            5,
            5
       );
    });

    it("simple check", async () => {
        await saleTokenContract.connect(tokenOwner).approve(dopeContract.address, 1000);
        await dopeContract.connect(tokenOwner).stake(1000);
        expect(await dopeContract.getStakeAmountOf(tokenOwner.address)).to.eq(1000);
        await dopeContract.connect(tokenOwner).unStake(1000);
        expect(await dopeContract.getStakeAmountOf(tokenOwner.address)).to.eq(0);
        expect(await dopeContract.getSaleTokenAddress()).to.eq(saleTokenContract.address);
        expect(await saleTokenContract.balanceOf(tokenOwner.address)).to.eq(saleTokenMintAmount);
    });
});