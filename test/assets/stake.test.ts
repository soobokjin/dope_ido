import { ethers, network } from "hardhat";
import chai from "chai";
import { solidity } from "ethereum-waffle";
import { BigNumber, Contract, ContractFactory } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { accumulateBlockByBlockNumber, accumulateBlockByBlockCnt } from "../utils";

chai.use(solidity);

describe("DOPE", () => {
    let stake: ContractFactory;
    let stakeOwner: SignerWithAddress;
    let stakeContract: Contract;


    before("Setup accounts", async () => {
       [stakeOwner] = await ethers.getSigners();
    });

    before("fetch stake contract factories", async () => {
       stake = await ethers.getContractFactory('Stake');
       stakeContract = await stake.connect(stakeOwner).deploy(

       );
    });

    it("period", async () => {
    });

});
