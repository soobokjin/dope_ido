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

    return await get(name).address;
}

const deployDOPE: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
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
        console.log("deploy saleToken")
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

    // DOPE Deploy
    const gasPrice = 8000000000;
    const stringGasPrice = '0x' + gasPrice.toString(16)
    await deploy(DOPE, {
        from: dopeOwner,
        gasLimit: 8000000,
        gasPrice: stringGasPrice,
        args: [
            'STN',
            saleTokenAddress,
            100000000000,
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
    await get(DOPE);
};
export default deployDOPE;
