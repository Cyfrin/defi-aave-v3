// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/Test.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IPool} from "../interfaces/aave-v3/IPool.sol";
import {POOL} from "../Constants.sol";

contract Liquidate {
    IPool public constant pool = IPool(POOL);

    // Task 1 - Liquidate an under-collateralized loan
    function liquidate(address collateral, address borrowedToken, address user)
        public {
        // Task 1.1 - Get the amount of borrowed token that the user owes to Aave V3

        // Task 1.2 - Transfer the full borrowed amount from msg.sender

        // Task 1.3 - Approve the pool contract to spend borrowed token from this contract

        // Task 1.4 - Call liquidate
    }
}
