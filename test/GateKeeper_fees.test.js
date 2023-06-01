const { ethers, network } = require('hardhat');
const { BN } = require('@openzeppelin/test-helpers');
const { expect } = require('chai');

contract('GateKeeper', () => {
  let payToken, bridgeV2, gateKeeper;
  let owner, operator, alice, bob;
  const chainId = network.config.chainId;

  const baseFeeNativeUnits = {} // wei
  const rateNativeUnits = {} // wei
  let baseFee = 100; // USD
  let rate = 0.1; // USD
  const units = 10 ** 18; // wei
  const chainIds = {  // https://chainlist.org/
    "fantom": 250,
    "arbitrum": 42161,
    "avalanche": 43114,
    "binance": 56,
    "ethereum": 1,
    "polygon": 137,
    "hardhat": 31337,
  }
  const nativeTokenPrice = { // USD
    "fantom": 0.427,
    "arbitrum": 1.432,
    "avalanche": 18.34,
    "binance": 339.16,
    "ethereum": 1913,
    "polygon": 1.007,
    "hardhat": 1,
  }                       
  234 000 000 000 000 000 000
  for (let chain of Object.keys(chainIds)) {
    baseFeeNativeUnits[chainIds[chain]] = ethers.utils.parseEther(Math.round(baseFee / nativeTokenPrice[chain]).toString())
    console.log('fees', baseFeeNativeUnits[chainIds[chain]])
    rateNativeUnits[chainIds[chain]] = ethers.utils.parseEther(Math.round(rate / nativeTokenPrice[chain]).toString())
    console.log('rates', rateNativeUnits[chainIds[chain]])
  }

  async function setFees(contractAddress) {
    const gateKeeper = await ethers.getContractAt("GateKeeper", contractAddress);
    await gateKeeper.connect(operator).setBaseFee([
      [
        chainId,
        ethers.constants.AddressZero,
        baseFeeNativeUnits[chainId]
      ]
    ]);
    await gateKeeper.connect(operator).setRate([
      [
        chainId,
        ethers.constants.AddressZero,
        rateNativeUnits[chainId]
      ]
    ]);
  }

  describe('local test', () => {
    before(async () => {
      [owner, operator, alice, bob] = await ethers.getSigners();
      let factory = await ethers.getContractFactory('TestTokenPermit');
      payToken = await factory.deploy('TestToken', 'TT');
      await payToken.deployed();
      factory = await ethers.getContractFactory('BridgeV2Mock');
      bridgeV2 = await factory.deploy();
      await bridgeV2.deployed();
      factory = await ethers.getContractFactory('GateKeeper');
      gateKeeper = await factory.deploy(bridgeV2.address);
      await gateKeeper.deployed();
      await gateKeeper.connect(owner).grantRole(await gateKeeper.OPERATOR_ROLE(), operator.address);
    })

    it('Should set base fee ethereum', async function () {
      setFees(gateKeeper.address);
      expect(await gateKeeper.baseFees(chainId, ethers.constants.AddressZero)).to.equal(baseFeeNativeUnits[chainId]);
    });

    it('Should set rate ethereum', async function () {
      setFees(gateKeeper.address);
      expect(await gateKeeper.rates(chainId, ethers.constants.AddressZero)).to.equal(rateNativeUnits[chainId]);
    });

    it('Should set base fee fantom', async function () {
      setFees(gateKeeper.address);
      expect(await gateKeeper.baseFees(chainId, ethers.constants.AddressZero)).to.equal(baseFeeNativeUnits[chainId]);
    });

    it('Should set rate fantom', async function () {
      setFees(gateKeeper.address);
      expect(await gateKeeper.rates(chainId, ethers.constants.AddressZero)).to.equal(rateNativeUnits[chainId]);
    });

  })
})