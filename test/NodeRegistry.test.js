const { ethers } = require('hardhat');
require('ethers');
const { expect } = require('chai');
const { addressToBytes32 } = require('../utils/helper');

async function getPermitSignature(signer, token, spender, value, deadline) {
  const [nonce, name, version, chainId] = await Promise.all([
    token.nonces(signer.address),
    'EYWA',
    '1',
    signer.getChainId(),
  ]);

  return ethers.utils.splitSignature(
    await signer._signTypedData(
      {
        name,
        version,
        chainId,
        verifyingContract: token.address,
      },
      {
        Permit: [
          {
            name: 'owner',
            type: 'address',
          },
          {
            name: 'spender',
            type: 'address',
          },
          {
            name: 'value',
            type: 'uint256',
          },
          {
            name: 'nonce',
            type: 'uint256',
          },
          {
            name: 'deadline',
            type: 'uint256',
          },
        ],
      },
      {
        owner: signer.address,
        spender,
        value,
        nonce,
        deadline,
      }
    )
  );
}

describe('NodeRegistry local test', () => {

  let nodeSigner, nodeSigner2, newSigner, nodeOwner, nodeOwner2, accountWithoutNode, operator;
  let nodeRegistry;
  let EPOA;
  let nodeData;

  const State = { Registered: 0, Ready: 1, Disabled: 2, Removed: 3, Deleted: 4, Penalized: 5 };
  const Mode = { Witness: 0, Validator: 1 };

  beforeEach(async () => {
    [nodeSigner, nodeSigner2, newSigner, nodeOwner, nodeOwner2, accountWithoutNode, operator] = await ethers.getSigners();
    const NodeRegistry = await ethers.getContractFactory('NodeRegistryV2');
    nodeRegistry = await NodeRegistry.deploy();
    await nodeRegistry.deployed();

    const tokenFactory = await ethers.getContractFactory('EPOA');
    EPOA = await tokenFactory.deploy(nodeRegistry.address);
    await EPOA.deployed();

    nodeData = {
      nodeId: 1,
      owner: nodeOwner.address,
      signer: nodeSigner.address,
      version: 3,
      hostId: '888',
      blsPubKey: addressToBytes32(nodeOwner.address),
      collateral: ethers.utils.parseEther('2.0'),
      state: State.Ready,
      mode: Mode.Validator
    };

    await nodeRegistry.grantRole(await nodeRegistry.OPERATOR_ROLE(), operator.address);
  });

  it('should set utility token', async function () {
    await nodeRegistry.setUtilityToken(EPOA.address);
    expect(await nodeRegistry.EPOA()).to.be.equal(EPOA.address);
  });

  it('should revert utility token setting', async function () {
    await expect(nodeRegistry.setUtilityToken(ethers.constants.AddressZero)).to.be.revertedWith('NodeRegistry: zero address');
  });

  it('should revert add node if insufficient balance', async function () {
    await nodeRegistry.setUtilityToken(EPOA.address);
    await EPOA.mint(nodeOwner.address, ethers.utils.parseEther('0.1'));
    const currentBalance = await EPOA.balanceOf(nodeOwner.address);

    const deadline = ethers.constants.MaxUint256;

    const { v, r, s } = await getPermitSignature(
      nodeOwner,
      EPOA,
      nodeRegistry.address,
      currentBalance,
      deadline
    );

    await expect(nodeRegistry.connect(nodeOwner).addNode(nodeData, deadline, v, r, s)).to.be.revertedWith('NodeRegistry: not enough funds');
  });

  it('should revert token setting when not owner', async function () {
    const message = `AccessControl: account ${nodeOwner.address.toLowerCase()} is missing role ${await nodeRegistry.DEFAULT_ADMIN_ROLE()}`;
    await expect(nodeRegistry.connect(nodeOwner).setUtilityToken(ethers.constants.AddressZero)).to.be.revertedWith(message);
  });

  it('should revert if not a node owner', async function () {
    await EPOA.mint(nodeOwner.address, nodeData.collateral);
    const currentBalance = await EPOA.balanceOf(nodeOwner.address);

    const deadline = ethers.constants.MaxUint256;

    const { v, r, s } = await getPermitSignature(
      nodeOwner,
      EPOA,
      nodeRegistry.address,
      currentBalance,
      deadline
    );

    await expect(nodeRegistry.connect(accountWithoutNode).addNode(nodeData, deadline, v, r, s)).to.be.revertedWith('NodeRegistry: not owner');
  });

  it('should revert if node host id 0', async function () {
    await EPOA.mint(nodeOwner.address, nodeData.collateral);
    const currentBalance = await EPOA.balanceOf(nodeOwner.address);

    const deadline = ethers.constants.MaxUint256;

    const { v, r, s } = await getPermitSignature(
      nodeOwner,
      EPOA,
      nodeRegistry.address,
      currentBalance,
      deadline
    );
    const nodeData3 = { ...nodeData };
    nodeData3.hostId = 0;
    await expect(nodeRegistry.connect(nodeOwner).addNode(nodeData3, deadline, v, r, s)).to.be.revertedWith('NodeRegistry: zero host key');
  });

  it('should add node', async function () {
    await nodeRegistry.setUtilityToken(EPOA.address);
    await EPOA.mint(nodeOwner.address, nodeData.collateral);
    const currentBalance = await EPOA.balanceOf(nodeOwner.address);

    const deadline = ethers.constants.MaxUint256;

    const { v, r, s } = await getPermitSignature(
      nodeOwner,
      EPOA,
      nodeRegistry.address,
      currentBalance,
      deadline
    );

    await nodeRegistry.connect(nodeOwner).addNode(nodeData, deadline, v, r, s);

    const result = await nodeRegistry['getNodes(address)'](nodeOwner.address);
    expect(result[0].owner).to.equal(nodeOwner.address);
    expect(result[0].nodeId).to.equal(1);
  });

  describe('local tests with added node', () => {

    beforeEach(async () => {
      [nodeSigner, nodeSigner2, newSigner, nodeOwner, nodeOwner2, accountWithoutNode, operator] = await ethers.getSigners();
      const NodeRegistry = await ethers.getContractFactory('NodeRegistryV2');
      nodeRegistry = await NodeRegistry.deploy();
      await nodeRegistry.deployed();

      const tokenFactory = await ethers.getContractFactory('EPOA');
      EPOA = await tokenFactory.deploy(nodeRegistry.address);
      await EPOA.deployed();

      nodeData = {
        nodeId: 1,
        owner: nodeOwner.address,
        signer: nodeSigner.address,
        version: 3,
        hostId: '888',
        blsPubKey: addressToBytes32(nodeOwner.address),
        collateral: ethers.utils.parseEther('2.0'),
        state: State.Ready,
        mode: Mode.Validator
      };

      await nodeRegistry.setUtilityToken(EPOA.address);
      await EPOA.mint(nodeOwner.address, nodeData.collateral);
      const currentBalance = await EPOA.balanceOf(nodeOwner.address);

      const deadline = ethers.constants.MaxUint256;

      const { v, r, s } = await getPermitSignature(
        nodeOwner,
        EPOA,
        nodeRegistry.address,
        currentBalance,
        deadline
      );

      await nodeRegistry.connect(nodeOwner).addNode(nodeData, deadline, v, r, s);

      await nodeRegistry.grantRole(await nodeRegistry.OPERATOR_ROLE(), operator.address);
    });

    it('should get nodes', async function () {
      const nodes = await nodeRegistry['getNodes()']();
      expect(nodes.length).to.equal(1);
    });

    it('should get node by signer', async function () {
      const node = await nodeRegistry.getNode(nodeSigner.address);
      expect(node.signer).to.equal(nodeSigner.address);
    });

    it('should revert if node exists', async function () {
      await EPOA.mint(nodeOwner.address, nodeData.collateral);
      const currentBalance = await EPOA.balanceOf(nodeOwner.address);

      const deadline = ethers.constants.MaxUint256;

      const { v, r, s } = await getPermitSignature(
        nodeOwner,
        EPOA,
        nodeRegistry.address,
        currentBalance,
        deadline
      );

      expect(nodeRegistry.connect(nodeOwner).addNode(nodeData, deadline, v, r, s)).to.be.revertedWith('NodeRegistry: node already exists');
    });

    it('should get node by owner', async function () {
      const result = await nodeRegistry['getNodes(address)'](nodeOwner.address);
      expect(result[0].owner).to.equal(nodeOwner.address);
    });

    it('should get node by signer', async function () {
      const result = await nodeRegistry['getNodes(address)'](nodeOwner.address);
      expect(result[0].owner).to.equal(nodeOwner.address);
    });

    it('should update node version', async function () {
      await nodeRegistry.connect(nodeSigner).updateNodeVersion(1, 99);
      const result = await nodeRegistry['getNodes(address)'](nodeOwner.address);
      expect(result[0].version).to.equal(BigInt(99));
    });

    it('should revert node not exist', async function () {
      await expect(nodeRegistry.connect(nodeOwner).updateNodeSigner(1, ethers.constants.AddressZero)).to.be.revertedWith('NodeRegistry: zero address');
    });

    it('should revert if signer already assigned', async function () {
      await expect(nodeRegistry.connect(nodeOwner).updateNodeSigner(1, nodeSigner.address)).to.be.revertedWith('NodeRegistry: signer already assigned');
    });

    it('should update signer', async function () {
      await nodeRegistry.connect(nodeOwner).updateNodeSigner(1, newSigner.address);
      const result = await nodeRegistry['getNodes(address)'](nodeOwner.address);
      expect(result[0].signer).to.equal(newSigner.address);
    });

    it('should change state to Removed', async function () {
      let node = (await nodeRegistry['getNodes(address)'](nodeOwner.address))[0];
      expect(node.state).to.eql(State.Registered);
      await nodeRegistry.connect(nodeOwner).removeNode(node.nodeId);
      node = (await nodeRegistry['getNodes(address)'](nodeOwner.address))[0];
      expect(node.state).to.eql(State.Removed);
    });

    it('should revert removeNode if id is wrong', async function () {
      const nodeId = 99;
      expect(nodeRegistry.connect(nodeOwner).removeNode(nodeId)).to.be.revertedWith('NodeRegistry: wrong id');
    });

    it('should revert removeNode if caller is not node owner', async function () {
      const node = (await nodeRegistry['getNodes(address)'](nodeOwner.address))[0];
      await expect(nodeRegistry.connect(accountWithoutNode).removeNode(node.nodeId)).to.be.revertedWith('NodeRegistry: not owner');
    });

    it('should change state to Ready', async function () {
      let node = (await nodeRegistry['getNodes(address)'](nodeOwner.address))[0];
      await nodeRegistry.connect(nodeOwner).removeNode(node.nodeId);
      await nodeRegistry.connect(nodeOwner).setState(node.nodeId, State.Ready);
      node = (await nodeRegistry['getNodes(address)'](nodeOwner.address))[0];
      expect(node.state).to.eql(State.Ready);
    });

    it('should revert when wrong id', async function () {
      await expect(nodeRegistry.connect(nodeOwner).setState(999, State.Deleted)).to.be.revertedWith('NodeRegistry: wrong id');
    });

    it('should change state to Deleted', async function () {
      let node = (await nodeRegistry['getNodes(address)'](nodeOwner.address))[0];
      await nodeRegistry.connect(nodeOwner).removeNode(node.nodeId);
      await nodeRegistry.connect(operator).setState(node.nodeId, State.Deleted);

      node = (await nodeRegistry['getNodes(address)'](nodeOwner.address))[0];
      expect(node.state).to.equal(State.Deleted);
    });

    it('should burn EPOA tokens', async function () {
      const node = (await nodeRegistry['getNodes(address)'](nodeOwner.address))[0];
      await nodeRegistry.connect(nodeOwner).removeNode(node.nodeId);
      await nodeRegistry.connect(operator).setState(node.nodeId, State.Deleted);
      const oldBalance = await EPOA.balanceOf(nodeRegistry.address);
      await nodeRegistry.connect(nodeOwner).removeNode(node.nodeId);
      const newBalance = await EPOA.balanceOf(nodeRegistry.address);
      expect(oldBalance).to.be.above(newBalance);
    });

  });

});
