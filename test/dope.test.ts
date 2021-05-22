import { ethers } from "hardhat";
import chai from "chai";
import { Contract, ContractFactory} from "ethers";
import { solidity } from "ethereum-waffle";
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';


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

        dopeContract = await DOPE.connect(dopeOwner).deploy(
            'test',
            dopeOwner.address,
            5,
            dopeOwner.address,
            dopeOwner.address,
            dopeOwner.address,
            5,
            5,
            5
       );
        saleTokenContract = await saleToken.connect(tokenOwner).deploy(
            "saleToken",
            "STN",
            saleTokenMintAmount
        );
    });

    it("simple check", async () => {
        expect(await dopeContract.getSaleTokenAddress()).to.eq(dopeOwner.address);
        expect(await saleTokenContract.balanceOf(tokenOwner.address)).to.eq(saleTokenMintAmount);
    });
});