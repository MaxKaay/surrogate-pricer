// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IFixingsRecorder} from "./IFixingsRecorder.sol";

/// Everything that defines a series' payout. seriesId = keccak256(abi.encode(terms)).
/// Implied vol is NOT a term: it changes price, never payout, so it lives in
/// the Desk and identical notes stay one fungible series.
struct SeriesTerms {
    address feed; // underlying: AggregatorV3 feed, 8 decimals
    uint40 strikeTime; // observation time of the initial fixing (a market close)
    uint32 observationInterval; // seconds between observations; >= 1 hour (Desk grid: 604800)
    uint8 observationCount; // observations after strike, 1..104; the last one is maturity
    uint16 kiBarrierBps; // knock-in barrier, bps of initial fixing; 0 < ki <= ac
    uint16 acBarrierBps; // autocall barrier, bps of initial fixing; <= 20_000
    uint16 couponBpsPerPeriod; // accrued per elapsed observation, bps of notional; <= 10_000
}

enum Phase {
    Pending, // strike fixing not processed yet: no mint
    Live, // struck; mint, redeemPair
    Settled // payout fixed forever: redeem, redeemPair
}

/// Up-to-date state. `state()` includes fixings that are recorded but not yet
/// processed by `advance()`, so views never lag the recorder.
struct SeriesState {
    Phase phase;
    uint96 initialFixing; // feed decimals; 0 while Pending
    uint8 observationsDone; // processed observations, excluding the strike
    bool knockedIn; // latching; discrete monitoring at fixings only
    bool autocalled;
    uint40 nextObservation; // 0 once Settled
    uint40 maturity; // strikeTime + observationCount * observationInterval
    uint128 payoutPerNote; // USDG base units per 1 NOTE (1e6 base units); 0 until Settled
}

/// L1 core. One series = one USDG escrow + two ERC-20s (NOTE, WRITER).
/// No model, no admin, no pause, no upgrade. Every state-changing entry point
/// first processes all recorded fixings (same as calling advance()).
///
/// Payout per NOTE, in units of its 1-USDG notional (normative; the Monte
/// Carlo teacher implements the same rules):
///   observations i = 1..N at strikeTime + i * interval; c = coupon per period
///   knock-in:  any fixing_i < ki * initial  (latching)
///   autocall:  first i with fixing_i >= ac * initial  ->  1 + c * i, settle at i
///   maturity:  knocked in and fixing_N < initial  ->  fixing_N / initial + c * N
///              otherwise                          ->  1 + c * N
///   maxPayout = 1 + c * N;  WRITER gets maxPayout - NOTE payout
/// Fallback: an observation still unrecorded MAX_ROLL + FALLBACK_GRACE after
/// obsTime reuses the previous fixing (the strike fixing for i = 1).
interface INoteSeries {
    event Struck(uint96 initialFixing);
    event ObservationProcessed(
        uint8 indexed index, uint40 obsTime, uint96 fixing, bool knockedIn, bool autocalled, bool fallbackUsed
    );
    event Settled(uint8 atObservation, bool autocalled, bool knockedIn, uint128 payoutPerNote, uint128 payoutPerWriter);
    event Minted(address indexed caller, address indexed to, uint256 amount, uint256 collateralIn);
    event PairRedeemed(address indexed caller, address indexed to, uint256 amount, uint256 collateralOut);
    event Redeemed(
        address indexed caller, address indexed to, uint256 noteAmount, uint256 writerAmount, uint256 collateralOut
    );

    error NotStruck();
    error AlreadySettled();
    error NotSettled();
    error ZeroAmount();

    // --- identity -------------------------------------------------------------
    function factory() external view returns (address);
    function id() external view returns (bytes32);
    function terms() external view returns (SeriesTerms memory);
    function note() external view returns (address);
    function writer() external view returns (address);
    function recorder() external view returns (IFixingsRecorder);
    function collateral() external view returns (address); // USDG

    // --- economics ------------------------------------------------------------
    /// USDG base units locked per 1 NOTE + 1 WRITER (= 1e6 * (1 + c * N)).
    function maxPayoutPerNote() external view returns (uint128);
    function FALLBACK_GRACE() external view returns (uint40);

    // --- state ----------------------------------------------------------------
    function state() external view returns (SeriesState memory);

    /// An observation time has passed but its fixing isn't recorded yet. While
    /// true the note's state is unknown, and quoters must refuse to price.
    function pendingObservation() external view returns (bool pending, uint40 obsTime);

    /// Permissionless: processes the strike and every recorded observation in
    /// order; settles on autocall, maturity or fallback. Moves no tokens.
    function advance() external returns (SeriesState memory);

    // --- positions (collateral is pulled with transferFrom: approve the series) ---
    /// Lock ceil(amount * maxPayoutPerNote / 1e6) USDG; mint `amount` NOTE and WRITER to `to`.
    function mint(uint256 amount, address to) external returns (uint256 collateralIn);

    /// Burn `amount` NOTE and WRITER from the caller; pay floor(amount * maxPayoutPerNote / 1e6).
    /// Allowed in any phase after strike.
    function redeemPair(uint256 amount, address to) external returns (uint256 collateralOut);

    /// Settled only. Burns from the caller; NOTE pays floor(noteAmount * payoutPerNote / 1e6),
    /// WRITER pays floor(writerAmount * (maxPayoutPerNote - payoutPerNote) / 1e6).
    function redeem(uint256 noteAmount, uint256 writerAmount, address to) external returns (uint256 collateralOut);

    function previewMint(uint256 amount) external view returns (uint256 collateralIn);
    function previewRedeemPair(uint256 amount) external view returns (uint256 collateralOut);
    function previewRedeem(uint256 noteAmount, uint256 writerAmount) external view returns (uint256 collateralOut);
}
