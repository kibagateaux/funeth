// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {console} from "forge-std/console.sol";
import {AddressSet, LibAddressSet} from "./helpers/AddressSet.sol";
import {IERC20x} from "../src/Interfaces.sol";
import {nnETH as NetworkNationETH} from "../src/nnETH.sol";
import {nnEthBaseTest} from "./nnEthBaseTest.t.sol";


uint256 constant ETH_SUPPLY = 120_500_000 ether;

contract ForcePush {
    constructor(address dst) payable {
        selfdestruct(payable(dst));
    }
}

contract Handler is nnEthBaseTest {
    using LibAddressSet for AddressSet;

    uint256 public ghost_depositSum;
    uint256 public ghost_withdrawSum;
    uint256 public ghost_forcePushSum;

    uint256 public ghost_zeroWithdrawals;
    uint256 public ghost_zeroTransfers;
    uint256 public ghost_zeroTransferFroms;

    mapping(bytes32 => uint256) public calls;

    AddressSet internal _actors;
    address internal currentActor;
    address internal token;

    modifier createActor() {
        currentActor = msg.sender;
        _actors.add(msg.sender);
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

    constructor(NetworkNationETH _weth, address reserveToken) {
        nnETH = _weth;
        token = reserveToken;
        deal(address(reserveToken), address(this), ETH_SUPPLY);
    }

    function deposit(uint256 amount) public createActor countCall("deposit") {
        amount = bound(amount, 0, address(this).balance);
        _pay(currentActor, amount);

        vm.prank(currentActor);
        WETH.deposit{value: amount}();
        nnETH.deposit(amount);

        ghost_depositSum += amount;
    }

    function withdraw(uint256 actorSeed, uint256 amount) public useActor(actorSeed) countCall("withdraw") {
        amount = bound(amount, 0, nnETH.balanceOf(currentActor));
        if (amount == 0) ghost_zeroWithdrawals++;

        vm.startPrank(currentActor);
        nnETH.withdraw(amount);
        _pay(address(this), amount);
        vm.stopPrank();

        ghost_withdrawSum += amount;
    }

    function approve(uint256 actorSeed, uint256 spenderSeed, uint256 amount)
        public
        useActor(actorSeed)
        countCall("approve")
    {
        address spender = _actors.rand(spenderSeed);

        vm.prank(currentActor);
        nnETH.approve(spender, amount);
    }

    function transfer(uint256 actorSeed, uint256 toSeed, uint256 amount)
        public
        useActor(actorSeed)
        countCall("transfer")
    {
        address to = _actors.rand(toSeed);

        amount = bound(amount, 0, nnETH.balanceOf(currentActor));
        if (amount == 0) ghost_zeroTransfers++;

        vm.prank(currentActor);
        nnETH.transfer(to, amount);
    }

    function transferFrom(uint256 actorSeed, uint256 fromSeed, uint256 toSeed, bool _approve, uint256 amount)
        public
        useActor(actorSeed)
        countCall("transferFrom")
    {
        address from = _actors.rand(fromSeed);
        address to = _actors.rand(toSeed);

        amount = bound(amount, 0, nnETH.balanceOf(from));

        if (_approve) {
            vm.prank(from);
            nnETH.approve(currentActor, amount);
        } else {
            amount = bound(amount, 0, nnETH.allowance(from, currentActor));
        }
        if (amount == 0) ghost_zeroTransferFroms++;

        vm.prank(currentActor);
        nnETH.transferFrom(from, to, amount);
    }

    function sendFallback(uint256 amount) public createActor countCall("sendFallback") {
        amount = bound(amount, 0, address(this).balance);
        _pay(currentActor, amount);

        vm.prank(currentActor);
        _pay(address(nnETH), amount);

        ghost_depositSum += amount;
    }

    // function forcePush(uint256 amount) public countCall("forcePush") {
    //     amount = bound(amount, 0, address(this).balance);
    //     new ForcePush{ value: amount }(address(nnETH));
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

    function netDeposits() external view returns (uint256) {
        return ghost_depositSum + ghost_forcePushSum - ghost_withdrawSum;
    }

    function callSummary() external view {
        console.log("Call summary:");
        console.log("-------------------");
        console.log("deposit", calls["deposit"]);
        console.log("withdraw", calls["withdraw"]);
        console.log("sendFallback", calls["sendFallback"]);
        console.log("approve", calls["approve"]);
        console.log("transfer", calls["transfer"]);
        console.log("transferFrom", calls["transferFrom"]);
        // console.log("forcePush", calls["forcePush"]);
        console.log("-------------------");

        console.log("Zero withdrawals:", ghost_zeroWithdrawals);
        console.log("Zero transferFroms:", ghost_zeroTransferFroms);
        console.log("Zero transfers:", ghost_zeroTransfers);
    }

    function _pay(address to, uint256 amount) internal {
        if(token == address(0)) {
            (bool s,) = to.call{value: amount}("");
            require(s, "pay() failed");
        } else {
            deal(token, to, amount);
        }
    }

    receive() external payable {}
}