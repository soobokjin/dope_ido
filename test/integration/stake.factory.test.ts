import {ethers} from "hardhat";
import chai from "chai";
import {solidity} from "ethereum-waffle";
import {Contract, ContractFactory} from "ethers";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";

chai.use(solidity);
const {expect} = chai;

describe("DOPE", () => {

    const saleTokenMintAmount: number = 10 ** 10;
    let dopeOwner: SignerWithAddress;
    let tokenOwner: SignerWithAddress;
    let investor: SignerWithAddress;

    let stakeFactory: ContractFactory;
    let stakeFactoryFactory: ContractFactory;
    let saleTokenFactory: ContractFactory;

    let stakeFactoryContract: Contract;
    let stakeProxyContract: Contract;
    let stakeImplementationContract: Contract;
    let dopeTokenContract: Contract;

    before("Setup accounts", async () => {
        [tokenOwner, dopeOwner, investor] = await ethers.getSigners();
    });

    before("fetch token contract factories", async () => {
        saleTokenFactory = await ethers.getContractFactory('ERC20Mintable');
        dopeTokenContract = await saleTokenFactory.connect(tokenOwner).deploy(
            "DOPEToken",
            "DOPE",
            saleTokenMintAmount
        );
    });
    let investorTokenAmount = 100000;

    before("share token to investor and lender", async () => {
        await dopeTokenContract.connect(tokenOwner).transfer(investor.address, investorTokenAmount)
    });

    before("fetch dope contract factories", async () => {
        stakeFactoryFactory = await ethers.getContractFactory('StakeFactory');
        stakeFactory = await ethers.getContractFactory('Stake');

        stakeFactoryContract = await stakeFactoryFactory.connect(dopeOwner).deploy();
        await stakeFactoryContract.connect(dopeOwner).createStake(
            dopeTokenContract.address,
            10000,
            10000,
            10000,
        );
        stakeImplementationContract = stakeFactory.attach(await stakeFactoryContract.implementation());
    });

    it("", async () => {
        let created_address: string = await stakeFactoryContract.getStakeAddressOf(0);
        stakeProxyContract = stakeFactory.attach(created_address);
        console.log(await stakeProxyContract.connect(dopeOwner).owner());
        console.log(await stakeProxyContract.connect(dopeOwner).operator());

        console.log(await stakeProxyContract.connect(dopeOwner).requiredRetentionPeriod());
        console.log(await stakeProxyContract.connect(dopeOwner).requiredRetentionPeriod());
    });
});