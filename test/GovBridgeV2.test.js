const { ethers } = require('hardhat');
require('ethers');
const { expect } = require('chai');

describe('GovBridgeV2 test', () => {

    let deployer, notAdmin, mockNodeRegistry, govBridge;

    before(async () => {
        [deployer, notAdmin, mockNodeRegistry] = await ethers.getSigners();
        const factory = await ethers.getContractFactory('GovBridgeV2');
        govBridge = await factory.deploy();
        await govBridge.deployed();
    });

    it('should set NodeRegistry', async function () {
        await govBridge.setNodeRegistry(mockNodeRegistry.address);
        expect(await govBridge.nodeRegistry()).to.equal(mockNodeRegistry.address);
    });

    it('should update epoch', async function () {
        const lastRequestTime = await govBridge.lastRequestEpochUpdateTime();
        await govBridge.requestEpochUpdate();
        expect(await govBridge.lastRequestEpochUpdateTime()).to.above(lastRequestTime);
    });

    it('should revert version update', async function () {
        const message = `AccessControl: account ${notAdmin.address.toLowerCase()} is missing role ${await govBridge.OPERATOR_ROLE()}`;
        await expect(govBridge.connect(notAdmin).requestProtocolVersionUpdate(3)).to.be.revertedWith(message);
    });

    it('should change epochMinDuration', async function () {
        const minDuration = BigInt(3600);
        await govBridge.setEpochMinDuration(minDuration);
        expect(await govBridge.epochMinDuration()).to.equal(minDuration);
    });

    it('should revert change epochMinDuration', async function () {
        const minDuration = BigInt(3600);
        const message = `AccessControl: account ${notAdmin.address.toLowerCase()} is missing role ${await govBridge.DEFAULT_ADMIN_ROLE()}`;
        await expect(govBridge.connect(notAdmin).setEpochMinDuration(minDuration)).to.be.revertedWith(message);
    });

    it('should change epochMinRequestUpdateDuration', async function () {
        const minRequestDuration = BigInt(7200);
        await govBridge.setEpochMinRequestUpdateDuration(minRequestDuration);
        expect(await govBridge.epochMinRequestUpdateDuration()).to.equal(minRequestDuration);
    });

    it('should revert change epochMinRequestUpdateDuration', async function () {
        const minRequestDuration = BigInt(7200);
        const message = `AccessControl: account ${notAdmin.address.toLowerCase()} is missing role ${await govBridge.DEFAULT_ADMIN_ROLE()}`;
        await expect(govBridge.connect(notAdmin).setEpochMinRequestUpdateDuration(minRequestDuration)).to.be.revertedWith(message);
    });

    it('should revert NodeRegistry change', async function () {
        const message = `AccessControl: account ${notAdmin.address.toLowerCase()} is missing role ${await govBridge.DEFAULT_ADMIN_ROLE()}`;
        await expect(govBridge.connect(notAdmin).setNodeRegistry(notAdmin.address)).to.be.revertedWith(message);
    });

    it('should revert update epoch', async function () {
        await expect(govBridge.requestEpochUpdate()).to.be.revertedWith('GovBridge: not enough time after retry');
    });
});
