const ProfileContract = artifacts.require("Profile");

const ECU_TOKEN_ADDRESS = '0xdc49f7e090206f25563d0a8a8190388e92148a1d';

module.exports = function (deployer) {
  deployer.deploy(ProfileContract, ECU_TOKEN_ADDRESS);
};
