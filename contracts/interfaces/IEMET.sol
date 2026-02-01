// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

/// @title IEMET - Interface for the EMET ERC-20 token
/// @notice Minimal interface for interacting with the existing EMET token on Base
interface IEMET {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}
