// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAggregatorV3} from "./IAggregatorV3.sol";

/// L0: one recorder per feed. Permissionless and trustless: anyone records the
/// fixing for an observation time by naming a feed round, and the recorder
/// proves on-chain that it is the right one (DESIGN.md, Decision 1):
///   Case A: the last round with updatedAt <= obsTime, at most MAX_FIX_AGE old.
///   Case B: disrupted day. The first round after obsTime, when the previous
///           round proves a gap > MAX_FIX_AGE, at most MAX_ROLL late.
/// Finding the round is off-chain work (binary search over getRoundData).
interface IFixingsRecorder {
    struct Fixing {
        uint40 timestamp; // the feed round's updatedAt, not obsTime; 0 = not recorded
        uint96 price; // feed decimals (8)
        uint80 roundId;
    }

    event FixingRecorded(uint40 indexed obsTime, uint80 roundId, uint96 price, uint40 timestamp);

    error AlreadyRecorded(uint40 obsTime);
    error FutureObservation(uint40 obsTime);
    error BadPrice(int256 answer);
    error NotLastRoundBefore(uint80 roundId, uint40 obsTime);
    error FixingTooStale(uint40 updatedAt, uint40 obsTime);
    error NoGapProof(uint80 roundId, uint40 obsTime);
    error RollTooLong(uint40 updatedAt, uint40 obsTime);

    function feed() external view returns (IAggregatorV3);
    function MAX_FIX_AGE() external view returns (uint40);
    function MAX_ROLL() external view returns (uint40);

    function recordFixing(uint40 obsTime, uint80 roundId) external;
    function fixingOf(uint40 obsTime) external view returns (Fixing memory);
    function isRecorded(uint40 obsTime) external view returns (bool);
}
