// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import './libraries/Ownable.sol';

contract Profile is Ownable {
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

    
    uint256 public numAccounts;
    mapping(address => UserProfile) public accounts;

    function createAccount(string memory _name, string memory _contact)
        public
        returns (uint256)
    {
        UserProfile storage profile = accounts[msg.sender];

        require(
            profile.state == UserState.Unknown,
            "PROFILE: USER_EXISTS"
        );

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

    function registered(address account) public view returns (bool) {
        return accounts[account].state == UserState.Active;
    }
}
