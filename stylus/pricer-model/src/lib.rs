//! Surrogate Pricer — Stylus student model.
//!
//! A pure function from a note's state to its fair value in bps of notional:
//! an integer MLP distilled from an off-chain Monte Carlo teacher, with the
//! weights compiled in and pinned by `weightsHash()`. No storage, no external
//! calls, no `block.timestamp`: time enters only through the inputs.
//!
//! ```solidity
//! interface ISurrogatePricer {
//!     error OutOfRange(uint8 field, int64 value);
//!     function priceBps(PricerInputs calldata in_) external view returns (uint16);
//!     function weightsHash() external view returns (bytes32);
//!     function featureSpecVersion() external pure returns (uint16);
//! }
//! ```
//! `PricerInputs` is the static struct in NoteQuoter.sol; its ABI encoding is
//! the 10-tuple taken by `price_bps` below.

#![cfg_attr(not(any(test, feature = "export-abi")), no_main)]
extern crate alloc;

pub mod engine;

use alloy_primitives::FixedBytes;
use alloy_sol_types::sol;
use stylus_sdk::prelude::*;

pub const FEATURE_SPEC_VERSION: u16 = 1;

sol! {
    /// Input `field` (index in PricerInputs) is outside the training range.
    #[derive(Debug, PartialEq, Eq)]
    error OutOfRange(uint8 field, int64 value);
}

#[derive(SolidityError, Debug, PartialEq, Eq)]
pub enum PricerError {
    OutOfRange(OutOfRange),
}

/// (spotBpsOfInitial, distToKnockInBps, volBpsAnnual, kiBarrierBps,
///  acBarrierBps, couponBpsPerPeriod, timeToMaturitySecs, timeToNextObsSecs,
///  observationsRemaining, flags)
pub type PricerInputs = (u16, i32, u16, u16, u16, u16, u32, u32, u8, u8);

#[storage]
#[entrypoint]
pub struct SurrogatePricer {}

#[public]
impl SurrogatePricer {
    /// Fair value of the note in bps of notional. Reverts with
    /// `OutOfRange` instead of extrapolating.
    pub fn price_bps(&self, inputs: PricerInputs) -> Result<u16, PricerError> {
        let raw = [
            inputs.0 as i64,
            inputs.1 as i64,
            inputs.2 as i64,
            inputs.3 as i64,
            inputs.4 as i64,
            inputs.5 as i64,
            inputs.6 as i64,
            inputs.7 as i64,
            inputs.8 as i64,
            inputs.9 as i64,
        ];
        engine::price_bps(&raw)
            .map_err(|e| PricerError::OutOfRange(OutOfRange { field: e.field, value: e.value }))
    }

    /// keccak256 of the canonical student_export.json this contract was built
    /// from (recomputed at build time, not copied).
    pub fn weights_hash(&self) -> FixedBytes<32> {
        FixedBytes(engine::WEIGHTS_HASH)
    }

    pub fn feature_spec_version(&self) -> u16 {
        FEATURE_SPEC_VERSION
    }
}
