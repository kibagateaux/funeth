// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {console} from "forge-std/console.sol";
import {AddressSet, LibAddressSet, EnumerableSetUsage} from "../helpers/AddressSet.sol";
import {IERC20x} from "../../src/Interfaces.sol";
import {FunETH} from "../../src/FunETH.sol";
import {FunCityLandRegistry} from "../../src/FunCityLandRegistry.sol";
import {NNRegistryCoreTest} from "./NNRegistryCore.t.sol";
import {EnumerableSetLib} from "solady/utils/EnumerableSetLib.sol";

contract Handler is NNRegistryCoreTest {
    using LibAddressSet for AddressSet;

    using EnumerableSetLib for EnumerableSetLib.Uint256Set;
    using EnumerableSetUsage for EnumerableSetLib.Uint256Set;

    // data for each nnToken used in the registry  to track different units, deposit/withdrawals, etc.
    struct NNTokenRegistryData {
        uint256 ghost_depositSum;
        uint256 ghost_withdrawSum;
        uint256 ghost_forcePushSum;
        EnumerableSetLib.Uint256Set ghost_stakedIDs;
        EnumerableSetLib.Uint256Set ghost_acceptedIDs;
    }

    mapping(address => NNTokenRegistryData) public nnTokenData;
    mapping(address => EnumerableSetLib.Uint256Set) public staker_nfts;
    mapping(address => EnumerableSetLib.Uint256Set) public city_lots;
    mapping(uint64 => EnumerableSetLib.Uint256Set) public city_buyers;

    uint256 public ghost_depositSum;
    uint256 public ghost_withdrawSum;
    uint256 public ghost_forcePushSum;

    uint256 public ghost_zeroWithdrawals;
    uint256 public ghost_zeroTransfers;
    uint256 public ghost_zeroTransferFroms;

    uint256 public ghost_settledTrades; // trades executed on cowswap

    mapping(bytes32 => uint256) public calls;

    AddressSet internal _actors;
    address internal currentActor;
    address internal token;

    modifier createActor() {
        currentActor = msg.sender;
        _actors.add(msg.sender);
        _;
    }

    modifier useNNToken() {
        token = uint256(uint160(msg.sender)) % 2 == 0 ? token = address(funETH) : token = address(funUSDC);
        _;
    }

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = _actors.rand(actorIndexSeed);
        _;
    }

    modifier countCall(bytes32 key) {
        calls[key]++;
        _;
    }

    constructor(FunCityLandRegistry _registry) {
        registry = _registry;

        // init balances to cap testing
        token = address(0);
        _pay(address(this), MAX_AAVE_DEPOSIT / 4);
        token = address(funETH);
        _pay(address(this), MAX_AAVE_DEPOSIT * 3 / 4);
        token = address(USDC);
        _pay(address(this), MAX_AAVE_DEPOSIT / 4);
        token = address(funUSDC);
        _pay(address(this), MAX_AAVE_DEPOSIT * 3 / 4);
    }

    function stake(uint128 amount) public createActor useNNToken countCall("stake") {
        amount = uint128(bound(amount, uint128(0), uint128(IERC20x(token).balanceOf(address(this)))));
        _pay(currentActor, amount);

        vm.prank(currentActor);
        IERC20x(token).approve(address(registry), amount);
        vm.prank(currentActor);
        uint256 stakeID = registry.stake(lotID, currentActor, token, amount);
        nnTokenData[token].ghost_depositSum += amount;
        nnTokenData[token].ghost_stakedIDs.add(stakeID);
        staker_nfts[currentActor].add(stakeID);
        city_buyers[lotID].add(stakeID);
    }

    function increaseStake(uint256 actorSeed, uint128 amount) public useActor(actorSeed) countCall("increaseStake") {
        amount = uint128(bound(amount, uint128(0), uint128(IERC20x(token).balanceOf(address(this)))));
        _pay(currentActor, amount);

        uint256 stakeID = staker_nfts[currentActor].rand(actorSeed);
        vm.prank(currentActor);
        IERC20x(token).approve(address(registry), amount);
        vm.prank(currentActor);
        registry.increaseStake(stakeID, amount);
        nnTokenData[token].ghost_depositSum += amount;
    }

    function depositUSDCAndStake(uint128 amount) public createActor countCall("depositUSDCAndStake") {
        token = address(USDC);
        amount = uint128(bound(amount, uint128(0), uint128(IERC20x(token).balanceOf(address(this)))));
        _pay(currentActor, amount);

        vm.prank(currentActor);
        USDC.approve(address(registry), amount);
        vm.prank(currentActor);
        uint256 stakeID = registry.depositUSDCAndStake(lotID, currentActor, amount);
        nnTokenData[address(funUSDC)].ghost_depositSum += amount;
        nnTokenData[address(funUSDC)].ghost_stakedIDs.add(stakeID);
        staker_nfts[currentActor].add(stakeID);
        city_buyers[lotID].add(stakeID);
    }

    function depositETHAndStake(uint128 amount) public createActor countCall("depositETHAndStake") {
        token = address(0);
        amount = uint128(bound(amount, uint128(0), uint128(address(this).balance)));
        _pay(currentActor, amount);

        vm.prank(currentActor);
        uint256 stakeID = registry.depositETHAndStake{value: amount}(lotID, currentActor);
        nnTokenData[address(funETH)].ghost_depositSum += amount;
        nnTokenData[address(funETH)].ghost_stakedIDs.add(stakeID);
        staker_nfts[currentActor].add(stakeID);
        city_buyers[lotID].add(stakeID);
    }

    function unstake(uint256 actorSeed) public useActor(actorSeed) countCall("unstake") {
        vm.prank(currentActor);
        uint256 stakeID = staker_nfts[currentActor].rand(actorSeed);
        (, uint256 amount) = registry.stakes(stakeID);

        registry.unstake(registry.getLotForStake(stakeID), stakeID, currentActor);

        nnTokenData[token].ghost_depositSum -= amount;
        nnTokenData[token].ghost_stakedIDs.remove(stakeID);
        staker_nfts[currentActor].remove(stakeID);
        city_buyers[lotID].remove(stakeID);
    }

    function transferFrom(uint256 actorSeed, uint256 fromSeed, uint256 toSeed, bool toApprove)
        public
        useActor(actorSeed)
        countCall("transferFrom")
    {
        address from = _actors.rand(fromSeed);
        address to = _actors.rand(toSeed);
        uint256 stakeID = staker_nfts[from].rand(actorSeed);
        if (toApprove) {
            vm.prank(from);
            registry.approve(currentActor, stakeID);
        } else {
            // for erc20 we would only transferFrom allowance() amount but doesnt exist for NFT
        }

        vm.prank(currentActor);
        registry.transferFrom(from, to, stakeID);
        staker_nfts[to].add(stakeID);
        staker_nfts[from].remove(stakeID);
    }

    function approve(uint256 actorSeed, uint256 fromSeed, bool approveAll)
        public
        useActor(actorSeed)
        countCall("approve")
    {
        address from = _actors.rand(fromSeed);
        uint256 stakeID = staker_nfts[from].rand(actorSeed);
        if (approveAll) {
            vm.prank(from);
            registry.setApprovalForAll(currentActor, true);
        } else {
            vm.prank(from);
            registry.approve(currentActor, stakeID);
        }
    }

    /**
     * property manager admin funcs ***
     */
    function approveBuyer(uint256 actorSeed) public useActor(actorSeed) countCall("approveBuyer") {
        uint64 lot = uint64(city_lots[currentActor].rand(actorSeed));
        vm.assume(city_buyers[lot].length() > 0);
        uint256 buyer = city_buyers[lot].rand(actorSeed);

        FunCityLandRegistry.Property memory property = registry.properties(lotID);
        vm.prank(property.city);
        registry.approveBuyer(lotID, buyer);
        nnTokenData[token].ghost_acceptedIDs.add(buyer);
    }

    function listProperty(uint64 price, uint64 deposit) public createActor countCall("listProperty") {
        vm.prank(registry.curator());
        registry.addCity(currentActor, 1);

        vm.prank(currentActor);
        FunCityLandRegistry.ListingDetails memory property =
            FunCityLandRegistry.ListingDetails({price: price, deposit: deposit, uri: ""});

        // TODO maybe causes problems with global lotID var
        lotID = registry.listProperty(property);

        city_lots[currentActor].add(lotID);
    }

    function delistProperty(uint256 actorSeed) public useActor(actorSeed) countCall("delistProperty") {
        uint64 lot = uint64(city_lots[currentActor].rand(actorSeed));
        emit log_named_uint("delistProperty lot #", lot);
        registry.delistProperty(lot);
        city_lots[currentActor].remove(lot);
    }

    function confirmSettlement(uint256 citySeed) public useActor(citySeed) countCall("confirmSettlement") {
        uint64 lot = uint64(city_lots[currentActor].rand(citySeed));
        uint256 buyer = city_buyers[lot].rand(citySeed);
        vm.assume(buyer != 0);

        bytes32 tradeHash = registry.properties(lotID).tradeHash;
        bytes memory uid = abi.encode(keccak256(abi.encode(tradeHash, address(registry), block.timestamp)));
        registry.confirmSettlement(uid);

        // remove old nnTokenData
        // add new nnTokenData
    }

    // function deposit(uint256 amount) public createActor countCall("deposit") {
    //     amount = bound(amount, 0, address(this).balance);
    //     _pay(currentActor, amount);

    //     vm.prank(currentActor);
    //     WETH.deposit{value: amount}();
    //     funETH.deposit(amount);

    //     ghost_depositSum += amount;
    // }

    // function stake(uint256 actorSeed, uint256 amount) public useActor(actorSeed) countCall("withdraw") {
    //     amount = bound(amount, 0, funETH.balanceOf(currentActor));
    //     if (amount == 0) ghost_zeroWithdrawals++;

    //     vm.startPrank(currentActor);
    //     funETH.withdraw(amount);
    //     _pay(address(this), amount);
    //     vm.stopPrank();

    //     ghost_withdrawSum += amount;
    // }

    // function approve(uint256 actorSeed, uint256 spenderSeed, uint256 amount)
    //     public
    //     useActor(actorSeed)
    //     countCall("approve")
    // {
    //     address spender = _actors.rand(spenderSeed);

    //     vm.prank(currentActor);
    //     funETH.approve(spender, amount);
    // }

    // function transfer(uint256 actorSeed, uint256 toSeed, uint256 amount)
    //     public
    //     useActor(actorSeed)
    //     countCall("transfer")
    // {
    //     address to = _actors.rand(toSeed);

    //     amount = bound(amount, 0, funETH.balanceOf(currentActor));
    //     if (amount == 0) ghost_zeroTransfers++;

    //     vm.prank(currentActor);
    //     funETH.transfer(to, amount);
    // }

    // function transferFrom(uint256 actorSeed, uint256 fromSeed, uint256 toSeed, bool _approve, uint256 amount)
    //     public
    //     useActor(actorSeed)
    //     countCall("transferFrom")
    // {
    //     address from = _actors.rand(fromSeed);
    //     address to = _actors.rand(toSeed);

    //     amount = bound(amount, 0, funETH.balanceOf(from));

    //     if (_approve) {
    //         vm.prank(from);
    //         funETH.approve(currentActor, amount);
    //     } else {
    //         amount = bound(amount, 0, funETH.allowance(from, currentActor));
    //     }
    //     if (amount == 0) ghost_zeroTransferFroms++;

    //     vm.prank(currentActor);
    //     funETH.transferFrom(from, to, amount);
    // }

    // function sendFallback(uint256 amount) public createActor countCall("sendFallback") {
    //     amount = bound(amount, 0, address(this).balance);
    //     _pay(currentActor, amount);

    //     vm.prank(currentActor);
    //     _pay(address(funETH), amount);

    //     ghost_depositSum += amount;
    // }

    // function forcePush(uint256 amount) public countCall("forcePush") {
    //     amount = bound(amount, 0, address(this).balance);
    //     new ForcePush{ value: amount }(address(funETH));
    //     ghost_forcePushSum += amount;
    // }

    function forEachActor(function(address) external func) public {
        return _actors.forEach(func);
    }

    function reduceActors(uint256 acc, function(uint256,address) external returns (uint256) func)
        public
        returns (uint256)
    {
        return _actors.reduce(acc, func);
    }

    function actors() external view returns (address[] memory) {
        return _actors.addrs;
    }

    function netUSDCDeposits() public view returns (uint256) {
        return nnTokenData[address(funUSDC)].ghost_depositSum + nnTokenData[address(funUSDC)].ghost_forcePushSum
            - nnTokenData[address(funUSDC)].ghost_withdrawSum;
    }

    function netFunETHDeposits() public view returns (uint256) {
        return nnTokenData[address(funETH)].ghost_depositSum + nnTokenData[address(funETH)].ghost_forcePushSum
            - nnTokenData[address(funETH)].ghost_withdrawSum;
    }

    function netDeposits() external view returns (uint256) {
        return funUSDC.convertToDecimal(netUSDCDeposits(), funUSDC.decimals(), 8)
            + funETH.convertToDecimal(netFunETHDeposits() * funETH.price(true), funETH.decimals(), 8);
    }

    function callSummary() external view {
        console.log("Call summary:");
        console.log("-------------------");
        console.log("stake", calls["stake"]);
        console.log("depositUSDCAndStake", calls["depositUSDCAndStake"]);
        console.log("depositETHAndStake", calls["depositETHAndStake"]);
        console.log("unstake", calls["unstake"]);
        console.log("approve", calls["approve"]);
        console.log("transfer", calls["transfer"]);
        console.log("transferFrom", calls["transferFrom"]);

        console.log("approveBuyer", calls["approveBuyer"]);
        console.log("listProperty", calls["listProperty"]);

        // console.log("forcePush", calls["forcePush"]);
        console.log("-------------------");

        console.log("Zero withdrawals:", ghost_zeroWithdrawals);
        console.log("Zero transferFroms:", ghost_zeroTransferFroms);
        console.log("Zero transfers:", ghost_zeroTransfers);
    }

    function _pay(address to, uint256 amount) internal {
        if (token == address(0)) {
            (bool s,) = to.call{value: amount}("");
            require(s, "pay() failed");
        } else {
            deal(token, to, amount);
        }
    }

    receive() external payable {}
}
