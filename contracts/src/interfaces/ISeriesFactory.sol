// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SeriesTerms} from "./INoteSeries.sol";

/// L1 core entry point. Permissionless, deterministic, no admin.
/// Series, NOTE and WRITER are EIP-1167 clones at CREATE2 addresses derived
/// from seriesId, so identical terms always map to the same series and anyone
/// can compute the addresses off-chain. One FixingsRecorder per feed, also at
/// a CREATE2 address, so a series can't be pointed at a fake recorder.
interface ISeriesFactory {
    event RecorderDeployed(address indexed feed, address recorder);
    event SeriesCreated(
        bytes32 indexed seriesId, address indexed feed, address series, address note, address writer, SeriesTerms terms
    );

    error BadSchedule(); // interval < 1 h, count not in 1..104, or strikeTime == 0
    error BadBarriers(); // not 0 < ki <= ac <= 20_000
    error BadCoupon(); // coupon > 10_000
    error BadFeed(); // feed decimals != 8

    function collateral() external view returns (address); // USDG, immutable

    function seriesId(SeriesTerms calldata terms) external pure returns (bytes32);
    function predictSeries(SeriesTerms calldata terms)
        external
        view
        returns (address series, address note, address writer);
    function seriesOf(bytes32 seriesId) external view returns (address); // 0 if not created
    function isSeries(address series) external view returns (bool); // provenance check
    function allSeries() external view returns (address[] memory);

    function recorderOf(address feed) external view returns (address); // deterministic, may be undeployed
    function deployRecorder(address feed) external returns (address recorder); // idempotent

    /// Idempotent: returns the existing series for identical terms. Deploys
    /// the feed's recorder if needed.
    function createSeries(SeriesTerms calldata terms) external returns (address series);
}
