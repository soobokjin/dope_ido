import { ethers } from "hardhat";
import chai from "chai";
import { Contract, ContractFactory } from 'ethers';
import { solidity } from "ethereum-waffle";
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';

chai.use(solidity);
const { expect } = chai;
describe("Tests", () => {
  let signers: SignerWithAddress;
  before('setup accounts', async () => {
    [signers] = await ethers.getSigners();
  });
  let DOPE: ContractFactory;

  before('fetch contract factories', async () => {
    DOPE = await ethers.getContractFactory('DOPE');
  });

  describe("Test", () => {
    let token: Contract;

    before('deploy', async () => {
      token = await DOPE.connect(signers).deploy(
          'test',
          signers.address,
          5,
          signers.address,
          signers.address,
          signers.address,
          5,
          5,
          5
      );
    });
    it('simple', async () => {
        expect(await token.getSaleTokenAddress()).to.eq(signers.address);
    })
  });
});