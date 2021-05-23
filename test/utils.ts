import {ethers, network} from "hardhat";
import {BaseProvider} from "@ethersproject/providers/src.ts/base-provider";

const provider: BaseProvider = ethers.provider;


export async function accumulateBlockByBlockNumber (blockNumber: number) {
    await network.provider.send("evm_setAutomine", [false])
    let currentBlockNumber: number = await provider.getBlockNumber();

    for (let i = 0; i < blockNumber - currentBlockNumber; i++) {
        await network.provider.send("evm_mine");
    }
    await network.provider.send("evm_setAutomine", [true])
}


export async function accumulateBlockByBlockCnt (blockCnt: number) {
    await network.provider.send("evm_setAutomine", [false])
    for (let i = 0; i < blockCnt; i++) {
        await network.provider.send("evm_mine");
    }
    await network.provider.send("evm_setAutomine", [true])
}