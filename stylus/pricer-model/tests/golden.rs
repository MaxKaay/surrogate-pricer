//! Golden-vector CI: the compiled contract must reproduce the quantized Python
//! reference exactly (no tolerance) for every model vector, and reject every
//! out-of-range vector with the right field index.

use serde_json::Value;
use surrogate_pricer_model::{OutOfRange, PricerError, SurrogatePricer, engine};

const FIELDS: [&str; 10] = [
    "spotBpsOfInitial",
    "distToKnockInBps",
    "volBpsAnnual",
    "kiBarrierBps",
    "acBarrierBps",
    "couponBpsPerPeriod",
    "timeToMaturitySecs",
    "timeToNextObsSecs",
    "observationsRemaining",
    "flags",
];

fn vectors() -> Value {
    let path = concat!(env!("PRICER_MODEL_DIR"), "/golden_vectors.json");
    serde_json::from_str(&std::fs::read_to_string(path).expect("golden_vectors.json")).unwrap()
}

fn raw(features: &Value) -> [i64; 10] {
    FIELDS.map(|f| features[f].as_i64().unwrap_or_else(|| panic!("missing {f}")))
}

fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

#[test]
fn vectors_belong_to_compiled_model() {
    let v = vectors();
    assert_eq!(v["weightsHash"].as_str().unwrap(), format!("0x{}", hex(&engine::WEIGHTS_HASH)));
}

#[test]
fn model_vectors_exact() {
    let v = vectors();
    let rows = v["modelVectors"].as_array().unwrap();
    assert_eq!(rows.len(), 100);
    for (n, row) in rows.iter().enumerate() {
        let want = row["expectedPriceBps"].as_u64().unwrap() as u16;
        assert_eq!(engine::price_bps(&raw(&row["features"])), Ok(want), "vector {n}");
    }
}

#[test]
fn reject_vectors_fail_closed() {
    let v = vectors();
    let rows = v["rejectVectors"].as_array().unwrap();
    assert!(!rows.is_empty());
    for (n, row) in rows.iter().enumerate() {
        let r = raw(&row["features"]);
        let field = row["fieldIndex"].as_u64().unwrap() as u8;
        let err = engine::price_bps(&r).expect_err("accepted out-of-range input");
        assert_eq!(err.field, field, "vector {n}");
        assert_eq!(err.value, r[field as usize], "vector {n}");
    }
}

#[test]
fn contract_abi_path_matches_engine() {
    use stylus_sdk::testing::*;
    let vm = TestVM::default();
    let c = SurrogatePricer::from(&vm);
    let v = vectors();
    for row in v["modelVectors"].as_array().unwrap().iter().take(10) {
        let r = raw(&row["features"]);
        let t = (
            r[0] as u16, r[1] as i32, r[2] as u16, r[3] as u16, r[4] as u16,
            r[5] as u16, r[6] as u32, r[7] as u32, r[8] as u8, r[9] as u8,
        );
        assert_eq!(c.price_bps(t).unwrap() as u64, row["expectedPriceBps"].as_u64().unwrap());
    }
    // uint16 field below its minimum -> OutOfRange(0, 1999)
    let bad = (1_999, 0, 5_000, 6_000, 10_000, 100, 10_000_000, 0, 10, 0);
    assert_eq!(
        c.price_bps(bad),
        Err(PricerError::OutOfRange(OutOfRange { field: 0, value: 1_999 }))
    );
    assert_eq!(c.weights_hash().0, engine::WEIGHTS_HASH);
}

#[test]
fn rounding_is_symmetric() {
    assert_eq!(engine::round_shift(-1, 2), 0); // -0.25 -> 0 (a floor-shift gives -1)
    assert_eq!(engine::round_shift(-2, 2), -1); // -0.5 -> -1 (away from zero)
    assert_eq!(engine::round_shift(2, 2), 1); // 0.5 -> 1
    assert_eq!(engine::round_shift(-3, 1), -2);
    assert_eq!(engine::round_shift(5, 3), 1);
}
