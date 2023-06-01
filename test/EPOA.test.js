const { ethers } = require('hardhat');
require('ethers');
const { expect } = require('chai');

describe('NodeRegistry local test', () => {

    let owner, mallory;
    let nodeRegistry;
    let EYWA;

    before(async () => {
        [owner, mallory] = await ethers.getSigners();
        const NodeRegistry = await ethers.getContractFactory('NodeRegistryV2');
        nodeRegistry = await NodeRegistry.deploy();
        await nodeRegistry.deployed();
        const tokenFactory = await ethers.getContractFactory('EPOA');
        EYWA = await tokenFactory.deploy(nodeRegistry.address);
        await EYWA.deployed();
    });

    it('should mint tokens', async function () {
        const oldBalance = await EYWA.balanceOf(owner.address);
        const amount = ethers.utils.parseEther(Math.floor(Math.random() * 100) + '.0');
        await EYWA.mint(owner.address, amount);
        const newBalance = await EYWA.balanceOf(owner.address);
        expect(newBalance).to.be.above(oldBalance);
    });

    it('should revert mint if caller is not an owner', async function () {
        await expect(EYWA.connect(mallory).mint(owner.address, 1000)).to.be.revertedWith('Ownable: caller is not the owner');
    });

    it('should mint with allowance tokens', async function () {
        const oldBalance = await EYWA.balanceOf(owner.address);
        const amount = ethers.utils.parseEther(Math.floor(Math.random() * 100) + '.0');
        await EYWA.mintWithAllowance(owner.address, mallory.address, amount);
        const newBalance = await EYWA.balanceOf(owner.address);
        expect(newBalance).to.be.above(oldBalance);
    });

    it('should revert mint with allowance if caller is not an owner', async function () {
        await expect(EYWA.connect(mallory).mintWithAllowance(owner.address, mallory.address, 1000)).to.be.revertedWith('Ownable: caller is not the owner');
    });

    it('should brun tokens', async function () {
        const oldBalance = await EYWA.balanceOf(owner.address);
        const amount = ethers.utils.parseEther('0.' + Math.floor(Math.random() * 100));
        await EYWA.burn(amount);
        const newBalance = await EYWA.balanceOf(owner.address);
        expect(oldBalance).to.be.above(newBalance);
    });

    it('should burn with allowance decrease tokens', async function () {
        const oldBalance = await EYWA.balanceOf(owner.address);
        const amount = ethers.utils.parseEther('0.' + Math.floor(Math.random() * 100));
        await EYWA.burnWithAllowanceDecrease(owner.address, mallory.address, amount);
        const newBalance = await EYWA.balanceOf(owner.address);
        expect(oldBalance).to.be.above(newBalance);
    });

    it('should revert burn with allowance decrease tokens', async function () {
        const amount = ethers.utils.parseEther('0.' + Math.floor(Math.random() * 100));
        await EYWA.approve(mallory.address, 0);
        await expect(EYWA.burnWithAllowanceDecrease(owner.address, mallory.address, amount)).to.be.revertedWith('EPOA: decreased allowance below zero');
    });

    it('should revert mint with allowance if caller is not an owner', async function () {
        await expect(EYWA.connect(mallory).burnWithAllowanceDecrease(owner.address, mallory.address, 1000)).to.be.revertedWith('Ownable: caller is not the owner');
    });

    it('should transfer tokens to NodeRegistry', async function () {
        const oldBalance = await EYWA.balanceOf(nodeRegistry.address);
        const amount = ethers.utils.parseEther(Math.floor(Math.random() * 100) + '.0');
        await EYWA.mintWithAllowance(owner.address, nodeRegistry.address, amount);
        await EYWA.transfer(nodeRegistry.address, amount);
        const newBalance = await EYWA.balanceOf(nodeRegistry.address);
        expect(newBalance).to.be.above(oldBalance);
    });

    it('should revert if transfer not to NodeRegistry', async function () {
        await expect(EYWA.transfer(mallory.address, 1000)).to.be.revertedWith('EPOA: transfer only to NodeRegistry');
    });

    it('should transferFrom tokens to NodeRegistry', async function () {
        const oldBalance = await EYWA.balanceOf(nodeRegistry.address);
        const amount = ethers.utils.parseEther(Math.floor(Math.random() * 100) + '.0');
        await EYWA.mint(owner.address, amount);
        await EYWA.approve(mallory.address, amount);
        await EYWA.connect(mallory).transferFrom(owner.address, nodeRegistry.address, amount);
        const newBalance = await EYWA.balanceOf(nodeRegistry.address);
        expect(newBalance).to.be.above(oldBalance);
    });

    it('should revert if transferFrom not to NodeRegistry', async function () {
        await expect(EYWA.transferFrom(owner.address, mallory.address, 1000)).to.be.revertedWith('EPOA: transfer only to NodeRegistry');
    });

    it('should change NodeRegistry address', async function () {
        const newNodeRegistry = '0x0000000000000000000000000000000000000042';
        await EYWA.setNodeRegistry(newNodeRegistry);
        expect(await EYWA.nodeRegistry()).to.be.equal(newNodeRegistry);
    });

    it('should not set NodeRegistry address if zero address given', async function () {
        await expect(EYWA.setNodeRegistry(ethers.constants.AddressZero)).to.be.revertedWith('EPOA: zero address given');
    });

    it('should revert change NodeRegistry', async function () {
        await expect(EYWA.connect(mallory).setNodeRegistry('0x0000000000000000000000000000000000000042')).to.be.revertedWith('Ownable: caller is not the owner');
    });
});
