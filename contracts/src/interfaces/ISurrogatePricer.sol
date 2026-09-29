// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// Raw feature vector, featureSpecVersion 1. Field order = model input order.
/// Ranges: docs/model-export-format.md. Out of range reverts, never clamps.
struct PricerInputs {
    uint16 spotBpsOfInitial; // spot / initialFixing * 10_000
    int32 distToKnockInBps; // (spot - knockInLevel) / initialFixing * 10_000, signed
    uint16 volBpsAnnual; // implied vol, a Desk quoting parameter (no oracle)
    uint16 kiBarrierBps; // knock-in barrier, bps of initial fixing
    uint16 acBarrierBps; // autocall barrier, bps of initial fixing
    uint16 couponBpsPerPeriod; // accrued per observation, bps of notional
    uint32 timeToMaturitySecs;
    uint32 timeToNextObsSecs;
    uint8 observationsRemaining;
    uint8 flags; // bit0: knocked in
}

/// L0: the Stylus student model (stylus/pricer-model). Pure: no storage, no
/// external calls, no block.timestamp. Weights compiled in, pinned by hash.
interface ISurrogatePricer {
    error OutOfRange(uint8 field, int64 value);

    /// Fair value of 1 NOTE in bps of its 1-USDG notional.
    function priceBps(PricerInputs calldata inputs) external view returns (uint16 priceBpsOfNotional);

    /// keccak256 of the canonical student_export.json (recomputed at build).
    function weightsHash() external view returns (bytes32);

    function featureSpecVersion() external view returns (uint16);
}
