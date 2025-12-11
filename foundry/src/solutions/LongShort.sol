// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/Test.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {Aave} from "../lib/Aave.sol";
import {Swap} from "../lib/Swap.sol";
import {Math} from "../lib/Math.sol";

// NOTE: Don't use this contract in production.
// Any caller can borrow on behalf of this contract and withdraw collateral from this contract.

contract LongShort is Aave, Swap {
    struct OpenParams {
        address collateralToken;
        uint256 collateralAmount;
        address borrowToken;
        uint256 borrowAmount;
        uint256 minHealthFactor;
        uint256 minSwapAmountOut;
        bytes swapData;
    }

    // Approve this contract to pull in collateral
    // Approve this contract to borrow
    function open(OpenParams memory params)
        public
        returns (uint256 collateralAmountOut)
    {
        require(params.minHealthFactor > 1e18, "min health factor <= 1");

        // Transfer collateral
        IERC20(params.collateralToken)
            .transferFrom(msg.sender, address(this), params.collateralAmount);

        // Supply collateral
        IERC20(params.collateralToken)
            .approve(address(pool), params.collateralAmount);
        supply(params.collateralToken, params.collateralAmount, msg.sender);

        // Borrow token
        borrow(params.borrowToken, params.borrowAmount, msg.sender);

        // Check health factor
        require(
            getHealthFactor(msg.sender) >= params.minHealthFactor,
            "health factor < min"
        );

        // Swap borrowed token to collateral token
        IERC20(params.borrowToken).approve(address(router), params.borrowAmount);
        return swap({
            tokenIn: params.borrowToken,
            tokenOut: params.collateralToken,
            amountIn: params.borrowAmount,
            amountOutMin: params.minSwapAmountOut,
            receiver: msg.sender,
            data: params.swapData
        });
    }

    struct CloseParams {
        address collateralToken;
        uint256 collateralAmount;
        uint256 maxCollateralToWithdraw;
        address borrowToken;
        uint256 maxDebtToRepay;
        uint256 minSwapAmountOut;
        bytes swapData;
    }

    // Approve this contract to pull in collateral AToken
    // Approve this contract to pull in collateral
    // Approve this contract to pull in borrowed token if closing at a loss
    function close(CloseParams memory params)
        public
        returns (
            uint256 collateralWithdrawn,
            uint256 debtRepaidFromMsgSender,
            uint256 borrowedLeftover
        )
    {
        // Transfer collateral
        IERC20(params.collateralToken)
            .transferFrom(msg.sender, address(this), params.collateralAmount);

        // Swap collateral to borrowed token
        IERC20(params.collateralToken)
            .approve(address(router), params.collateralAmount);
        uint256 amountOut = swap({
            tokenIn: params.collateralToken,
            tokenOut: params.borrowToken,
            amountIn: params.collateralAmount,
            amountOutMin: params.minSwapAmountOut,
            receiver: address(this),
            data: params.swapData
        });

        // Repay borrowed token
        uint256 debtToRepay = Math.min(
            getVariableDebt(params.borrowToken, msg.sender),
            params.maxDebtToRepay
        );
        IERC20(params.borrowToken).approve(address(pool), debtToRepay);
        uint256 repayAmount = 0;
        if (debtToRepay > amountOut) {
            // msg.sender repays for the difference
            repayAmount = debtToRepay - amountOut;
            IERC20(params.borrowToken)
                .transferFrom(msg.sender, address(this), repayAmount);
        }
        repay(params.borrowToken, debtToRepay, msg.sender);

        // Withdraw collateral to msg.sender
        IERC20 aToken = IERC20(getATokenAddress(params.collateralToken));
        aToken.transferFrom(
            msg.sender,
            address(this),
            Math.min(
                aToken.balanceOf(msg.sender), params.maxCollateralToWithdraw
            )
        );

        uint256 withdrawn = withdraw(
            params.collateralToken, params.maxCollateralToWithdraw, msg.sender
        );

        // Transfer profit = swapped - repaid
        uint256 bal = IERC20(params.borrowToken).balanceOf(address(this));
        if (bal > 0) {
            IERC20(params.borrowToken).transfer(msg.sender, bal);
        }

        return (withdrawn, repayAmount, bal);
    }
}
