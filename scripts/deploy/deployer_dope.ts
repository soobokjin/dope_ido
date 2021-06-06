import { ethers } from "hardhat";
import {Contract} from "ethers";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { CONTRACTS } from "../config/deploy";


async function deployToken (
    deploy: Function,
    get: Function,
    name: string ,
    owner: string,
    tokenName: string,
    symbol: string
): Promise<string> {
    const gasPrice = 8000000000;
    const stringGasPrice = '0x' + gasPrice.toString(16);
    const mintAmount = 1000 ** 18;
    const stringMintAmount = '0x' + mintAmount.toString(16);

    await deploy(name, {
        from: owner,
        contract: name,
        gasLimit: 8000000,
        gasPrice: stringGasPrice,
        args: [
            tokenName, symbol, stringMintAmount
        ],
        log: true,
        deterministicDeployment: false,
    });

    let result = await get(name);
    return result.address;
}

const deployDOPE: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    // Todo: 시나리오 생성, 시나리오에 맞추어 deploy
    // Todo: saleToken approval
    // Todo: period 설정
    const {deployments, getNamedAccounts} = hre;
    const {dopeOwner, stableTokenOwner, saleTokenOwner} = await getNamedAccounts();
    console.log(dopeOwner, stableTokenOwner, saleTokenOwner)
    const {deploy, get} = deployments;
    const gasPrice = 8000000000;
    const stringGasPrice = '0x' + gasPrice.toString(16);
    const Fund = 'Fund';
    const Lend = 'Lend';
    const Stake = 'Stake';

    const token_contracts: any = CONTRACTS[hre.network.name].tokens;

    const saleToken = 'ERC20Mintable';
    const dopeToken = 'ERC20Mintable';
    const stableToken = 'ERC20Mintable';
    let saleTokenAddress = token_contracts.saleToken;
    let stableTokenAddress = token_contracts.stableToken;
    let dopeTokenAddress = token_contracts.dopeToken;

    // ============= tokens Deploy ===============
    if (stableTokenAddress == '') {
        console.log("stableToken")
        stableTokenAddress = await deployToken(
            deploy, get, stableToken, stableTokenOwner,"stableToken","USD"
        );
    }
    if (dopeTokenAddress == '') {
        console.log("DOPEToken")
        dopeTokenAddress =  await deployToken(
            deploy, get, dopeToken, dopeOwner,"DOPEToken","DOPE"
        );
    }
    if (saleTokenAddress == '') {
        console.log("saleToken")
        saleTokenAddress = await deployToken(
            deploy, get, saleToken, saleTokenOwner,"saleToken","STN"
        );
    }

    // ============= Fund Deploy ===============
    let saleTokenName = 'STN'
    let saleTokenAmount = 10 ** 10;
    let exchangeRate = 10 ** 6;
    let maxUserFundingAllocation = 100000;
    console.log("Fund")
    await deploy (Fund, {
        from: dopeOwner,
        gasLimit: 8000000,
        gasPrice: stringGasPrice,
        args: [
            saleTokenName,
            saleTokenAddress,
            saleTokenAmount,
            stableTokenAddress,
            saleTokenOwner,
            maxUserFundingAllocation,
            exchangeRate
        ],
        log: true,
        deterministicDeployment: false,
    });
    let fundDeployment = await get(Fund);
    let fundAddress = fundDeployment.address;

    // ============= Stake Deploy ===============
    console.log("Stake")
    let minStakeAmount = 0;
    let minRetentionPeriod = 0;
    await deploy(Stake, {
       from: dopeOwner,
       gasLimit: 8000000,
       gasPrice: stringGasPrice,
       args: [
           dopeTokenAddress,
           minStakeAmount,
           minRetentionPeriod,
       ],
        log: true,
        deterministicDeployment: false,
    });
    let stakeDeployment = await get(Stake);
    let stakeAddress = stakeDeployment.address;

    // ============= Lend Deploy ===============
    console.log("Lend")
    let maxTotalAllocation = 1000000;
    let maxUserAllocation = 1000000;
    let ltvRate = 5000;
    let interestRate = 1000;
    await deploy(Lend, {
        from: dopeOwner,
        gasLimit: 8000000,
        gasPrice: stringGasPrice,
        args: [
            fundAddress,
            stableTokenAddress,
            maxTotalAllocation,
            maxUserAllocation,
            ltvRate,
            interestRate
        ],
        log: true,
        deterministicDeployment: false,
    });
    let lendDeployment = await get(Lend);
    let lendAddress = lendDeployment.address;

    // Connect Fund
    console.log("Connect Fund")
    const dopeSigner = await ethers.getSigner(dopeOwner);
    const saleTokenSigner = await ethers.getSigner(saleTokenOwner);
    let saleTokenContract: Contract = await ethers.getContractAt(stableToken, saleTokenAddress, saleTokenSigner);
    let fundContract: Contract = await ethers.getContractAt(Fund, fundDeployment.address, dopeSigner);

    console.log(await saleTokenContract.connect(saleTokenSigner).approve(fundDeployment.address, saleTokenAmount));
    console.log(await fundContract.connect(dopeSigner).setSaleToken());
    console.log(await fundContract.connect(dopeSigner).setContracts(
        stakeAddress
    ));

    console.log(await fundContract.getTargetFundingAmount());
};

export default deployDOPE;
