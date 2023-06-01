const { ethers, network } = require('hardhat');
const { BN } = require('@openzeppelin/test-helpers');
const { expect } = require('chai');

contract('GateKeeper', () => {
  let baseFeeNative, baseFeeToken, nativeRate, tokenRate, discount;
  let payToken, bridgeV2, gateKeeper;
  let owner, operator, alice, bob, treasury;
  const chainId = network.config.chainId;

  function calculateExpectedRate(baseFee, rate, discount, data) {
    let payAmount = new BN((baseFee).toNumber() + ((data.length) * (rate)));
    let callerDiscount = new BN((payAmount) * ((discount / (10000))));
    return (payAmount - callerDiscount);
  }

  describe('local test', () => {
    before(async () => {
      [owner, operator, alice, bob, treasury] = await ethers.getSigners();
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

    it('Should set native base fee', async function () {
      const fee = BigInt(Math.floor(Math.random() * (10 - 1) + 1)) * BigInt(10 ** 3);
      await gateKeeper.connect(operator).setBaseFee([
        [
          chainId,
          ethers.constants.AddressZero,
          fee
        ]
      ]);
      expect(await gateKeeper.baseFees(chainId, ethers.constants.AddressZero)).to.equal(fee);
    });

    it('Should set token base fee', async function () {
      const fee = BigInt(Math.floor(Math.random() * (10 - 1) + 1)) * BigInt(10 ** 3);
      await gateKeeper.connect(operator).setBaseFee([
        [chainId, payToken.address, fee]
      ]);
      expect(await gateKeeper.baseFees(chainId, payToken.address)).to.equal(fee);
    })

    it('Should set native rates', async function () {
      const rate = BigInt(Math.floor(Math.random() * (10000 - 1) + 1));
      await gateKeeper.connect(operator).setRate([
        [chainId, ethers.constants.AddressZero, rate]
      ]);
      expect(await gateKeeper.rates(chainId, ethers.constants.AddressZero)).to.equal(rate);
    })

    it('Should set token rates', async function () {
      const rate = BigInt(Math.floor(Math.random() * (10000 - 1) + 1));
      await gateKeeper.connect(operator).setRate([
        [chainId, payToken.address, rate]
      ]);
      expect(await gateKeeper.rates(chainId, payToken.address)).to.equal(rate);
    })

    it('Should set discount', async function () {
      const discount = 1000; // eg 10%
      await gateKeeper.connect(operator).setDiscount(owner.address, discount);
      expect(await gateKeeper.discounts(owner.address)).to.equal(discount);
    })

    it('Should calculate transaction cost in native asset', async function () {
      const data = ethers.utils.randomBytes(Math.floor(Math.random() * (255 - 1) + 1));
      const expectedCost = calculateExpectedRate(
        await gateKeeper.baseFees(chainId, ethers.constants.AddressZero),
        await gateKeeper.rates(chainId, ethers.constants.AddressZero),
        await gateKeeper.discounts(owner.address),
        data
      );
      const cost = await gateKeeper.calculateCost(
        ethers.constants.AddressZero,
        data.length,
        chainId,
        owner.address
      );
      expect(expectedCost).to.be.equal(cost);
    });

    it('Should calculate transaction cost in ERC20 token', async function () {
      const data = ethers.utils.randomBytes(Math.floor(Math.random() * (255 - 1) + 1));
      const expectedCost = calculateExpectedRate(
        await gateKeeper.baseFees(chainId, payToken.address),
        await gateKeeper.rates(chainId, payToken.address),
        await gateKeeper.discounts(owner.address),
        data
      );
      const cost = await gateKeeper.calculateCost(
        payToken.address,
        data.length,
        chainId,
        owner.address
      );
      expect(expectedCost).to.be.equal(cost);
    });

    it('Should send cross-chain call', async function () {
      await payToken.mint(alice.address, ethers.utils.parseEther('1'));
      await payToken.connect(alice).approve(bridgeV2.address, ethers.utils.parseEther('1'));
      // console.log(await payToken.balanceOf(alice.address));
      const ABI = [ 
        "function transfer(address to, uint256 amount)",
        "function transferFrom(address from, address to, uint256 amount)"
      ];
      const interface = new ethers.utils.Interface(ABI);
      let data = interface.encodeFunctionData("transferFrom", [ alice.address, bob.address, ethers.utils.parseEther('1') ]);
      data = ethers.utils.defaultAbiCoder.encode([ "address", "bytes" ], [ payToken.address, data ]);
      const cost = await gateKeeper.calculateCost(ethers.constants.AddressZero, data.length, chainId, owner.address);
      await gateKeeper.sendData(data, payToken.address, chainId, ethers.constants.AddressZero, { value: cost });
      console.log('cost', cost)
      const requestId = '0x221dc2eae25319d2a3387a2def5cace15376aed6e3b32b8cac20a7adeaed0d81';
      const receivedData = '0x8bd345690000000000000000000000000000000000000000000000000000000000000060000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb922660000000000000000000000000000000000000000000000000000000000007a6900000000000000000000000000000000000000000000000000000000000000e00000000000000000000000005fbdb2315678afecb367f032d93f642f64180aa30000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000006423b872dd00000000000000000000000070997970c51812dc3a010c7d01b50e0d17dc79c80000000000000000000000003c44cdddb6a900fa2b585dd299e03d12fa4293bc0000000000000000000000000000000000000000000000000de0b6b3a764000000000000000000000000000000000000000000000000000000000000';
      const to = '0x5fbdb2315678afecb367f032d93f642f64180aa3';
      await bridgeV2.receiveV2([[requestId, to, receivedData]]);
      // console.log(await payToken.balanceOf(bob.address));
    });

    it('Should send cross-chain call with ether payment', async function () {
      await payToken.mint(alice.address, ethers.utils.parseEther('1'));
      await payToken.connect(alice).approve(bridgeV2.address, ethers.utils.parseEther('1'));
      console.log(await payToken.balanceOf(alice.address));
      const ABI = [ 
        "function transfer(address to, uint256 amount)",
        "function transferFrom(address from, address to, uint256 amount)"
      ];
      const interface = new ethers.utils.Interface(ABI);
      let data = interface.encodeFunctionData("transferFrom", [ alice.address, bob.address, ethers.utils.parseEther('1') ]);
      data = ethers.utils.defaultAbiCoder.encode([ "address", "bytes" ], [ payToken.address, data ]);
      const cost = await gateKeeper.calculateCost(ethers.constants.AddressZero, data.length, chainId, owner.address);
      const initialBalance = await web3.eth.getBalance(gateKeeper.address);
      await gateKeeper.sendData(data, ethers.constants.AddressZero, chainId, ethers.constants.AddressZero, { value: cost });
      const requestId = '0x221dc2eae25319d2a3387a2def5cace15376aed6e3b32b8cac20a7adeaed0d81';
      const receivedData = '0x8bd345690000000000000000000000000000000000000000000000000000000000000060000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb922660000000000000000000000000000000000000000000000000000000000007a6900000000000000000000000000000000000000000000000000000000000000e00000000000000000000000005fbdb2315678afecb367f032d93f642f64180aa30000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000006423b872dd00000000000000000000000070997970c51812dc3a010c7d01b50e0d17dc79c80000000000000000000000003c44cdddb6a900fa2b585dd299e03d12fa4293bc0000000000000000000000000000000000000000000000000de0b6b3a764000000000000000000000000000000000000000000000000000000000000';
      const to = '0x5fbdb2315678afecb367f032d93f642f64180aa3';
      await bridgeV2.receiveV2([[requestId, to, receivedData]]);
      const finalBalance = await web3.eth.getBalance(gateKeeper.address);
      expect(parseInt(cost) + parseInt(initialBalance)).to.be.equal(parseInt(finalBalance))
    });

    it('Should not withdraw token fees if treasury not set', async function () {
      await expect(gateKeeper.connect(operator).withdrawFees(payToken.address, ethers.utils.parseEther('1')))
        .to.be.revertedWith('GateKeeper: treasury not set');
    });

    it('Should withdraw token fees', async function () {
      await gateKeeper.setTreasury(treasury.address);
      const oldBalance = await payToken.balanceOf(treasury.address);
      await payToken.mint(gateKeeper.address, ethers.utils.parseEther('1'));
      await gateKeeper.connect(operator).withdrawFees(payToken.address, ethers.utils.parseEther('1'));
      expect(await payToken.balanceOf(treasury.address)).to.be.above(oldBalance)
    });

    it('Should allow the owner to withdraw Ether', async () => {
      const initialBalance = await web3.eth.getBalance(treasury.address);
      await gateKeeper.connect(operator).withdrawFees(ethers.constants.AddressZero, 1000);
      const finalBalance = await web3.eth.getBalance(treasury.address);
      expect(Number(finalBalance.substring(18))).to.be.above(Number(initialBalance.substring(18)))
    });
  
    it('Should revert when withdraw amount exceeds balance', async () => {
      const amount = ethers.utils.parseEther('1');
      await expect(
        gateKeeper.connect(operator).withdrawFees(ethers.constants.AddressZero, amount)
      ).to.be.revertedWith('GateKeeper: failed to send Ether');
    });

  })
})