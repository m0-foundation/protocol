const { time } = require('@nomicfoundation/hardhat-toolbox/network-helpers');
// const { anyValue } = require('@nomicfoundation/hardhat-chai-matchers/withArgs');
const { expect } = require('chai');
const { default: randSeed } = require('rand-seed');

describe('MToken', () => {
  let mToken;
  let rateModel;
  let registrar;

  let deployer;

  let protocol;
  let alice;
  let bob;
  let charlie;
  let dave;
  let elise;

  const accounts = [];

  const EARNERS_LIST_IGNORED_KEY = ethers.encodeBytes32String('earners_list_ignored');
  const EARNERS_RATE_MODEL_KEY = ethers.encodeBytes32String('earner_rate_model');

  const getRandomIntGenerator = (seed) => {
    const rand = new randSeed(seed);

    return (min, max) => min + Math.floor(rand.next() * (max - min));
  };

  beforeEach(async () => {
    [deployer, protocol, alice, bob, charlie, dave, elise] = await ethers.getSigners();

    accounts.push(alice);
    accounts.push(bob);
    accounts.push(charlie);
    accounts.push(dave);
    accounts.push(elise);

    rateModel = await ethers.deployContract('MockRateModel');
    registrar = await ethers.deployContract('MockSPOGRegistrar');
    mToken = await ethers.deployContract('MToken', [await registrar.getAddress(), protocol.address]);

    await registrar['updateConfig(bytes32, address)'](EARNERS_RATE_MODEL_KEY, await rateModel.getAddress());
    await rateModel.setRate(1_000);
    await mToken.updateIndex();
  });

  it.skip('tests minting to non-earners', async () => {
    await time.increase(31_536_000); // 1 year

    await mToken.connect(protocol).mint(alice.address, 100);
    await mToken.connect(protocol).mint(bob.address, 200);
    await mToken.connect(protocol).mint(charlie.address, 400);
    await mToken.connect(protocol).mint(dave.address, 800);
    await mToken.connect(protocol).mint(elise.address, 1600);

    expect(await mToken.balanceOf(alice.address)).to.equal(100);
    expect(await mToken.balanceOf(bob.address)).to.equal(200);
    expect(await mToken.balanceOf(charlie.address)).to.equal(400);
    expect(await mToken.balanceOf(dave.address)).to.equal(800);
    expect(await mToken.balanceOf(elise.address)).to.equal(1600);
  });

  it.skip('tests minting to earners', async () => {
    expect(await mToken.earnerRate()).to.equal(1_000);

    await registrar['updateConfig(bytes32, uint256)'](EARNERS_LIST_IGNORED_KEY, 1);

    await mToken['startEarning(address)'](alice.address);
    await mToken['startEarning(address)'](bob.address);
    await mToken['startEarning(address)'](charlie.address);
    await mToken['startEarning(address)'](dave.address);
    await mToken['startEarning(address)'](elise.address);

    await time.increase(31_536_000); // 1 year

    await mToken.connect(protocol).mint(alice.address, 100);
    await mToken.connect(protocol).mint(bob.address, 200);
    await mToken.connect(protocol).mint(charlie.address, 400);
    await mToken.connect(protocol).mint(dave.address, 800);
    await mToken.connect(protocol).mint(elise.address, 1600);

    expect(await mToken.balanceOf(alice.address)).to.equal(99);
    expect(await mToken.balanceOf(bob.address)).to.equal(198);
    expect(await mToken.balanceOf(charlie.address)).to.equal(398);
    expect(await mToken.balanceOf(dave.address)).to.equal(799);
    expect(await mToken.balanceOf(elise.address)).to.equal(1599);
  });

  it('tests random minting/transferring', async () => {
    const getRandomInt = getRandomIntGenerator('1234');

    await registrar['updateConfig(bytes32, uint256)'](EARNERS_LIST_IGNORED_KEY, 1);

    for (let i = 0; i < 4_000; i++) {
      await time.increase(getRandomInt(0, 86_400)); // jump up to a day

      const randomNumber1 = getRandomInt(0, 10);
      const randomNumber2 = getRandomInt(0, accounts.length);

      const account = accounts[randomNumber2];

      const isEarning = await mToken.isEarning(account.address);

      if (!isEarning && randomNumber1 <= 1) {
        await mToken.connect(account)['startEarning()']();
        continue;
      }

      if (isEarning && randomNumber1 <= 2) {
        await mToken.connect(account)['stopEarning()']();
        continue;
      }

      const hasOptedOutOfEarning = await mToken.hasOptedOutOfEarning(account.address);

      if (!hasOptedOutOfEarning && randomNumber1 <= 4) {
        await mToken.connect(account).optOutOfEarning();
        continue;
      }

      const currentBalance = Number(await mToken.balanceOf(account.address));

      if (randomNumber1 <= 4 || currentBalance == 0) {
        await mToken.connect(protocol).mint(account.address, getRandomInt(5_000, 100_000));
        continue;
      }

      const randomNumber3 = 1 + getRandomInt(0, accounts.length - 1);

      const recipient = accounts[(randomNumber2 + randomNumber3) % accounts.length];

      const randomNumber4 = getRandomInt(2_000, 7_000);

      // Never transfer all
      const amount = Math.floor((randomNumber4 * currentBalance) / 10_000);

      await mToken.connect(account).transfer(recipient.address, amount >= currentBalance ? currentBalance : amount);
    }
  });
});
