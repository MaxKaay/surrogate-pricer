// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// NOTE or WRITER of one series: a plain ERC-20 (no hooks, no rebasing, no
/// fees), decimals = the collateral's (USDG: 6). Only its series can mint or burn.
interface ISeriesToken is IERC20Metadata {
    error OnlySeries();

    function series() external view returns (address);
    function isNote() external view returns (bool); // false = WRITER

    function mint(address to, uint256 amount) external; // only series
    function burn(address from, uint256 amount) external; // only series; the series burns its own caller's tokens
}
