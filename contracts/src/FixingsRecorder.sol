// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IAggregatorV3Rounds {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
    function getRoundData(uint80 roundId)
        external
        view
        returns (uint80, int256, uint256, uint256, uint80);
    function latestRound() external view returns (uint256);
    function decimals() external view returns (uint8);
}

/// FixingsRecorder — one instance per underlying (per feed). Permissionless,
/// trustless: anyone can record, and every recorded fixing is verified against
/// feed rounds on-chain. Design: DESIGN.md, Decision 1.
///
/// Fixing rule for a scheduled observation time `obsTime`:
///   Case A (normal):  last round with updatedAt <= obsTime, age <= 96h.
///   Case B (rolled):  first round with updatedAt > obsTime, when the previous
///                     round proves a >96h gap (disrupted day).
contract FixingsRecorder {
    uint40 public constant MAX_FIX_AGE = 96 hours; // holiday-weekend coverage
    uint40 public constant MAX_ROLL = 8 days;      // beyond: settle at last good fix (vault logic)
    int256 public constant PRICE_MAX = 1e13;       // $100k @ 8dec — kills early-round scale anomaly

    struct Fixing {
        uint40 timestamp; // actual feed updatedAt, not obsTime
        uint96 price;     // feed decimals
        uint80 roundId;   // audit trail (also emitted)
    }

    IAggregatorV3Rounds public immutable feed;

    mapping(uint40 obsTime => Fixing) public fixings;

    event FixingRecorded(uint40 indexed obsTime, uint80 roundId, uint96 price, uint40 timestamp);

    error AlreadyRecorded(uint40 obsTime);
    error FutureObservation(uint40 obsTime);
    error BadPrice(int256 answer);
    error NotLastRoundBefore(uint80 roundId, uint40 obsTime);
    error FixingTooStale(uint40 updatedAt, uint40 obsTime);
    error NoGapProof(uint80 roundId, uint40 obsTime);
    error RollTooLong(uint40 updatedAt, uint40 obsTime);

    constructor(address feed_) {
        feed = IAggregatorV3Rounds(feed_);
    }

    function recordFixing(uint40 obsTime, uint80 roundId) external {
        if (obsTime > block.timestamp) revert FutureObservation(obsTime);
        if (fixings[obsTime].timestamp != 0) revert AlreadyRecorded(obsTime);

        (, int256 answer,, uint40 updatedAt,) = _round(roundId);
        if (answer <= 0 || answer > PRICE_MAX) revert BadPrice(answer);

        if (updatedAt <= obsTime) {
            // Case A: must be the LAST round at-or-before obsTime, and fresh enough.
            if (obsTime - updatedAt > MAX_FIX_AGE) revert FixingTooStale(updatedAt, obsTime);
            try feed.getRoundData(roundId + 1) returns (uint80, int256, uint256, uint256 nextUpdatedAt, uint80) {
                if (nextUpdatedAt <= obsTime) revert NotLastRoundBefore(roundId, obsTime);
            } catch {
                // no next round: only acceptable if this IS the latest round
                if (roundId != feed.latestRound()) revert NotLastRoundBefore(roundId, obsTime);
            }
        } else {
            // Case B: rolled observation. Must be the FIRST round after obsTime,
            // with a proven >96h gap before it, within the 8-day hard cap.
            if (updatedAt - obsTime > MAX_ROLL) revert RollTooLong(updatedAt, obsTime);
            try feed.getRoundData(roundId - 1) returns (uint80, int256, uint256, uint256 prevUpdatedAt, uint80) {
                if (prevUpdatedAt > obsTime) revert NoGapProof(roundId, obsTime); // roundId-1 also after obsTime
                if (obsTime - prevUpdatedAt <= MAX_FIX_AGE) revert NoGapProof(roundId, obsTime); // no disruption
            } catch {
                // roundId-1 doesn't exist: genesis round, gap proof trivially satisfied
            }
        }

        fixings[obsTime] = Fixing({timestamp: updatedAt, price: uint96(uint256(answer)), roundId: roundId});
        emit FixingRecorded(obsTime, roundId, uint96(uint256(answer)), updatedAt);
    }

    function fixingOf(uint40 obsTime) external view returns (Fixing memory) {
        return fixings[obsTime];
    }

    function isRecorded(uint40 obsTime) external view returns (bool) {
        return fixings[obsTime].timestamp != 0;
    }

    function _round(uint80 roundId)
        internal
        view
        returns (uint80 id, int256 answer, uint256 startedAt, uint40 updatedAt, uint80 answeredInRound)
    {
        uint256 u;
        (id, answer, startedAt, u, answeredInRound) = feed.getRoundData(roundId);
        updatedAt = uint40(u);
    }
}
