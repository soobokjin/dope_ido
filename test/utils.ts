import {ethers, network} from "hardhat";
import {BaseProvider} from "@ethersproject/providers/src.ts/base-provider";

const provider: BaseProvider = ethers.provider;


export async function accumulateBlockByBlockNumber (blockNumber: number) {
    // https://ethereum.stackexchange.com/questions/86633/time-dependent-tests-with-hardhat
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

export async function latestBlocktime (): Promise<number> {
  const { timestamp } = await provider.getBlock('latest');
  return timestamp;
}

export async function increaseTime (time: number) {
    // https://ethereum.stackexchange.com/questions/86633/time-dependent-tests-with-hardhat
    await network.provider.send("evm_increaseTime", [time])
    await network.provider.send("evm_mine") // this one will have 02:00 PM as its timestamp
}
