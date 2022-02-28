// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface INexus is IERC20 {
    function isInBlacklist(address account) external view returns (bool);

    function burn(address from, uint256 amount) external;
}
