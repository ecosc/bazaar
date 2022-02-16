// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

interface IProfile {
    function registered(address account) external view returns (bool);
}