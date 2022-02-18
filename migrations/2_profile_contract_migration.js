const ProfileContract = artifacts.require("Profile");

const ECU_TOKEN_ADDRESS = '0xB7eb742aa5ddc7f08e5bB94E238D738126239F93';

module.exports = function (deployer) {
  deployer.deploy(ProfileContract, ECU_TOKEN_ADDRESS);
};
