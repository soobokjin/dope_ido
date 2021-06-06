import {ethers, network} from "hardhat";
import chai from "chai";
import {solidity} from "ethereum-waffle";
import {BigNumber, Contract, ContractFactory} from "ethers";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import {accumulateBlockByBlockNumber, accumulateBlockByBlockCnt} from "./utils";
import {deflateRawSync} from "zlib";

chai.use(solidity);
const {expect} = chai;

describe("DOPE", () => {

    const saleTokenMintAmount: number = 10 ** 10;
    let dopeOwner: SignerWithAddress;
    let tokenOwner: SignerWithAddress;
    let investor: SignerWithAddress;
    let lender: SignerWithAddress;

    let Fund: ContractFactory;
    let saleToken: ContractFactory;
    let stake: ContractFactory;
    let lend: ContractFactory;
    let Period: ContractFactory;

    let fundContract: Contract;
    let saleTokenContract: Contract;
    let stableTokenContract: Contract;
    let dopeTokenContract: Contract;
    let PeriodContract: Contract;
    let stakeContract: Contract;
    let lendContract: Contract;

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
        [tokenOwner, dopeOwner, investor, lender] = await ethers.getSigners();
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
        await stableTokenContract.connect(tokenOwner).transfer(lender.address, lenderTokenAmount)
    });

    before("fetch dope contract factories", async () => {
        Fund = await ethers.getContractFactory('Fund');
        fundContract = await Fund.connect(dopeOwner).deploy(
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
        Period = await ethers.getContractFactory('IDOPeriod');
        stake = await ethers.getContractFactory('Stake');
        lend = await ethers.getContractFactory('Lend');
        PeriodContract = await Period.connect(dopeOwner).deploy(
            startStakeBlockNum,
            endStakeBlockNum,
            startFundBlockNum,
            endFundBlockNum,
            startDepositLoanBlockNum,
            endDepositLoanBlockNum,
            startBorrowBlockNum,
            endBorrowBlockNum,
            startClaimBlockNum
        );
        stakeContract = await stake.connect(dopeOwner).deploy(
            dopeTokenContract.address,
            0,
            0
        );
        lendContract = await lend.connect(dopeOwner).deploy(
            fundContract.address,
            stableTokenContract.address,
            100000000,
            10000000,
            5000,
            1000,
        );
        await fundContract.connect(tokenOwner).setContracts(
            stakeContract.address,
            PeriodContract.address,
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

    it("deposit token and lend token from it", async () => {
        // lender Deposit 10000 token
        await stableTokenContract.connect(lender).approve(lendContract.address, 10000);
        await lendContract.connect(lender).deposit(10000);
        expect(await lendContract.getDepositedAmount(lender.address)).to.eq(BigNumber.from(10000));

        // investor Fund 10000 token
        await stableTokenContract.connect(investor).approve(fundContract.address, 10000);
        await fundContract.connect(investor).fundSaleToken(10000);
        // expect(await dopeContract.getShareAndCollateral(investor.address)).to.eq([10000, 0]);

        // investor lend 1000 token (Collateral should be 2000)
        await lendContract.connect(investor).borrow(1000);
        // expect(await dopeContract.getShareAndCollateral(investor.address)).to.eq([10000, 1000]);

        // investor repay 1000 token (Collateral should be 0 and share should be 9800)
        await stableTokenContract.connect(investor).approve(lendContract.address, 1000);
        await lendContract.connect(investor).repay(1000);
        // expect(await dopeContract.getShareAndCollateral(investor.address)).to.eq([10000, 1000]);

        // lender withdraw token (200 dope token and 10000 stable token should get)
        await lendContract.connect(lender).withdraw();
        expect(await stableTokenContract.balanceOf(lender.address)).to.eq(lenderTokenAmount);
        expect(await saleTokenContract.balanceOf(lender.address)).to.eq(200);

        // investor claim token (100 dope token and 10000 stable token should get)
        await fundContract.connect(investor).claim();
        expect(await saleTokenContract.balanceOf(investor.address)).to.eq(9800);
    });
});