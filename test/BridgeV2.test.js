const { ethers, upgrades } = require('hardhat');
const { expect } = require('chai');
const { BN } = require('@openzeppelin/test-helpers');


describe('BridgeV2 unit tests', () => {

  let bridge, gateKeeper;

  const zeroAddress = ethers.constants.AddressZero;
  const State = { Active: 0, Inactive: 1 };
  const chainId = network.config.chainId;

  let owner, operator, validator, alice, bob, mallory;

  const epochs = [{
    publicKey: '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
    participantsCount: 0,
    epochNum: 0
  }, {
    publicKey: '0x12f305d7168869dbcad79545b709d2798c549112ddc7c73194038a0b30b7940309e78c5660f66e1b313f7f09a56e4ad29175d896e863cb291f5c16196539297311d00d7071269ac81d59ad42540f11e793a624776f29562519a461e0b90b5757001ffd3f6411f20042c496978b7010785fb04bca8dda902e47a2e97d15e6adcc',
    participantsCount: 40,
    epochNum: 134
  }, {
    publicKey: '0x12f305d7168869dbcad79545b709d2798c549112ddc7c73194038a0b30b7940309e78c5660f66e1b313f7f09a56e4ad29175d896e863cb291f5c16196539297311d00d7071269ac81d59ad42540f11e793a624776f29562519a461e0b90b5757001ffd3f6411f20042c496978b7010785fb04bca8dda902e47a2e97d15e6adcc',
    participantsCount: 40,
    epochNum: 135
  }];

  async function deployBridge() {
    const factory = await ethers.getContractFactory('BridgeV2');
    bridge = await factory.deploy();
    await bridge.deployed();
  }

  function calculateExpectedRate(baseFee, rate, discount, data) {
    let payAmount = new BN((baseFee).toNumber() + ((data.length) * (rate)));
    let callerDiscount = new BN((payAmount) * ((discount / (10000))));
    return (payAmount - callerDiscount);
  }

  // Deploy all contracts before each test suite
  before(async () => {
    // eslint-disable-next-line no-undef
    [owner, operator, validator, alice, bob, mallory, gateKeeper] = await ethers.getSigners();

    await deployBridge();
  });

  describe('Initial', () => {
    it('Should have correct initialize params', async() => {
      expect(await bridge.hasRole(await bridge.DEFAULT_ADMIN_ROLE(), owner.address)).to.equal(true);
      expect(await bridge.currentRequestIdChecker()).not.to.equal(zeroAddress);
      expect(await bridge.previousRequestIdChecker()).not.to.equal(zeroAddress);
      expect(await bridge.state()).to.equal(State.Inactive);

      const currentEpoch = await bridge.getCurrentEpoch();
      expect(currentEpoch[0]).to.equal(epochs[0].publicKey);
      expect(currentEpoch[1]).to.equal(epochs[0].participantsCount);
      expect(currentEpoch[2]).to.equal(epochs[0].epochNum);

      const previousEpoch = await bridge.getPreviousEpoch();
      expect(previousEpoch[0]).to.equal(epochs[0].publicKey);
      expect(previousEpoch[1]).to.equal(epochs[0].participantsCount);
      expect(previousEpoch[2]).to.equal(epochs[0].epochNum);

      const current = await ethers.getContractAt('RequestIdChecker', await bridge.currentRequestIdChecker());
      const prev = await ethers.getContractAt('RequestIdChecker', await bridge.previousRequestIdChecker());
      expect(await current.owner()).to.equal(bridge.address);
      expect(await prev.owner()).to.equal(bridge.address);
    });
  });

  describe('State', () => {
    it('Should set state', async() => {
      await bridge.connect(owner).grantRole(await bridge.OPERATOR_ROLE(), operator.address);
      expect(await bridge.state()).to.equal(State.Inactive);
      expect(await bridge.connect(operator).setState(State.Active));
      expect(await bridge.state()).to.equal(State.Active);
    });

    it('Should not set state if caller is not an operator', async() => {
      const message = `AccessControl: account ${mallory.address.toLowerCase()} is missing role ${await bridge.OPERATOR_ROLE()}`;
      await expect(bridge.connect(mallory).setState(State.Active)).to.be.revertedWith(message);
    });
  });

  describe('Epochs', () => {

    async function setNeededEpoch() {
      for (let i = 0; i < 158; ++i) {
        await bridge.connect(operator).resetEpoch();
      }
    }

    before(async () => {
      await setNeededEpoch();
      await bridge.connect(owner).grantRole(await bridge.VALIDATOR_ROLE(), validator.address);
    });

    it('Should reset epoch', async() => {
      const currentEpoch = await bridge.getCurrentEpoch();
      expect(await bridge.connect(operator).resetEpoch());
      expect(currentEpoch[2] + 1).to.equal((await bridge.getCurrentEpoch())[2]);

      // await bridge.rotateEpoch();

      const current = await ethers.getContractAt('RequestIdChecker', await bridge.currentRequestIdChecker());
      const prev = await ethers.getContractAt('RequestIdChecker', await bridge.previousRequestIdChecker());
      expect(await current.checks('0xb47f44499dc71fadfa4d1cfc80c88164c8fe90b5c3daa3fed9d442dcad935868')).to.equal(false);
      expect(await prev.checks('0xb47f44499dc71fadfa4d1cfc80c88164c8fe90b5c3daa3fed9d442dcad935868')).to.equal(false);

      // await bridge.ttt('0xb47f44499dc71fadfa4d1cfc80c88164c8fe90b5c3daa3fed9d442dcad935868');

      expect(await current.owner()).to.equal(bridge.address);
      expect(await prev.owner()).to.equal(bridge.address);
    });

    it('Should update epoch', async() => {
      // https://testnet.ftmscan.com/tx/0x51ade27a12ae01cdcf5d6e2fa965d6e627dc10f80eb4929ec2622f439fd5e1cd
      // consist epoch num 161
      const params = [
        '0x0000000000000000cd7e9f7533da9bff551880af044d594b0cad6856b3e372ece6053875e508aa2d00000000000000000000000000000000000000000000000000000000000000008318c399e6cee6671c0b10cc063ae222d010b39b46a0445585469c809c4a27fd0000000000e6b957000000000000002900000000644756d0',
        '0xfd4e010100000000000000a100000014801aea77842bf93aae10ce44b3e5a284d5a271b14e8cccadfce6ab95a68cf7d1750de6d3385be65b32df5d9223c91924165a3e63e24278eea916f454172aaf3fe9023c72327a81f69da8e954ed6f7b483fd4661f2e2813f5df8ec4beef781fd5190aa683d0a9a278db35d16d79a096f8ed976ae123a7650a65b247c940b5b01bd7a43a293157e8dc156fea9cd02dbb6eb24585c1913a5f3304a9e9e1c21c5e9742100000000000000007000000000000000d000000000000000900000000000000180000000000000005000000000000000100000000000000160000000000000019000000000000000f000000000000001400000000000000080000000000000006000000000000000b000000000000000300000000000000110000000000000002000000000000000a000000000000000c000000000000001500000000000000',
        '0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
        '0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
        0
      ];
      await expect(bridge.connect(validator).updateEpoch(params)).to.be.revertedWith('Bridge: wrong epoch number');
      await bridge.connect(operator).resetEpoch();
      expect(await bridge.connect(validator).updateEpoch(params));

      // https://testnet.ftmscan.com/tx/0x5860235a9a1b7d3417a1ed26a1f138f66faa16d59625fcb6c03ce33839bfa768
      expect(await bridge.connect(validator).updateEpoch([
        '0x0000000000000000187ab7074df8de07c92f941b91ebfee37de850debcac6d46357a47478bde379079b11699f05c2c5487a94462a0712fdc209848d16bbacb94b066da756f43f41bc195c47b1c934b333d2d731fc12032b9f2ae160a432ca2b9ead04dbb720250280000000000e6c32c000000000000002b000000006447765b',
        '0xfd4e010100000000000000a20000001480296f5faf62a5c5c1e5a3e5457b830902e84d4482cc3e504a53b88f1d18b19e4f1e6c9754a52263565aa7edc9c408f29ccd8374c76fb439742986d373d9df5e542b0fc94b13bf3e4ccbe65a16fe9d401f018ef5a0bd997b9f34db93d36055fc09166f6422f5b81d00b38c523f1e2155483c1c67edd8fa04adf2a4872d9d84e45a27c7f09a253d94ad4a16ac80d0637b9a8e5dca7295d76a6d13de9394553886d10e000000000000000c0000000000000004000000000000000f00000000000000020000000000000016000000000000000500000000000000110000000000000008000000000000000d0000000000000013000000000000000a0000000000000003000000000000001200000000000000150000000000000018000000000000000100000000000000100000000000000006000000000000000b00000000000000',
        '0x0f4c32ac3d27d5dac7827d4797dfb0ac55b1cb3a84c5ee8d7de9e28060ea75a81a4e520f884d653da71a3fb3d65f805fca5d294526118d4a301f9b67389b46132e97c40bf50399597c3d07af0f5e5df6b6893ec0c53656d767278ff58fce77b1281dbcd37cdfcf3fc75dd426ec5064ca71d2994c793a21edcbf67cf7097a0ebc',
        '0x2493a7bfab22626914a0022fe57d80eb0ee9b91c493044cf5dd9b2279a89adfa14d1f49768012d850ac54337996e6936ef92fec9c7afb9b68d297f491f49c40b',
        1048575
      ]));
    });
return;
    it('Should update epoch', async() => {
      // https://testnet.ftmscan.com/tx/0x56932ec2c81934fb5ab2ed93dbd2bf580ad0265daf470ad67ed45312ef717fe9
      // consist epoch num 134
      const params = [
        '0x00000000000000006e25eb4e6216767486fcd72f9c7c1c4c5acb7ae860ab0aaac1cf14e20958149728b136f91694913b05f866ad15927be1f098737b2e1f6c794b90ccb16f72162b10a6964a0c8b80d57e0ee317d43480a0842789bd9a38f3c0d403ac624cca9b6d0000000000d61114000000000000000f0000000063f3b214',
        '0xae010000000000000086000000288012f305d7168869dbcad79545b709d2798c549112ddc7c73194038a0b30b7940309e78c5660f66e1b313f7f09a56e4ad29175d896e863cb291f5c16196539297311d00d7071269ac81d59ad42540f11e793a624776f29562519a461e0b90b5757001ffd3f6411f20042c496978b7010785fb04bca8dda902e47a2e97d15e6adccbe1add7c8534b13a7b85ebae8b0e8b0cf7f62664197cde3d7a8dc137ad8135a6',
        '0x21877a65970fdcd95ff4854d3060de05301bf8d7cc85f11a2eb7a0efd1e015f227bb21934a432b0a07189e74b13d80e5ae89c16ae26419c30de9694385cbdab31cd98c4b930a35c511197b526bd0a44a289bc7c903a3d59a55952a6cfa3578930a8cbfe752209a424ef15be53912616397019735f2d489788aa343e7d9b3dcff',
        '0x2f4379783af6a028d27582f60e9e08b3c48496fe291387d88d20dc195f327c0c0170ed6936a0d964bad37b6ce47e7d94c6b50876df88f85cf5cb2999f0643331',
        1099511627775
      ];
      await expect(bridge.connect(validator).updateEpoch(params)).to.be.revertedWith('Bridge: wrong epoch number');
      await bridge.connect(operator).resetEpoch();
      expect(await bridge.connect(validator).updateEpoch(params));

      // https://testnet.ftmscan.com/tx/0x55c6f726f7d400b40c7919df1bcb646f16129426431a70a806a42efc2c7b77aa
      expect(await bridge.connect(validator).updateEpoch([
        '0x00000000000000000092e76bb1ca562010698a117c03241f8a9c7eacdd6c1e98b4a3bb7a52f75ad6f5a4d6498be3ef97ee0c772838096bb617694de14ce068445e6a056096f4313295817479836144529aba4f3aafe99fc9898d17003e1629150cfe8da6b5b620a90000000000d6125600000000000000110000000063f3b5eb',
        '0xae010000000000000087000000288012f305d7168869dbcad79545b709d2798c549112ddc7c73194038a0b30b7940309e78c5660f66e1b313f7f09a56e4ad29175d896e863cb291f5c16196539297311d00d7071269ac81d59ad42540f11e793a624776f29562519a461e0b90b5757001ffd3f6411f20042c496978b7010785fb04bca8dda902e47a2e97d15e6adcc7d406a1c28cc6ff22f68c8de2b48f0cea099770462bc26c8f110d3d8eb7d1e2a',
        '0x168a65ff84313087eddd945a60354293bd365a20240e775defe64ae98dc8facc0a7da3293b431982af026fcdf13ac2d2ec3dfd5d6385c0a3d7b91e104151889c022897f3825b6601b0773930c1ce5c4944c62b89416994c26604d60508a3b24c13b2b35b0ad5ebbc3f873dcdf7df92e4767134d591a3b3e221e352d02833b653',
        '0x00f6421d39f71d79b6cb26ff86bc115bf0ab84d43bd4b4137317adbbd1c9e82d2f2d3f827e5cbce10caa3beaebf41bb42bd9f2acefd111fd07e0ee5e72b8c457',
        1082323034591
      ]));

      const currentEpoch = await bridge.getCurrentEpoch();
      expect(currentEpoch[0]).to.equal(epochs[2].publicKey);
      expect(currentEpoch[1]).to.equal(epochs[2].participantsCount);
      expect(currentEpoch[2]).to.equal(epochs[2].epochNum);

      const previousEpoch = await bridge.getPreviousEpoch();
      expect(previousEpoch[0]).to.equal(epochs[1].publicKey);
      expect(previousEpoch[1]).to.equal(epochs[1].participantsCount);
      expect(previousEpoch[2]).to.equal(epochs[1].epochNum);
    });

    it('Should not reset epoch if caller is not an admin', async() => {
      const message = `AccessControl: account ${mallory.address.toLowerCase()} is missing role ${await bridge.OPERATOR_ROLE()}`;
      await expect(bridge.connect(mallory).resetEpoch()).to.be.revertedWith(message);
    });
  });
return;
  describe('Send / Receive', () => {
    // https://testnet.ftmscan.com/tx/0x7d406a1c28cc6ff22f68c8de2b48f0cea099770462bc26c8f110d3d8eb7d1e2a
    // except nonce
    const sendParams = [
      '0x000000000000000000000000000000000000000000000000000000d9ff7ae15f',
      '0x0000000000000000f5a4d6498be3ef97ee0c772838096bb617694de14ce068445e6a056096f43132f5a4d6498be3ef97ee0c772838096bb617694de14ce068445e6a056096f431322dbb9b4263a0ac584ede7b65a0ce8de4fcb283a95106957d8e8297268ec82f690000000000d6125200000000000000100000000063f3b5da',
      '0x0000000000000000000000000000000000000140',
      '0x0000000000000000000000000000000000000420',
      1216          
    ];

    // https://testnet.ftmscan.com/tx/0x41df2a3652f449c9bc61057bea0871c6150d1a240875ea76a19eb7685ed11e30
    // epoch 134
    const receiveParams = [
      '0x00000000000138817a7e590a28ac9daad7146ed6238ef80908ce6c2b0f3547043f25999e654efc4cf5a4d6498be3ef97ee0c772838096bb617694de14ce068445e6a056096f4313243e5a846eb9281892ba0b588bedf36c98c2e0f0624a1fd532280465e2a2193020000000001ebd995000000000000000d0000000063f3b2ad',
      '0xa12edd32b48923bed4a8961bca5f77dfd3b808a89c3933c042239d82f4feff2286f86ebe86ef539337d5827db84a19da3838c1b67c000000000000000000000000e4664241aa7ecc62f7010c94d49bb84ada46465f44faad85c8000000000000000000000000000000000000000000000000016c3d976cb1a0672edd32b48923bed4a8961bca5f77dfd3b808a89c3933c042239d82f4feff2286a20f000000000000',
      '0x22207f18fd171747d17ef6131d64255ae3f9ec5e7cab2d191c57b113a18718332ea6a5fc21bda4ffa040b2338597526945addfd973008da2cda6fcf7175406fd086a547a8161abee09d4dc83b6b0ed9246695b339e28aaa7e248b7c3c0dba3801d574bd799065dc52b19cb751c602e43026eec2b8dd6ac3a7d2ce265b0c31780',
      '0x1e5a0657723e6bb8c3d06d651c50de3da4ba602bbe4502e3c801cba95da4a81304b5a0058f55d88c0453cdd39c64ef0bb52bb21b07c349597706ff5bd0fecce0',
      687186341367
    ];

    before(async () => {
      await bridge.connect(owner).grantRole(await bridge.GATEKEEPER_ROLE(), gateKeeper.address);
    });

    it('Should accept receive from prev epoch', async() => {
      expect(await bridge.connect(validator).receiveV2([receiveParams]));
    });

    it('Should emit event with error if request id already used', async() => {
      await expect(bridge.receiveV2([receiveParams])).to.be.revertedWith('Bridge: request id already seen');
    });

    it('Should revert receive if bridge in Inactive state', async() => {
      await bridge.setState(State.Inactive);
      await expect(bridge.receiveV2([receiveParams])).to.be.revertedWith('Bridge: state inactive');
      await bridge.setState(State.Active);
    });

    it('Should revert receive if epoch too old', async() => {
      // https://testnet.ftmscan.com/tx/0xe53748005b322820fa718d0c334bf57a4720ceff95cee86fa8c5b4f65345c65d
      // epoch 133
      await expect(bridge.receiveV2([[
        '0x0000000000000005ab56947cefd2b131eb1381f7e4ac5af2974cb1e72393bfc38762c1aee8cee25c28b136f91694913b05f866ad15927be1f098737b2e1f6c794b90ccb16f72162b96993070c4eab6ee136f1728e49ef5e276b5865ce290d93cdc2de0cedbf6e8d600000000008218d400000000000000050000000063f3b0dc',
        '0xa1a452cc380d71b98a297a45a6d967f75a881bcfd106ef5235ca006148b52d0b6c59b6730113e5da413aaa59e1900d97445c41e904000000000000000000000000e4664241aa7ecc62f7010c94d49bb84ada46465f44faad85c8000000000000000000000000000000000000000000000000415b00fc00151c73a452cc380d71b98a297a45a6d967f75a881bcfd106ef5235ca006148b52d0b6ca20f000000000000',
        '0x21877a65970fdcd95ff4854d3060de05301bf8d7cc85f11a2eb7a0efd1e015f227bb21934a432b0a07189e74b13d80e5ae89c16ae26419c30de9694385cbdab31cd98c4b930a35c511197b526bd0a44a289bc7c903a3d59a55952a6cfa3578930a8cbfe752209a424ef15be53912616397019735f2d489788aa343e7d9b3dcff',
        '0x14577d0624e0cc959a82fcf4cf0c16f5c6768eb4601d781f828ec7ad8ff791b91e493fb47df8ac22fea3f3a79b93e8b22c7c1d48aeb5b035209173c660fbbf1e',
        1099511627775
      ]])).to.be.revertedWith('Bridge: wrong epoch');
    });

    it('Should send request', async() => {
      expect(await bridge.connect(gateKeeper).sendV2(sendParams, '0x0000000000000000000000000000000000000080', 0));
    });

    it('Should not send request if nonce incorrect', async() => {
      await expect(bridge.connect(gateKeeper).sendV2(sendParams, '0x0000000000000000000000000000000000000080', 42))
        .to.be.revertedWith('Bridge: nonce mismatch');
    });

    it('Should not send request if caller is not a gate keeper', async() => {
      const message = `AccessControl: account ${mallory.address.toLowerCase()} is missing role ${await bridge.GATEKEEPER_ROLE()}`;
      await expect(bridge.connect(mallory).sendV2(sendParams, '0x0000000000000000000000000000000000000080', 0))
        .to.be.revertedWith(message);
    });

    it('Should not send request if bridge in Inactive state', async() => {
      await bridge.setState(State.Inactive);
      await expect(bridge.connect(gateKeeper).sendV2(sendParams, '0x0000000000000000000000000000000000000080', 0))
        .to.be.revertedWith('Bridge: state inactive');
      await bridge.setState(State.Active);
    });

    it('Should not send request if epoch is not set', async() => {
      await bridge.resetEpoch();
      await expect(bridge.connect(gateKeeper).sendV2(sendParams, '0x0000000000000000000000000000000000000080', 0))
        .to.be.revertedWith('Bridge: epoch not set');
    });
  });
});