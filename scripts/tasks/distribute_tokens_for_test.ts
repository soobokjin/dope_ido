import "hardhat-deploy";
import "@nomiclabs/hardhat-ethers";
import {BigNumber, Contract, ethers } from "ethers";

import { task } from "hardhat/config";
import {CONTRACTS} from "../config/deploy";

const TOKEN = 'ERC20Mintable';

const distributeTokens: () => void = () => {
    task("distributeTokens",
        "Allows to place many orders for testing purposes"
    ).addParam(
        "toAddress", "address"
    ).addParam(
        "tokenName", "token to get. saleToken, stableToken, dopeToken"
    ).addOptionalParam(
        "amount", "amount to get"
    ).setAction(
        async (args, hre) => {
            const {getNamedAccounts} = hre;
            const token_contracts: any = CONTRACTS[hre.network.name].tokens;
            const {stableTokenOwner, saleTokenOwner} = await getNamedAccounts();
            let toAddress: string = args.toAddress;
            let tokenAddress = token_contracts[args.tokenName];
            let amount: bigint = args.amount;
            let signer;

            if (args.tokenName == "saleToken") {
                signer = await hre.ethers.getSigner(saleTokenOwner);
            } else {
                signer = await hre.ethers.getSigner(stableTokenOwner);
            }
            let tokenContract: Contract = await hre.ethers.getContractAt(TOKEN, tokenAddress, signer);
            console.log(await tokenContract.connect(signer).transfer(toAddress, amount));
    });
};

export { distributeTokens };