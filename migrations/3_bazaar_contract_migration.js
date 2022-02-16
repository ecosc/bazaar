const BazaarContract = artifacts.require("Bazaar");
const ProfileContract = artifacts.require("Profile");

module.exports = async function (deployer) {
  let profile = await ProfileContract.deployed();

  await deployer.deploy(BazaarContract, profile.address);
};
