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
});
