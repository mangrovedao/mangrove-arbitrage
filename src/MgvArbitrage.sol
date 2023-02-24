// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20} from "mgv_src/MgvLib.sol";
import {AccessControlled} from "mgv_src/strategies/utils/AccessControlled.sol";

enum Exchange {
    MANGROVE,
    UNISWAP,
    NONE
}

struct ArbParams {
    uint256 offerId;
    address takerWantsToken;
    uint256 takerWants;
    address takerGivesToken;
    uint256 takerGives;
    uint24 fee;
    uint256 minGain;
}


contract MgvArbitrage is AccessControlled {
    IMangrove mgv;

    constructor(IMangrove _mgv, address admin) AccessControlled(admin) {
        mgv = _mgv;
    }

    ISwapRouter router = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    receive() external payable virtual {}

    uint256 public MAX_GASREQ = 350000;

    function withdrawToken(address token, uint256 amount, address to) external onlyAdmin returns (bool) {
        return IERC20(token).transfer(to, amount);
    }

    function doArbitrageExchangeOnUniswap(ArbParams calldata params, address token, uint24 fee) external onlyAdmin returns (uint256 amountOut) {
        uint256 givesBalance = IERC20(params.takerGivesToken).balanceOf(address(this)); // Important that this is done before any tranfers
        uint256 amountIn = preExchangeOnUniswap(params, token, fee);
        (uint256 takerGot, uint256 takerGave) = snipeOnMgv(params);
        amountOut = swapOnUniswap(params, takerGot, takerGave);
        postExchangeOnUniswap(params, token, fee, amountIn);
        checkGain( params.takerGivesToken, givesBalance, params.minGain);
    }

    function doArbitrageExchangeOnMgv(ArbParams calldata params, address token) external onlyAdmin returns (uint256 amountOut) {
        uint256 givesBalance = IERC20(params.takerGivesToken).balanceOf(address(this)); // Important that this is done before any tranfers
        uint256 amountIn = preExchangeOnMgv(params, token);
        (uint256 takerGot, uint256 takerGave) = snipeOnMgv(params);
        amountOut = swapOnUniswap(params, takerGot, takerGave);
        postExchangeOnMgv(params, token, amountIn);
        checkGain( params.takerGivesToken, givesBalance, params.minGain);
    }

    function doArbitrage(ArbParams calldata params) external onlyAdmin returns (uint256 amountOut) {
        uint256 givesBalance = IERC20(params.takerGivesToken).balanceOf(address(this)); // Important that this is done before any tranfers
        (uint256 takerGot, uint256 takerGave) = snipeOnMgv(params);
        amountOut = swapOnUniswap(params, takerGot, takerGave);
        checkGain( params.takerGivesToken, givesBalance, params.minGain);
    }

    function checkGain(address takerGivesToken, uint256 givesBalance, uint256 minGain) view internal {
        require(IERC20(takerGivesToken).balanceOf(address(this)) > givesBalance, "MgvArbitrage/notProfitable");
        require(IERC20(takerGivesToken).balanceOf(address(this)) - givesBalance > minGain, "MgvArbitrage/notMinGain");
    }

    function swapOnUniswap(ArbParams calldata params, uint256 takerGot, uint256 takerGave)
        internal
        returns (uint256 amountOut)
    {
        ISwapRouter.ExactInputSingleParams memory uniswapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: params.takerWantsToken,
            tokenOut: params.takerGivesToken,
            fee: params.fee,
            recipient: address(this),
            deadline: type(uint256).max,
            amountIn: takerGot,
            amountOutMinimum: takerGave,
            sqrtPriceLimitX96: 0
        });
        amountOut = router.exactInputSingle(uniswapParams);
        require(amountOut >= takerGave, "MgvArbitrage/notProfitable");
    }

    function snipeOnMgv(ArbParams calldata params) internal returns (uint256, uint256) {
        uint256[4][] memory targets = new uint[4][](1);
        targets[0] = [params.offerId, params.takerWants, params.takerGives, type(uint256).max];
        (uint256 successes, uint256 takerGot, uint256 takerGave,,) =
            mgv.snipes(params.takerWantsToken, params.takerGivesToken, targets, false);
        require(successes == 1, "MgvArbitrage/snipeFail");
        return (takerGot, takerGave);
    }

    function postExchangeOnUniswap(ArbParams calldata params, address token, uint24 fee, uint256 amountIn) internal {
        if (token != address(0) && token != params.takerGivesToken) {
            ISwapRouter.ExactOutputSingleParams memory exhcangeParams = ISwapRouter.ExactOutputSingleParams({
                tokenIn: params.takerGivesToken,
                tokenOut: token,
                fee: fee,
                recipient: address(this),
                deadline: type(uint256).max,
                amountOut: amountIn,
                amountInMaximum: type(uint256).max,
                sqrtPriceLimitX96: 0
            });
            router.exactOutputSingle(exhcangeParams);
        }
    }

    function postExchangeOnMgv(ArbParams calldata params, address token, uint256 amountIn)
        internal
        returns (uint256)
    {
        if (token != address(0) && token != params.takerGivesToken) {
            (uint256 takerGot,,,) = mgv.marketOrder({
                outbound_tkn: token,
                inbound_tkn: params.takerGivesToken,
                takerWants: amountIn,
                takerGives: type(uint160).max,
                fillWants: true
            });
            require(takerGot == amountIn, "MgvArbitrage/notEnoughOnMgv");
        }
        return 0;
    }

    function preExchangeOnUniswap(ArbParams calldata params, address token, uint24 fee) internal returns (uint256) {
        if (token != address(0) && token != params.takerGivesToken) {
            ISwapRouter.ExactOutputSingleParams memory exhcangeParams = ISwapRouter.ExactOutputSingleParams({
                tokenIn: token,
                tokenOut: params.takerGivesToken,
                fee: fee,
                recipient: address(this),
                deadline: type(uint256).max,
                amountOut: params.takerGives,
                amountInMaximum: IERC20(token).balanceOf(address(this)),
                sqrtPriceLimitX96: 0
            });
            return router.exactOutputSingle(exhcangeParams);
        }
        return 0;
    }

    function preExchangeOnMgv(ArbParams calldata params, address token) internal returns (uint256) {
        if (token != address(0) && token != params.takerGivesToken) {
            (uint256 takerGot, uint256 takerGave,,) = mgv.marketOrder({
                outbound_tkn: params.takerGivesToken,
                inbound_tkn: token,
                takerWants: params.takerGives,
                takerGives: IERC20(token).balanceOf(address(this)),
                fillWants: true
            });
            require(takerGot == params.takerGives, "MgvArbitrage/notEnoughOnMgv");
            return takerGave;
        }
        return 0;
    }

    function activateTokens(IERC20[] calldata tokens) external onlyAdmin {
        for (uint256 i = 0; i < tokens.length; ++i) {
            tokens[i].approve(address(mgv), type(uint256).max);
            tokens[i].approve(address(router), type(uint256).max);
        }
    }
}
