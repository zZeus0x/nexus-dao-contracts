// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

interface INexusEcosystem is IERC721Enumerable {
    function getTokenEmissionRate(uint256 tokenId)
        external
        view
        returns (uint256);

    function getTierPrice(uint256 tier) external view returns (uint256);

    function mint(
        address to,
        uint256 tier,
        string calldata name
    ) external;
}
