import { ethers } from "hardhat";
import { Contract } from "ethers";
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
    const saleTokenMintAmount = 100000000000;
    const stringSaleTokenMintAmount = '0x' + saleTokenMintAmount.toString(16);

    await deploy(name, {
        from: owner,
        contract: name,
        gasLimit: 8000000,
        gasPrice: stringGasPrice,
        args: [
            tokenName, symbol, stringSaleTokenMintAmount
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
    const { deployments, getNamedAccounts } = hre;
    const { dopeOwner, saleTokenOwner, stableTokenOwner } = await getNamedAccounts();
    const { deploy, get } = deployments;
    const DOPE = 'DOPE';
    const token_contracts: any = CONTRACTS[hre.network.name].tokens;
    const saleToken = 'ERC20Mintable';
    const dopeToken = 'ERC20Mintable';
    const stableToken = 'ERC20Mintable';
    let saleTokenAddress = token_contracts.saleToken;
    let stableTokenAddress = token_contracts.stableToken;
    let dopeTokenAddress = token_contracts.dopeToken;
    // Sale Token Deploy
    if (saleTokenAddress == '') {
        saleTokenAddress = await deployToken(
            deploy, get, saleToken, saleTokenOwner,"sale Token","STN"
        );
    }
    if (stableTokenAddress == '') {
        stableTokenAddress = await deployToken(
            deploy, get, stableToken, stableTokenOwner,"stable Token","USD"
        );
    }
    if (dopeTokenAddress == '') {
        dopeTokenAddress =  await deployToken(
            deploy, get, dopeToken, dopeOwner,"DOPE Token","DOPE"
        );
    }
    const saleTokenAmount = 50000000;
    // DOPE Deploy
    const gasPrice = 8000000000;
    const stringGasPrice = '0x' + gasPrice.toString(16);
    await deploy(DOPE, {
        from: dopeOwner,
        gasLimit: 8000000,
        gasPrice: stringGasPrice,
        args: [
            'STN',
            saleTokenAddress,
            saleTokenAmount,
            stableTokenAddress,
            saleTokenOwner,
            dopeTokenAddress,
            10 ** 6,
            1000,
            5000,
        ],
        log: true,
        deterministicDeployment: false,
    });
    let dopeDeployment = await get(DOPE);
    let tokenOwner;
    [tokenOwner] = await ethers.getSigners();
    console.log(tokenOwner.address);
    console.log(saleTokenOwner);
    let saleTokenContract: Contract = await ethers.getContractAt(stableToken, saleTokenAddress, tokenOwner);
    let dopeContract: Contract = await ethers.getContractAt(DOPE, dopeDeployment.address, tokenOwner);
    console.log(await saleTokenContract.connect(tokenOwner).balanceOf(dopeDeployment.address));
    console.log(await saleTokenContract.connect(tokenOwner).approve(dopeDeployment.address, saleTokenAmount));
    console.log(await dopeContract.connect(tokenOwner).putSaleToken());
    console.log(await saleTokenContract.connect(tokenOwner).balanceOf(dopeDeployment.address));

};
export default deployDOPE;
