// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./PoolFactory.sol";

import "./interfaces/IERC20.sol";
import "./interfaces/IUniswapV3Pool.sol";
import "./interfaces/IUniswapV3Manager.sol";

import "./lib/LiquidityMath.sol";
import "./lib/Path.sol";
import "./lib/PoolAddress.sol";
import "./lib/TickMath.sol";
import "./lib/console.sol";

contract SwapManager is IUniswapV3Manager {
    event Log(string message, uint24 data);
    using Path for bytes;

    error SlippageCheckFailed(uint256 amount0, uint256 amount1);
    error TooLittleReceived(uint256 amountOut);

    address public immutable factory;

    PoolFactory fact;

    constructor(address factory_) {
        factory = factory_;
        fact = PoolFactory(factory);
    }

    function getPosition(
        GetPositionParams calldata params
    )
        public
        view
        returns (
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        IUniswapV3Pool pool = getPool(params.tokenA, params.tokenB, params.fee);

        (
            liquidity,
            feeGrowthInside0LastX128,
            feeGrowthInside1LastX128,
            tokensOwed0,
            tokensOwed1
        ) = pool.positions(
            keccak256(
                abi.encodePacked(
                    params.owner,
                    params.lowerTick,
                    params.upperTick
                )
            )
        );
    }

    function swapSingle(
        SwapSingleParams calldata params
    ) public returns (uint256 amountOut) {
        amountOut = _swap(
            params.amountIn,
            msg.sender,
            params.sqrtPriceLimitX96,
            SwapCallbackData({
                path: abi.encodePacked(
                    params.tokenIn,
                    params.fee,
                    params.tokenOut
                ),
                payer: msg.sender
            })
        );
    }

    function swap(SwapParams memory params) public returns (uint256 amountOut) {
        address payer = msg.sender;
        bool hasMultiplePools;

        while (true) {
            hasMultiplePools = params.path.hasMultiplePools();

            params.amountIn = _swap(
                params.amountIn,
                hasMultiplePools ? address(this) : params.recipient,
                0,
                SwapCallbackData({
                    path: params.path.getFirstPool(),
                    payer: payer
                })
            );

            if (hasMultiplePools) {
                payer = address(this);
                params.path = params.path.skipToken();
            } else {
                amountOut = params.amountIn;
                break;
            }
        }

        if (amountOut < params.minAmountOut)
            revert TooLittleReceived(amountOut);
    }

    function _swap(
        uint256 amountIn,
        address recipient,
        uint160 sqrtPriceLimitX96,
        SwapCallbackData memory data
    ) internal returns (uint256 amountOut) {
        (address tokenIn, address tokenOut, uint24 fee) = data
            .path
            .decodeFirstPool();

        bool zeroForOne = tokenIn < tokenOut;

        (int256 amount0, int256 amount1) = getPool(tokenIn, tokenOut, fee).swap(
            recipient,
            zeroForOne,
            amountIn,
            sqrtPriceLimitX96 == 0
                ? (
                    zeroForOne
                        ? TickMath.MIN_SQRT_RATIO + 1
                        : TickMath.MAX_SQRT_RATIO - 1
                )
                : sqrtPriceLimitX96,
            abi.encode(data)
        );

        amountOut = uint256(-(zeroForOne ? amount1 : amount0));
    }

    function getPool(
        address token0,
        address token1,
        uint24 fee
    ) internal view returns (IUniswapV3Pool pool) {
        (token0, token1) = token0 < token1
            ? (token0, token1)
            : (token1, token0);
        pool = IUniswapV3Pool(
            PoolAddress.computeAddress(factory, token0, token1, fee)
        );
    }

    function uniswapV3SwapCallback(
        int256 amount0,
        int256 amount1,
        bytes calldata data_
    ) public {
        SwapCallbackData memory data = abi.decode(data_, (SwapCallbackData));
        (address tokenIn, address tokenOut, ) = data.path.decodeFirstPool();

        bool zeroForOne = tokenIn < tokenOut;

        int256 amount = zeroForOne ? amount0 : amount1;

        if (data.payer == address(this)) {
            IERC20(tokenIn).transfer(msg.sender, uint256(amount));
        } else {
            IERC20(tokenIn).transferFrom(
                data.payer,
                msg.sender,
                uint256(amount)
            );
        }
    }
}
