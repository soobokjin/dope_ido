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
        await stakeContract.connect(stakeOwner).setStakeToken(stakeTokenContract.address);
    });

    // ================================== Stake ==================================
    it("stake with un registered stake token should revert", async () => {
        await expect(
            stakeContract.connect(stakeOwner).stake(10000, unregisteredStakeTokenContract.address)
        ).to.be.revertedWith("Stake: invalid stake token");
    });

    it("stake with valid amount", async () => {
        let stakeAmount: number = 100000;
        await stakeTokenContract.connect(stakeOwner).approve(stakeContract.address, stakeAmount);

        await stakeContract.connect(stakeOwner).stake(stakeAmount, stakeTokenContract.address);

        expect(
            await stakeContract.getCurrentStakeAmount(stakeOwner.address, stakeTokenContract.address)
        ).to.eq(stakeAmount);
        expect(await stakeTokenContract.balanceOf(stakeOwner.address)).to.eq(saleTokenMintAmount - stakeAmount);
        expect(await stakeTokenContract.balanceOf(stakeContract.address)).to.eq(stakeAmount);
    });

    it("unstake with valid amount", async () => {
        let stakeAmount: number = 100000;
        await stakeTokenContract.connect(stakeOwner).approve(stakeContract.address, stakeAmount);
        await stakeContract.connect(stakeOwner).stake(stakeAmount, stakeTokenContract.address);

        await stakeContract.connect(stakeOwner).unStake(stakeAmount, stakeTokenContract.address);

        expect(
            await stakeContract.getCurrentStakeAmount(stakeOwner.address, stakeTokenContract.address)
        ).to.eq(0);
        expect(await stakeTokenContract.balanceOf(stakeOwner.address)).to.eq(saleTokenMintAmount);
        expect(await stakeTokenContract.balanceOf(stakeContract.address)).to.eq(0);
    });

    it("validate merkle proof", async () => {
        /*
            leafs:
                0xC7905463C85C6398B4C146D5AcB02623Cda60E24
                0xeaE7E225C6A0733f96C3b0691d61a3B62B8cB850
                0x96d80c5189294e6e12Becb69f16591cd5cfc057C
                0x96d80c5189294e6e12Becb69f16591cd5cfc057C
         */
        let address1: string = '0xC7905463C85C6398B4C146D5AcB02623Cda60E24';
        let merkleProof = [
            '0x4c5031fa63aa4cd4aab2ce752b8f2450267997e0bd647933b036a04ebff94010',
            '0x19fa3742510ad34c636f1b090f0125197213fa56d9d6b411ef582a6462f40efa'
        ];
        let root: string = '0xb9bf33515673eecd7e594c529c12dae575bd20acec93c21cdd624be099cc7c42';
        await stakeContract.connect(stakeOwner).registerSaleTokenWhiteList(
            stakeTokenContract.address, root
        )

        expect(
            await stakeContract.isWhiteListed(address1, stakeTokenContract.address, merkleProof, 0)
        ).to.be.eq(true);
    });
});
