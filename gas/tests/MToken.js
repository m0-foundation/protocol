const { time } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
// const { anyValue } = require('@nomicfoundation/hardhat-chai-matchers/withArgs');
const { expect } = require("chai");
const { default: randSeed } = require("rand-seed");

describe("MToken", () => {
  let mToken;
  let registrar;

  let deployer;

  let portal;
  let alice;
  let bob;
  let charlie;
  let dave;
  let elise;

  const accounts = [];

  const EARNERS_LIST_IGNORED_KEY = ethers.encodeBytes32String(
    "earners_list_ignored",
  );

  const getRandomIntGenerator = (seed) => {
    const rand = new randSeed(seed);

    return (min, max) => min + Math.floor(rand.next() * (max - min));
  };

  beforeEach(async () => {
    [deployer, portal, alice, bob, charlie, dave, elise] =
      await ethers.getSigners();

    accounts.push(alice);
    accounts.push(bob);
    accounts.push(charlie);
    accounts.push(dave);
    accounts.push(elise);

    registrar = await ethers.deployContract("MockRegistrar");

    await registrar["setPortal(address)"](
      await portal.getAddress(),
    );

    mToken = await ethers.deployContract("MToken", [
      await registrar.getAddress(),
    ]);
  });

  it("tests minting to non-earners", async () => {
    // TODO: fix

    await mToken.connect(minterGateway).mint(alice.address, 100);
    await mToken.connect(minterGateway).mint(bob.address, 200);
    await mToken.connect(minterGateway).mint(charlie.address, 400);
    await mToken.connect(minterGateway).mint(dave.address, 800);
    await mToken.connect(minterGateway).mint(elise.address, 1600);

    expect(await mToken.balanceOf(alice.address)).to.equal(100);
    expect(await mToken.balanceOf(bob.address)).to.equal(200);
    expect(await mToken.balanceOf(charlie.address)).to.equal(400);
    expect(await mToken.balanceOf(dave.address)).to.equal(800);
    expect(await mToken.balanceOf(elise.address)).to.equal(1600);
  });

  it("tests minting to earners", async () => {
    await registrar["updateConfig(bytes32, uint256)"](
      EARNERS_LIST_IGNORED_KEY,
      1,
    );

    await accounts.forEach(async (account) => {
      await mToken.connect(account).startEarning();
    });

    // TODO: fix

    await mToken.connect(minterGateway).mint(alice.address, 100);
    await mToken.connect(minterGateway).mint(bob.address, 200);
    await mToken.connect(minterGateway).mint(charlie.address, 400);
    await mToken.connect(minterGateway).mint(dave.address, 800);
    await mToken.connect(minterGateway).mint(elise.address, 1600);

    expect(await mToken.balanceOf(alice.address)).to.equal(99);
    expect(await mToken.balanceOf(bob.address)).to.equal(198);
    expect(await mToken.balanceOf(charlie.address)).to.equal(398);
    expect(await mToken.balanceOf(dave.address)).to.equal(799);
    expect(await mToken.balanceOf(elise.address)).to.equal(1599);
  });

  it("tests random minting/transferring", async () => {
    const getRandomInt = getRandomIntGenerator("1234");

    await registrar["updateConfig(bytes32, uint256)"](
      EARNERS_LIST_IGNORED_KEY,
      1,
    );

    for (let i = 0; i < 4_000; i++) {
      // TODO: fix

      const randomNumber2 = getRandomInt(0, 10);
      const randomNumber3 = getRandomInt(0, accounts.length);

      const account = accounts[randomNumber3];

      const isEarning = await mToken.isEarning(account.address);

      if (!isEarning && randomNumber2 <= 1) {
        await mToken.connect(account).startEarning();
        continue;
      }

      if (isEarning && randomNumber2 <= 2) {
        await mToken.connect(account).stopEarning();
        continue;
      }

      const currentBalance = Number(await mToken.balanceOf(account.address));

      if (randomNumber2 <= 4 || currentBalance == 0) {
        await mToken
          .connect(minterGateway)
          .mint(account.address, getRandomInt(5_000, 100_000));
        continue;
      }

      const randomNumber4 = 1 + getRandomInt(0, accounts.length - 1);

      const recipient =
        accounts[(randomNumber3 + randomNumber4) % accounts.length];

      const randomNumber5 = getRandomInt(2_000, 7_000);

      // Never transfer all
      const amount = Math.floor((randomNumber5 * currentBalance) / 10_000);

      await mToken
        .connect(account)
        .transfer(
          recipient.address,
          amount >= currentBalance ? currentBalance : amount,
        );
    }
  });
});
