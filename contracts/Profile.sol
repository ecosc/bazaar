// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./libraries/Ownable.sol";
import "./libraries/TransferHelper.sol";

contract Profile is Ownable {
    event ProfileCreated(address indexed owner);

    enum UserState {
        Unknown,
        Active,
        Inactive
    }

    struct UserProfile {
        string name;
        string contact;
        UserState state;
    }

    address public feeTo;
    address public feeToSetter;

    uint256 public fee;
    address feeTokenAddress;
    uint256 public numAccounts;
    mapping(address => UserProfile) public accounts;

    constructor(address _feeTokenAddress) {
        feeTokenAddress = _feeTokenAddress;
        feeToSetter = msg.sender;
        feeTo = msg.sender;
        fee = 50 * 10**18;
    }

    /**
     * @dev set fee to account
     */
    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, "PROFILE: FORBIDDEN");
        feeTo = _feeTo;
    }

    /**
     * @dev set fee to setter account
     */
    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, "PROFILE: FORBIDDEN");
        feeToSetter = _feeToSetter;
    }

    /**
     * @dev set fee token address
     */
    function setFeeTokenAddress(address token) external onlyOwner {
        feeTokenAddress = token;
    }

    /**
     * @dev set create profile fee
     */
    function setFee(uint256 _fee) external onlyOwner {
        fee = _fee;
    }

    function createAccount(string memory _name, string memory _contact)
        public
        returns (uint256)
    {
        UserProfile storage profile = accounts[msg.sender];

        require(profile.state == UserState.Unknown, "PROFILE: USER_EXISTS");

        if (feeTo != address(0)) {
            TransferHelper.safeTransferFrom(
                feeTokenAddress,
                msg.sender,
                feeTo,
                fee
            );
        }

        numAccounts++;
        profile.name = _name;
        profile.contact = _contact;
        profile.state = UserState.Active;

        return numAccounts;
    }

    function updateAccount(string memory _name, string memory _contact) public {
        require(
            accounts[msg.sender].state == UserState.Active,
            "PROFILE: USER_NOT_EXISTS"
        );

        accounts[msg.sender].name = _name;
        accounts[msg.sender].contact = _contact;
    }

    function disableAccount(address account) public onlyOwner {
        accounts[account].state = UserState.Inactive;
    }

    function enableAccount(address account) public onlyOwner {
        accounts[account].state = UserState.Active;
    }

    function registered(address account) public view returns (bool) {
        return accounts[account].state == UserState.Active;
    }
}
