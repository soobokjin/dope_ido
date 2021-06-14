import {ethers, network} from "hardhat";
import chai from "chai";
import {solidity} from "ethereum-waffle";
import {Contract, ContractFactory} from "ethers";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import {increaseTime, latestBlocktime} from "../../utils";
import {HOUR, DAY} from "../../consts";


describe("Lend", () => {
    const saleTokenMintAmount: number = 10 ** 10;
    let requiredRetentionPeriod: number = 4 * DAY;
    let lendOwner: SignerWithAddress;

    let lend: ContractFactory;
    let lendToken: ContractFactory;
    let mockedFund: ContractFactory;

    let lendContract: Contract;
    let lendTokenContract: Contract;
    let mockedFundContract: Contract;

    before("Setup accounts", async () => {
        [lendOwner] = await ethers.getSigners();
    });

    beforeEach("fetch token contract factories", async () => {
        lendToken = await ethers.getContractFactory('ERC20Mintable');
        lendTokenContract = await lendToken.connect(lendOwner).deploy(
            "stakeToken",
            "STK",
            saleTokenMintAmount
        );
    });

    beforeEach("fetch lend contract factories", async () => {
        let defaultTimeBefore: number = DAY
        lend = await ethers.getContractFactory('Stake');
        lendContract = await lend.connect(lendOwner).deploy(
            lendTokenContract.address,
            requiredRetentionPeriod,
        );

        // set on stake period
        await lendContract.connect(lendOwner).setPeriod(
            await latestBlocktime() - defaultTimeBefore,
            defaultTimeBefore + DAY
        );
    });
});
