// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockChainlinkFeed} from "../src/MockChainlinkFeed.sol";
import {FixingsRecorder} from "../src/FixingsRecorder.sol";
import {NoteQuoter, NoteTerms} from "../src/NoteQuoter.sol";

contract FeedScenariosTest is Test {
    uint80 constant R1 = uint80(1) << 64 | 1; // 2^64 + 1
    int256 constant PRICE = 354_28_499_999; // $354.28 @ 8dec

    MockChainlinkFeed feed;
    FixingsRecorder recorder;
    NoteQuoter quoter;

    function setUp() public {
        vm.warp(1_790_699_124); // 2026-09-29 16:25 UTC, matches the probed fork
        feed = new MockChainlinkFeed("RHTSLA / USD");
        recorder = new FixingsRecorder(address(feed));
        quoter = new NoteQuoter(address(feed), address(1)); // dummy pricer: quote() not under test
    }

    function _terms(uint40 maturity, uint40 nextObs) internal pure returns (NoteTerms memory) {
        return NoteTerms({
            initialFixing: uint256(PRICE),
            kiBarrierBps: 6000,
            acBarrierBps: 10000,
            couponBpsPerPeriod: 200,
            volBpsAnnual: 5500,
            observationIntervalSecs: 604800,
            maturity: maturity,
            nextObservation: nextObs,
            observationsRemaining: 26,
            knockedIn: false
        });
    }

    // --- Case A: normal observation -------------------------------------

    function test_caseA_normal_week() public {
        feed.pushRound(PRICE); // R1 at t0
        vm.warp(block.timestamp + 30 minutes);
        feed.pushRound(PRICE + 1e8); // R2
        uint40 obsTime = uint40(block.timestamp) - 10 minutes; // between R1 and R2

        recorder.recordFixing(obsTime, R1);
        (uint40 ts, uint96 price, uint80 rid) = recorder.fixings(obsTime);
        assertEq(ts, 1_790_699_124);
        assertEq(price, uint96(uint256(PRICE)));
        assertEq(rid, R1);
        assertTrue(recorder.isRecorded(obsTime));
    }

    function test_caseA_rejects_older_round() public {
        feed.pushRound(PRICE); // R1
        vm.warp(block.timestamp + 30 minutes);
        feed.pushRound(PRICE); // R2
        uint40 obsTime = uint40(block.timestamp); // at/after R2
        // R1 is not the last round at-or-before obsTime — R2 is
        vm.expectRevert(abi.encodeWithSelector(FixingsRecorder.NotLastRoundBefore.selector, R1, obsTime));
        recorder.recordFixing(obsTime, R1);
    }

    function test_already_recorded() public {
        feed.pushRound(PRICE);
        uint40 obsTime = uint40(block.timestamp);
        recorder.recordFixing(obsTime, R1);
        vm.expectRevert(abi.encodeWithSelector(FixingsRecorder.AlreadyRecorded.selector, obsTime));
        recorder.recordFixing(obsTime, R1);
    }

    function test_bad_price_anomaly_guard() public {
        feed.pushRound(int256(3.96e18)); // the real feed's round-1 scale artifact
        vm.expectRevert(abi.encodeWithSelector(FixingsRecorder.BadPrice.selector, int256(3.96e18)));
        recorder.recordFixing(uint40(block.timestamp), R1);
    }

    // --- weekend: feed silent, quote fails closed -------------------------

    function test_weekend_quote_fails_closed() public {
        feed.pushRound(PRICE); // Friday close
        NoteTerms memory terms = _terms(uint40(block.timestamp + 180 days), uint40(block.timestamp + 3 days));
        quoter.extractFeatures(terms); // fresh: works

        vm.warp(block.timestamp + 27 hours); // Saturday night, feed asleep
        vm.expectRevert(abi.encodeWithSelector(NoteQuoter.FeedStale.selector, uint40(1_790_699_124)));
        quoter.extractFeatures(terms);
    }

    // --- Case B: halted feed, observation rolls to first fresh round ------

    function test_caseB_disrupted_day_roll() public {
        feed.pushRound(PRICE); // R1: Friday close
        uint40 obsTime = uint40(block.timestamp) + 7 days; // next Friday observation
        vm.warp(obsTime + 100 hours); // feed was halted >96h across the observation
        feed.pushRound(PRICE + 2e8); // R2: first round after the halt

        // the stale R1 is rejected for this observation
        vm.expectRevert(abi.encodeWithSelector(FixingsRecorder.FixingTooStale.selector, uint40(1_790_699_124), obsTime));
        recorder.recordFixing(obsTime, R1);

        // R2 is accepted as the rolled fixing
        recorder.recordFixing(obsTime, R1 + 1);
        (uint40 ts,, uint80 rid) = recorder.fixings(obsTime);
        assertEq(ts, obsTime + 100 hours);
        assertEq(rid, R1 + 1);
    }

    function test_caseB_rejects_beyond_hard_cap() public {
        feed.pushRound(PRICE);
        uint40 obsTime = uint40(block.timestamp) + 7 days;
        vm.warp(obsTime + 9 days); // dead > 8 days: vault-level settlement territory
        feed.pushRound(PRICE);
        vm.expectRevert(abi.encodeWithSelector(FixingsRecorder.RollTooLong.selector, uint40(obsTime + 9 days), obsTime));
        recorder.recordFixing(obsTime, R1 + 1);
    }

    function test_caseB_rejects_roll_without_gap() public {
        feed.pushRound(PRICE);
        uint40 obsTime = uint40(block.timestamp) + 30 minutes;
        vm.warp(obsTime + 10 minutes); // short gap, well under 96h
        feed.pushRound(PRICE);
        // R2 is after obsTime, but R1 proves there was NO disruption
        vm.expectRevert(abi.encodeWithSelector(FixingsRecorder.NoGapProof.selector, R1 + 1, obsTime));
        recorder.recordFixing(obsTime, R1 + 1);
    }

    // --- recorder reads a backdated staged round correctly -----------------

    function test_staged_backdated_round() public {
        feed.pushRoundAt(PRICE, uint40(1_790_600_000)); // staged "yesterday"
        recorder.recordFixing(uint40(1_790_600_000), R1);
        assertTrue(recorder.isRecorded(uint40(1_790_600_000)));
    }
}
