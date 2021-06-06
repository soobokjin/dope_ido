import {HardhatUserConfig} from "hardhat/types";
import "@nomiclabs/hardhat-waffle";
import "hardhat-deploy";
import {readFileSync} from 'fs';
import { distributeTokens } from "./scripts/tasks/distribute_tokens_for_test";

let getPrivateEnv: Function = function (filePath: string): Map<String, String> {
    let env = readFileSync(filePath, 'utf-8');

    let splitEnv: Array<string> = env.split(/\n/);
    let envMapper = new Map();
    for (let index in splitEnv) {
        let values = splitEnv[index].split("=");
        envMapper.set(values[0], values[1]);
    }
    return envMapper;
}
let envs: Map<String, String> = getPrivateEnv('./.env');

const ROPSTEN_INFURA_KEY = envs.get('ROPSTEN_INFURA_KEY');
const ROPSTEN_DEPLOYER = envs.get('ROPSTEN_DEPLOYER');
const ROPSTEN_SALETOKEN_DEPLOYER = envs.get('ROPSTEN_SALETOKEN_DEPLOYER');

distributeTokens();

const config: HardhatUserConfig = {
    solidity: {
        compilers: [{version: "0.8.0", settings: {}}],
        settings: {
            optimizer: {
                enabled: true,
                runs: 200,
            },
        },
    },
    networks: {
        hardhat: {},
        ropsten: {
            url: `https://ropsten.infura.io/v3/${ROPSTEN_INFURA_KEY}`,
            accounts: [`${ROPSTEN_DEPLOYER}`, `${ROPSTEN_SALETOKEN_DEPLOYER}`],
        },
    },
    paths: {
        sources: './contracts',
        artifacts: './build/artifacts',
        cache: './build/cache',
        deploy: './scripts/deploy',
        deployments: './deployments',
        tests: './test',
    },
    namedAccounts: {
        dopeOwner: 0,
        stableTokenOwner: 0,
        saleTokenOwner: 1,
    },
};
export default config;
