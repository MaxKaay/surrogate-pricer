// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// Chainlink AggregatorV3 plus `latestRound()`. Robinhood Chain stock feeds:
/// 8 decimals, 24/5, roundId = 2^64 + n, full `getRoundData` history.
/// Pauses show up only as staleness (`oraclePaused()` does not exist on-chain).
interface IAggregatorV3 {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function latestRound() external view returns (uint256);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
    function getRoundData(uint80 roundId)
        external
        view
        returns (uint80, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
