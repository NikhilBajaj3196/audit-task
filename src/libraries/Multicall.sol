// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

abstract contract MulticallUpgradeable is Initializable {
    function __Multicall_init() internal onlyInitializing {}

    function __Multicall_init_unchained() internal onlyInitializing {}

    function multicall(
        bytes[] calldata data
    ) external payable returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            results[i] = Address.functionDelegateCall(
                address(this),
                data[i]
            );
        }
        return results;
    }
}
