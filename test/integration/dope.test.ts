import {ethers, network} from "hardhat";
import chai from "chai";
import {solidity} from "ethereum-waffle";
import {BigNumber, Contract, ContractFactory} from "ethers";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import {accumulateBlockByBlockNumber, accumulateBlockByBlockCnt} from "../utils";
import {deflateRawSync} from "zlib";

chai.use(solidity);
const {expect} = chai;

describe("DOPE", () => {

    const saleTokenMintAmount: number = 10 ** 10;
    let dopeOwner: SignerWithAddress;
    let tokenOwner: SignerWithAddress;
    let investor: SignerWithAddress;

    let factory: ContractFactory;
    let fund: ContractFactory;
    let stake: ContractFactory;
    let saleToken: ContractFactory;

    let factoryContract: ContractFactory;
    let fundContract: Contract;
    let stakeContract: Contract;
    let saleTokenContract: Contract;
    let stableTokenContract: Contract;
    let dopeTokenContract: Contract;


    let startStakeBlockNum: number = 0;
    let endStakeBlockNum: number = 19;
    let startFundBlockNum: number = endStakeBlockNum + 1;
    let endFundBlockNum: number = startFundBlockNum + 19;
    let startDepositLoanBlockNum: number = endFundBlockNum + 1;
    let endDepositLoanBlockNum: number = startDepositLoanBlockNum + 19;
    let startBorrowBlockNum: number = endDepositLoanBlockNum + 1;
    let endBorrowBlockNum: number = startBorrowBlockNum + 19;
    let startClaimBlockNum: number = endBorrowBlockNum + 1;

    before("Setup accounts", async () => {
        [tokenOwner, dopeOwner, investor] = await ethers.getSigners();
    });

    before("fetch token contract factories", async () => {
        saleToken = await ethers.getContractFactory('ERC20Mintable');
        saleTokenContract = await saleToken.connect(tokenOwner).deploy(
            "saleToken",
            "STN",
            saleTokenMintAmount
        );
        stableTokenContract = await saleToken.connect(tokenOwner).deploy(
            "stableToken",
            "USD",
            saleTokenMintAmount
        );
        dopeTokenContract = await saleToken.connect(tokenOwner).deploy(
            "DOPEToken",
            "DOPE",
            saleTokenMintAmount
        );
    });
    let investorTokenAmount = 100000;
    let lenderTokenAmount = 100000;
    before("share token to investor and lender", async () => {
        await dopeTokenContract.connect(tokenOwner).transfer(investor.address, investorTokenAmount)
        await stableTokenContract.connect(tokenOwner).transfer(investor.address, investorTokenAmount)
    });

    before("fetch dope contract factories", async () => {
        fund = await ethers.getContractFactory('Fund');
        fundContract = await fund.connect(dopeOwner).deploy(
            'STN',
            saleTokenContract.address,
            saleTokenMintAmount,
            stableTokenContract.address,
            tokenOwner.address,
            100000000000,
            10 ** 6,
        );
        await saleTokenContract.connect(tokenOwner).approve(fundContract.address, saleTokenMintAmount);
        await fundContract.connect(tokenOwner).setSaleToken();
        expect(await saleTokenContract.balanceOf(tokenOwner.address)).to.eq(0);
        expect(await saleTokenContract.balanceOf(fundContract.address)).to.eq(10000000000);
    });

    before("fetch other contract factory", async () => {
        stake = await ethers.getContractFactory('Stake');

        stakeContract = await stake.connect(dopeOwner).deploy(
            dopeTokenContract.address,
            0,
            0
        );
        await fundContract.connect(tokenOwner).setContracts(
            stakeContract.address,
        );
    });

    it("stake and unStake", async () => {
        await dopeTokenContract.connect(tokenOwner).approve(stakeContract.address, 1000);
        await stakeContract.connect(tokenOwner).stake(1000);
        await expect(await stakeContract.getCurrentStakeAmount(tokenOwner.address)).to.eq(1000);

        await stakeContract.connect(tokenOwner).unStake(1000);
        await expect(await stakeContract.getCurrentStakeAmount(tokenOwner.address)).to.eq(0);

        await dopeTokenContract.connect(investor).approve(stakeContract.address, 1000);
        await stakeContract.connect(investor).stake(1000);
        await expect(await stakeContract.getCurrentStakeAmount(investor.address)).to.eq(1000);

        // await accumulateBlockByBlockNumber(startFundBlockNum);
        // await expect(stakeContract.connect(tokenOwner).stake(1000)).to.be.revertedWith("not in stake period");
    });

    // it("deposit token and lend token from it", async () => {
    //     // lender Deposit 10000 token
    //     await stableTokenContract.connect(lender).approve(lendContract.address, 10000);
    //     await lendContract.connect(lender).deposit(10000);
    //     expect(await lendContract.getDepositedAmount(lender.address)).to.eq(BigNumber.from(10000));
    //
    //     // investor Fund 10000 token
    //     await stableTokenContract.connect(investor).approve(fundContract.address, 10000);
    //     await fundContract.connect(investor).fundSaleToken(10000);
    //     // expect(await dopeContract.getShareAndCollateral(investor.address)).to.eq([10000, 0]);
    //
    //     // investor lend 1000 token (Collateral should be 2000)
    //     await lendContract.connect(investor).borrow(1000);
    //     // expect(await dopeContract.getShareAndCollateral(investor.address)).to.eq([10000, 1000]);
    //
    //     // investor repay 1000 token (Collateral should be 0 and share should be 9800)
    //     await stableTokenContract.connect(investor).approve(lendContract.address, 1000);
    //     await lendContract.connect(investor).repay(1000);
    //     // expect(await dopeContract.getShareAndCollateral(investor.address)).to.eq([10000, 1000]);
    //
    //     // lender withdraw token (200 dope token and 10000 stable token should get)
    //     await lendContract.connect(lender).withdraw();
    //     expect(await stableTokenContract.balanceOf(lender.address)).to.eq(lenderTokenAmount);
    //     expect(await saleTokenContract.balanceOf(lender.address)).to.eq(200);
    //
    //     // investor claim token (100 dope token and 10000 stable token should get)
    //     await fundContract.connect(investor).claim();
    //     expect(await saleTokenContract.balanceOf(investor.address)).to.eq(9800);
    // });
});