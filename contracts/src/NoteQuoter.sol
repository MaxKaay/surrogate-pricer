// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAggregatorV3} from "./interfaces/IAggregatorV3.sol";
import {ISurrogatePricer, PricerInputs} from "./interfaces/ISurrogatePricer.sol";

/// Legacy terms-based API from the K1 lane (caller passes NoteTerms). The
/// series-based target API is interfaces/INoteQuoter.sol; this contract will
/// be reworked to implement it.
struct NoteTerms {
    uint256 initialFixing;      // USD, feed decimals (8) — recorded at issuance
    uint16 kiBarrierBps;
    uint16 acBarrierBps;
    uint16 couponBpsPerPeriod;
    uint16 volBpsAnnual;        // writer quotes implied vol at issuance (idea doc, finding 5)
    uint32 observationIntervalSecs; // weekly autocall: 604800
    uint40 maturity;
    uint40 nextObservation;
    uint8  observationsRemaining;
    bool   knockedIn;
}

/// NoteQuoter — feature extraction + bounds + fee, the only contract that
/// talks to Robinhood Chain data. The surrogate stays a pure function.
/// Out-of-training-range inputs FAIL CLOSED (revert), never clamped (K3).
contract NoteQuoter {
    error FeedStale(uint40 updatedAt);
    error BadFeedAnswer();
    error OutOfRange(bytes32 field, int256 value);
    error FeeTooHigh();
    error NoteExpired();

    // Published training ranges — must equal featureNormalization in
    // student_export.json. Chosen for TSLA (see docs, range rationale).
    uint16 public constant SPOT_MIN_BPS = 2000;    // 0.2x initial
    uint16 public constant SPOT_MAX_BPS = 30000;   // 3.0x initial
    int32  public constant DIST_MIN_BPS = -8000;   // spot 80% below knock-in barrier
    int32  public constant DIST_MAX_BPS = 20000;   // spot 200% above it
    uint16 public constant VOL_MIN_BPS = 1500;     // 15% annualized
    uint16 public constant VOL_MAX_BPS = 15000;    // 150% annualized
    uint16 public constant KI_MIN_BPS = 4000;
    uint16 public constant KI_MAX_BPS = 9000;
    uint16 public constant AC_MIN_BPS = 9000;
    uint16 public constant AC_MAX_BPS = 11000;
    uint16 public constant COUPON_MAX_BPS = 1500;  // 15% per period
    uint32 public constant MATURITY_MIN_SECS = 604800;      // >= 1 week out
    uint32 public constant MATURITY_MAX_SECS = 63_072_000;  // <= 2 years out

    uint40 public constant MAX_FEED_STALENESS = 26 hours; // 24/5 feed + margin
    uint16 public constant MAX_FEE_BPS = 200;             // deploy-level cap

    IAggregatorV3 public immutable feed;   // TSLA/USD
    ISurrogatePricer public immutable pricer;

    event NoteQuoted(
        bytes32 indexed termsHash,
        uint256 notional,
        uint16 priceBpsOfNotional,
        uint16 feeBps,
        address feeReceiver,
        bytes32 weightsHash
    );

    constructor(address feed_, address pricer_) {
        feed = IAggregatorV3(feed_);
        pricer = ISurrogatePricer(pricer_);
    }

    /// In-path quote at mint/exit. Fee is a parameter of the call — the
    /// integrator's cut is explicit and emitted, not hidden in the price.
    function quote(NoteTerms calldata terms, uint256 notional, uint16 feeBps, address feeReceiver)
        external
        view
        returns (uint256 totalCost, uint16 priceBpsOfNotional)
    {
        if (feeBps > MAX_FEE_BPS) revert FeeTooHigh();
        PricerInputs memory in_ = extractFeatures(terms);
        checkRanges(in_);
        priceBpsOfNotional = pricer.priceBps(in_);
        totalCost = notional * (uint256(priceBpsOfNotional) + feeBps) / 10_000;
        // event emitted by the non-view vault wrapper (view fns can't emit);
        // fields above are exactly what NoteQuoted carries.
    }

    /// Feed read + feature derivation. This is the only place Robinhood Chain
    /// data enters the system.
    function extractFeatures(NoteTerms calldata terms) public view returns (PricerInputs memory in_) {
        (int256 answer, uint256 updatedAt) = _latestSpot();
        // NOTE: live probe of the mainnet TSLA/USD feed AND its aggregator
        // (0x7A6b…33b1, 2026-09-29) shows neither implements oraclePaused() —
        // the call reverts empty. Corporate-action/feed pause therefore has to
        // be detected via staleness, which is the check below.
        if (block.timestamp - updatedAt > MAX_FEED_STALENESS) revert FeedStale(uint40(updatedAt));
        if (answer <= 0) revert BadFeedAnswer();
        uint256 spot = uint256(answer);

        in_.spotBpsOfInitial = uint16(spot * 10_000 / terms.initialFixing);
        in_.distToKnockInBps = int32(
            (int256(spot) - int256(terms.initialFixing * terms.kiBarrierBps / 10_000)) * 10_000
                / int256(terms.initialFixing)
        );
        in_.volBpsAnnual = terms.volBpsAnnual;
        in_.kiBarrierBps = terms.kiBarrierBps;
        in_.acBarrierBps = terms.acBarrierBps;
        in_.couponBpsPerPeriod = terms.couponBpsPerPeriod;

        if (block.timestamp >= terms.maturity) revert NoteExpired();
        in_.timeToMaturitySecs = uint32(terms.maturity - block.timestamp);
        in_.timeToNextObsSecs = terms.nextObservation > block.timestamp
            ? uint32(terms.nextObservation - block.timestamp)
            : 0;
        in_.observationsRemaining = terms.observationsRemaining;
        in_.flags = terms.knockedIn ? 1 : 0;
    }

    function checkRanges(PricerInputs memory in_) public pure {
        if (in_.spotBpsOfInitial < SPOT_MIN_BPS || in_.spotBpsOfInitial > SPOT_MAX_BPS)
            revert OutOfRange("spotBpsOfInitial", int256(uint256(in_.spotBpsOfInitial)));
        if (in_.distToKnockInBps < DIST_MIN_BPS || in_.distToKnockInBps > DIST_MAX_BPS)
            revert OutOfRange("distToKnockInBps", int256(in_.distToKnockInBps));
        if (in_.volBpsAnnual < VOL_MIN_BPS || in_.volBpsAnnual > VOL_MAX_BPS)
            revert OutOfRange("volBpsAnnual", int256(uint256(in_.volBpsAnnual)));
        if (in_.kiBarrierBps < KI_MIN_BPS || in_.kiBarrierBps > KI_MAX_BPS)
            revert OutOfRange("kiBarrierBps", int256(uint256(in_.kiBarrierBps)));
        if (in_.acBarrierBps < AC_MIN_BPS || in_.acBarrierBps > AC_MAX_BPS)
            revert OutOfRange("acBarrierBps", int256(uint256(in_.acBarrierBps)));
        if (in_.couponBpsPerPeriod > COUPON_MAX_BPS)
            revert OutOfRange("couponBpsPerPeriod", int256(uint256(in_.couponBpsPerPeriod)));
        if (in_.timeToMaturitySecs < MATURITY_MIN_SECS || in_.timeToMaturitySecs > MATURITY_MAX_SECS)
            revert OutOfRange("timeToMaturitySecs", int256(uint256(in_.timeToMaturitySecs)));
    }

    function _latestSpot() internal view returns (int256 answer, uint256 updatedAt) {
        (, answer,, updatedAt,) = feed.latestRoundData();
    }
}
