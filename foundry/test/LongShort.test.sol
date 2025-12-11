// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {
    POOL,
    ORACLE,
    WETH,
    DAI,
    UNISWAP_V3_POOL_FEE_DAI_WETH
} from "../src/Constants.sol";
import {IPool} from "../src/interfaces/aave-v3/IPool.sol";
import {
    IVariableDebtToken
} from "../src/interfaces/aave-v3/IVariableDebtToken.sol";
import {IAaveOracle} from "../src/interfaces/aave-v3/IAaveOracle.sol";
import {LongShort} from "@exercises/LongShort.sol";

contract LongShortTest is Test {
    IERC20 private constant weth = IERC20(WETH);
    IERC20 private constant dai = IERC20(DAI);
    IPool private constant pool = IPool(POOL);
    IAaveOracle private constant oracle = IAaveOracle(ORACLE);
    LongShort private target;

    function setUp() public {
        target = new LongShort();
    }

    function test_long_weth() public {
        IPool.ReserveData memory debtReserve = pool.getReserveData(DAI);

        // Test open
        console.log("--- open ---");
        IVariableDebtToken debtToken =
            IVariableDebtToken(debtReserve.variableDebtTokenAddress);
        debtToken.approveDelegation(address(target), type(uint256).max);

        uint256 collateralAmount = 1e18;
        uint256 borrowAmount = 1000 * 1e18;

        deal(WETH, address(this), collateralAmount);
        weth.approve(address(target), collateralAmount);

        bytes memory swapData = abi.encode(UNISWAP_V3_POOL_FEE_DAI_WETH);

        uint256 collateralAmountOut = target.open(
            LongShort.OpenParams({
                collateralToken: WETH,
                collateralAmount: collateralAmount,
                borrowToken: DAI,
                borrowAmount: borrowAmount,
                minHealthFactor: 1.5 * 1e18,
                minSwapAmountOut: 1,
                swapData: swapData
            })
        );

        console.log("Collateral amount out: %e", collateralAmountOut);
        assertGt(collateralAmountOut, 0, "collateral amount out = 0");
        assertEq(
            weth.balanceOf(address(this)),
            collateralAmountOut,
            "WETH balance of this contract"
        );
        assertEq(weth.balanceOf(address(target)), 0, "WETH balance of target");

        // Test close
        console.log("--- Close ---");
        IPool.ReserveData memory collateralReserve = pool.getReserveData(WETH);
        IERC20 aToken = IERC20(collateralReserve.aTokenAddress);
        aToken.approve(address(target), type(uint256).max);

        deal(DAI, address(this), 100 * 1e18);
        dai.approve(address(target), 100 * 1e18);

        uint256 wethBal = weth.balanceOf(address(this));
        weth.approve(address(target), wethBal);

        uint256[2] memory balsBefore =
            [weth.balanceOf(address(this)), dai.balanceOf(address(this))];

        (
            uint256 collateralWithdrawn,
            uint256 debtRepaidFromMsgSender,
            uint256 borrowedLeftover
        ) = target.close(
            LongShort.CloseParams({
                collateralToken: WETH,
                collateralAmount: wethBal,
                maxCollateralToWithdraw: type(uint256).max,
                borrowToken: DAI,
                maxDebtToRepay: type(uint256).max,
                minSwapAmountOut: 1,
                swapData: swapData
            })
        );

        uint256[2] memory balsAfter =
            [weth.balanceOf(address(this)), dai.balanceOf(address(this))];

        console.log("Collateral withdrawn: %e", collateralWithdrawn);
        console.log("Debt repaid from msg.sender : %e", debtRepaidFromMsgSender);
        console.log("Borrowed leftover: %e", borrowedLeftover);

        // Accounting for Aave rounding down
        assertGe(balsAfter[0], collateralAmount - 1, "WETH balance");
        assertGe(collateralWithdrawn, collateralAmount - 1, "WETH withdrawn");
        assertEq(
            balsAfter[1],
            balsBefore[1] - debtRepaidFromMsgSender + borrowedLeftover,
            "DAI balance"
        );
    }

    function test_short_weth() public {
        IPool.ReserveData memory debtReserve = pool.getReserveData(WETH);

        // Test open
        console.log("--- open ---");
        IVariableDebtToken debtToken =
            IVariableDebtToken(debtReserve.variableDebtTokenAddress);
        debtToken.approveDelegation(address(target), type(uint256).max);

        uint256 collateralAmount = 1000 * 1e18;
        uint256 borrowAmount = 0.1 * 1e18;

        deal(DAI, address(this), collateralAmount);
        dai.approve(address(target), collateralAmount);

        bytes memory swapData = abi.encode(UNISWAP_V3_POOL_FEE_DAI_WETH);

        uint256 collateralAmountOut = target.open(
            LongShort.OpenParams({
                collateralToken: DAI,
                collateralAmount: collateralAmount,
                borrowToken: WETH,
                borrowAmount: borrowAmount,
                minHealthFactor: 1.5 * 1e18,
                minSwapAmountOut: 1,
                swapData: swapData
            })
        );

        console.log("Collateral amount out: %e", collateralAmountOut);
        assertGt(collateralAmountOut, 0, "collateral amount out = 0");
        assertEq(
            dai.balanceOf(address(this)),
            collateralAmountOut,
            "DAI balance of this contract"
        );
        assertEq(dai.balanceOf(address(target)), 0, "DAI balance of target");

        // Test close
        console.log("--- Close ---");
        IPool.ReserveData memory collateralReserve = pool.getReserveData(DAI);
        IERC20 aToken = IERC20(collateralReserve.aTokenAddress);
        aToken.approve(address(target), type(uint256).max);

        deal(WETH, address(this), 1e18);
        weth.approve(address(target), 1e18);

        uint256 daiBal = dai.balanceOf(address(this));
        dai.approve(address(target), daiBal);

        uint256[2] memory balsBefore =
            [dai.balanceOf(address(this)), weth.balanceOf(address(this))];

        (
            uint256 collateralWithdrawn,
            uint256 debtRepaidFromMsgSender,
            uint256 borrowedLeftover
        ) = target.close(
            LongShort.CloseParams({
                collateralToken: DAI,
                collateralAmount: daiBal,
                maxCollateralToWithdraw: type(uint256).max,
                borrowToken: WETH,
                maxDebtToRepay: type(uint256).max,
                minSwapAmountOut: 1,
                swapData: swapData
            })
        );

        uint256[2] memory balsAfter =
            [dai.balanceOf(address(this)), weth.balanceOf(address(this))];

        console.log("Collateral withdrawn: %e", collateralWithdrawn);
        console.log("Debt repaid from msg.sender : %e", debtRepaidFromMsgSender);
        console.log("Borrowed leftover: %e", borrowedLeftover);

        // Accounting for Aave rounding down
        assertGe(balsAfter[0], collateralAmount - 1, "DAI balance");
        assertGe(collateralWithdrawn, collateralAmount - 1, "DAI withdrawn");
        assertEq(
            balsAfter[1],
            balsBefore[1] - debtRepaidFromMsgSender + borrowedLeftover,
            "WETH balance"
        );
    }
}
