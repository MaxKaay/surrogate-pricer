// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// MockChainlinkFeed — testnet stand-in for the Robinhood stock-token feeds.
/// Faithful to the REAL feed interface as probed on mainnet 2026-09-29:
/// latestRoundData / getRoundData / latestRound / decimals / description,
/// roundId = 2^64 + n. Deliberately NO oraclePaused() — the real feed doesn't
/// have one (see DESIGN.md verified facts).
/// The 24/5 freeze is NOT simulated in-contract: it emerges from not pushing.
/// pushRoundAt exists so demo scripts can stage backdated rounds / gaps.
contract MockChainlinkFeed {
    uint80 public constant PHASE_OFFSET = uint80(1) << 64; // roundId = 2^64 + n

    struct Round {
        int256 answer;   // 8 decimals
        uint40 updatedAt;
    }

    address public owner;
    Round[] public rounds; // rounds[i] is round n = i+1
    string public description;

    error NotOwner();
    error NoRounds();
    error UnknownRound(uint80 roundId);
    error NonMonotonic(uint40 updatedAt, uint40 last);

    constructor(string memory description_) {
        owner = msg.sender;
        description = description_;
    }

    function pushRound(int256 answer) external {
        _push(answer, uint40(block.timestamp));
    }

    /// Demo/staging only: backdated round to stage weekends and halts.
    function pushRoundAt(int256 answer, uint40 updatedAt) external {
        _push(answer, updatedAt);
    }

    function _push(int256 answer, uint40 updatedAt) internal {
        if (msg.sender != owner) revert NotOwner();
        uint256 n = rounds.length;
        if (n > 0 && updatedAt <= rounds[n - 1].updatedAt) revert NonMonotonic(updatedAt, rounds[n - 1].updatedAt);
        rounds.push(Round({answer: answer, updatedAt: updatedAt}));
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function latestRound() external view returns (uint256) {
        if (rounds.length == 0) revert NoRounds();
        return uint256(PHASE_OFFSET) + rounds.length;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return getRoundData(uint80(uint256(PHASE_OFFSET) + rounds.length));
    }

    function getRoundData(uint80 roundId)
        public
        view
        returns (uint80, int256 answer, uint256 startedAt, uint256 updatedAt, uint80)
    {
        uint256 n = uint256(roundId) - uint256(PHASE_OFFSET);
        if (n == 0 || n > rounds.length) revert UnknownRound(roundId);
        Round storage r = rounds[n - 1];
        return (roundId, r.answer, r.updatedAt, r.updatedAt, roundId);
    }
}
