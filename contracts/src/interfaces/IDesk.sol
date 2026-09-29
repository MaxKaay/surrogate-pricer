// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {INoteQuoter} from "./INoteQuoter.sol";
import {ISeriesFactory} from "./ISeriesFactory.sol";

/// L3: the market for NOTE, and the pricer's only in-path use. An ERC-4626
/// vault on USDG: LPs deposit USDG; the Desk mints NOTE+WRITER pairs, sells
/// NOTE at the model's quote, keeps WRITER, and buys NOTE back for early exit.
/// All policy lives here: the curated grid, vol, caps, bands, fee cap.
///
/// Units: noteAmount in NOTE base units (6 decimals, 1 NOTE = 1 USDG notional);
/// priceBps and feeBps in bps of notional. cost/proceeds in USDG base units.
///   buy:  cost     = ceil(noteAmount * priceBps / 1e4)  + fee
///   sell: proceeds = floor(noteAmount * priceBps / 1e4) - fee
///   fee = ceil(noteAmount * feeBps / 1e4); feeReceiver gets fee minus the
///   BACKSTOP_SHARE_BPS slice, which stays in the vault.
///
/// LP flows: maxDeposit / maxWithdraw return 0 while any held series can't be
/// quoted (weekend, pending fixing), because share price would be unknown.
interface IDesk is IERC4626 {
    struct Listing {
        bool active;
        uint16 volBpsAnnual; // implied vol used for every quote of this series
        uint128 capNotional; // max NOTE outstanding from this Desk (6 decimals)
        uint128 soldNotional; // NOTE currently sold and not bought back
    }

    event SeriesListed(address indexed series, uint16 volBpsAnnual, uint128 capNotional);
    event SeriesDelisted(address indexed series);
    /// Emitted on every buy: the quote, the model version and the explicit fee.
    event NoteBought(
        address indexed series,
        address indexed buyer,
        address to,
        uint256 noteAmount,
        uint16 priceBps,
        uint256 cost,
        uint16 feeBps,
        address feeReceiver,
        bytes32 weightsHash
    );
    event NoteSold(
        address indexed series,
        address indexed seller,
        address to,
        uint256 noteAmount,
        uint16 priceBps,
        uint256 proceeds,
        uint16 feeBps,
        address feeReceiver,
        bytes32 weightsHash
    );
    event Collected(address indexed series, uint256 collateralOut);

    error NotListed(address series);
    error CapExceeded(uint256 requested, uint256 available);
    error FeeTooHigh(uint16 feeBps);
    error Slippage(uint256 actual, uint256 limit);
    error TooCloseToObservation(uint40 obsTime); // ε-band before each observation
    // plus INoteQuoter errors and ISurrogatePricer.OutOfRange, bubbled up

    function factory() external view returns (ISeriesFactory);
    function quoter() external view returns (INoteQuoter);
    function MAX_FEE_BPS() external view returns (uint16);
    function BACKSTOP_SHARE_BPS() external view returns (uint16);
    function minSecsToObservation() external view returns (uint32);

    function listing(address series) external view returns (Listing memory);
    function listedSeries() external view returns (address[] memory);

    function quoteBuy(address series, uint256 noteAmount, uint16 feeBps)
        external
        view
        returns (uint256 cost, uint16 priceBps);
    function quoteSell(address series, uint256 noteAmount, uint16 feeBps)
        external
        view
        returns (uint256 proceeds, uint16 priceBps);

    /// Buyer pays `cost` USDG (approve the Desk) and receives `noteAmount` NOTE at `to`.
    function buy(address series, uint256 noteAmount, uint256 maxCost, uint16 feeBps, address feeReceiver, address to)
        external
        returns (uint256 cost);

    /// Seller hands in `noteAmount` NOTE (approve the Desk) and receives `proceeds` USDG at `to`.
    function sell(
        address series,
        uint256 noteAmount,
        uint256 minProceeds,
        uint16 feeBps,
        address feeReceiver,
        address to
    ) external returns (uint256 proceeds);

    /// Permissionless: after settlement, redeem the Desk's WRITER (and any NOTE) into USDG.
    function collect(address series) external returns (uint256 collateralOut);

    // --- curator (owner) -----------------------------------------------------
    function listSeries(address series, uint16 volBpsAnnual, uint128 capNotional) external;
    function delistSeries(address series) external; // stops new buys; sells still allowed
    function setMinSecsToObservation(uint32 secs) external;
}
