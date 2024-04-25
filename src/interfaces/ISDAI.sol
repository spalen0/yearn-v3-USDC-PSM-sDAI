// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

interface ISDAI {
    function deposit(uint256 assets, address receiver) external;
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    function convertToAssets(uint256 shares) external view returns (uint256);
}
