import {ethers} from "hardhat";
import chai from "chai";
import {solidity} from "ethereum-waffle";
import {Contract, ContractFactory} from "ethers";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import {latestBlocktime} from "../../utils";


chai.use(solidity);
const {expect} = chai;


describe("Fund", () => {
    const MINUTES: number = 60;
    const HOUR: number = MINUTES * 60;
    const DAY: number = HOUR * 24;

    let fundOwner: SignerWithAddress;
    let investor: SignerWithAddress;
    let treasury: SignerWithAddress;

    const saleTokenMintAmount: number = 10 ** 10;

    let targetAmount: number = 100_000;
    let exchangeRate: number = 1_000_000;
    let userMinFundingAmount: number = 0;
    let userMaxFundingAmount: number = 1_000_000_000_000;

    let fundFactory: ContractFactory;
    let mockStakeFactory: ContractFactory;
    let tokenFactory: ContractFactory;

    let fundContract: Contract;
    let mockStakeContract: Contract;
    let saleTokenContract: Contract;
    let exchangeTokenContract: Contract;

    before("Setup accounts", async () => {
        [fundOwner, investor, treasury] = await ethers.getSigners();
    });

    beforeEach("fetch token contract", async () => {
        tokenFactory = await ethers.getContractFactory('ERC20Mintable');
        saleTokenContract = await tokenFactory.connect(fundOwner).deploy(
            "saleToken",
            "SAL",
            saleTokenMintAmount
        );
        exchangeTokenContract = await tokenFactory.connect(investor).deploy(
            "exchangeToken",
            "EXC",
            saleTokenMintAmount
        );
    });

    beforeEach("fetch fund contract", async () => {

        mockStakeFactory = await ethers.getContractFactory('MockedStake');
        fundFactory = await ethers.getContractFactory('Fund');

        mockStakeContract = await mockStakeFactory.connect(fundOwner).deploy();
        fundContract = await fundFactory.connect(fundOwner).deploy();
        let args = await fundContract.initPayload(
            saleTokenContract.address,
            exchangeTokenContract.address,
            mockStakeContract.address,
            treasury.address,
        );
        await fundContract.connect(fundOwner).initialize(args);
    });

    beforeEach("set default period and sale token", async () => {
        let defaultTimeBefore: number = DAY
        await fundContract.connect(fundOwner).setPeriod(
            await latestBlocktime() - defaultTimeBefore,
            defaultTimeBefore + DAY,
            0
        );

        await saleTokenContract.connect(fundOwner).approve(fundContract.address, (targetAmount * exchangeRate) / 10 ** 6);
        await fundContract.connect(fundOwner).setSaleToken(
            fundOwner.address,
            targetAmount,
            exchangeRate,
            userMinFundingAmount,
            userMaxFundingAmount
        );
    });

    it("success to fund", async () => {
        let investAmount: number = 10000

        await exchangeTokenContract.connect(investor).approve(fundContract.address, investAmount);
        await fundContract.connect(investor).fund(investAmount);

        expect(await saleTokenContract.balanceOf(investor.address)).to.eq(investAmount);
        expect(await exchangeTokenContract.balanceOf(treasury.address)).to.eq(investAmount);
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
