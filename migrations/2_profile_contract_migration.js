const ProfileContract = artifacts.require("Profile");

module.exports = function (deployer) {
  deployer.deploy(ProfileContract);
};
