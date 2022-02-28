// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface INexusVault {
    function getTokensOf(address staker)
        external
        view
        returns (uint256[] memory);

    function getTokenRewards(uint256 tokenId) external view returns (uint256);
}
