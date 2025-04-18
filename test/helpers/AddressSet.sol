// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {EnumerableSetLib} from "solady/utils/EnumerableSetLib.sol";

library EnumerableSetUsage {
    using EnumerableSetLib for *;

    function rand(EnumerableSetLib.Bytes32Set storage s, uint256 seed) internal view returns (bytes32) {
        if (s.length() > 0) {
            return s.at(seed % s.length());
        } else {
            return bytes32(0);
        }
    }

    function forEach(EnumerableSetLib.Bytes32Set storage s, function(bytes32) external func) internal {
        for (uint256 i; i < s.length(); ++i) {
            func(s.at(i));
        }
    }

    function reduce(
        EnumerableSetLib.Bytes32Set storage s,
        uint256 acc,
        function(uint256,bytes32) external returns (uint256) func
    ) internal returns (uint256) {
        for (uint256 i; i < s.length(); ++i) {
            acc = func(acc, s.at(i));
        }
        return acc;
    }

    function rand(EnumerableSetLib.Uint256Set storage s, uint256 seed) internal view returns (uint256) {
        return uint256(rand(s._toBytes32Set(), seed));
    }

    function forEach(EnumerableSetLib.Uint256Set storage s, function(bytes32) external func) internal {
        forEach(s._toBytes32Set(), func);
    }

    function reduce(
        EnumerableSetLib.Uint256Set storage s,
        uint256 acc,
        function(uint256,bytes32) external returns (uint256) func
    ) internal returns (uint256) {
        return reduce(s._toBytes32Set(), acc, func);
    }

    // function rand(EnumerableSetLib.AddressSet storage s, uint256 seed) internal view returns (address) {
    //    return address(rand(s._toBytes32Set(), seed));
    // }

    // function forEach(EnumerableSetLib.AddressSet storage s, function(bytes32) external func) internal returns (EnumerableSetLib.AddressSet storage a) {
    //     forEach(s._toBytes32Set(), func).slot;
    // }

    // function reduce(EnumerableSetLib.AddressSet storage s, uint256 acc, function(uint256,bytes32) external returns (uint256) func)
    //     internal
    //     returns (uint256)
    // {
    //     return reduce(s._toBytes32Set(), acc, func);
    // }
}

struct AddressSet {
    address[] addrs;
    mapping(address => bool) saved;
}

library LibAddressSet {
    function add(AddressSet storage s, address addr) internal {
        if (!s.saved[addr]) {
            s.addrs.push(addr);
            s.saved[addr] = true;
        }
    }

    function contains(AddressSet storage s, address addr) internal view returns (bool) {
        return s.saved[addr];
    }

    function count(AddressSet storage s) internal view returns (uint256) {
        return s.addrs.length;
    }

    function rand(AddressSet storage s, uint256 seed) internal view returns (address) {
        if (s.addrs.length > 0) {
            return s.addrs[seed % s.addrs.length];
        } else {
            return address(0);
        }
    }

    function forEach(AddressSet storage s, function(address) external func) internal {
        for (uint256 i; i < s.addrs.length; ++i) {
            func(s.addrs[i]);
        }
    }

    function reduce(AddressSet storage s, uint256 acc, function(uint256,address) external returns (uint256) func)
        internal
        returns (uint256)
    {
        for (uint256 i; i < s.addrs.length; ++i) {
            acc = func(acc, s.addrs[i]);
        }
        return acc;
    }
}
