// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20} from "mgv_src/MgvLib.sol";
import {AccessControlled} from "mgv_src/strategies/utils/AccessControlled.sol";

struct ArbParams {
    address taker;
    uint256 offerId;
    address wantsToken;
    uint256 wants;
    address givesToken;
    uint256 gives;
    uint24 fee;
}

contract MgvArbitrage is AccessControlled {
    IMangrove mgv;

    constructor(IMangrove _mgv, address admin) AccessControlled(admin) {
        mgv = _mgv;
    }

    ISwapRouter router = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    receive() external payable virtual {}

    function doArbitrage(ArbParams calldata params) external onlyAdmin returns (uint256 amountOut) {
        uint256[4][] memory targets = new uint[4][](1);
        targets[0] = [params.offerId, params.wants, params.gives, type(uint256).max];
        (uint256 successes, uint256 takerGot, uint256 takerGave,,) =
            mgv.snipesFor(params.wantsToken, params.givesToken, targets, false, params.taker);
        require(successes == 1, "MgvArbitrage/snipeFail");

        IERC20(params.wantsToken).transferFrom(params.taker, address(this), takerGot);
        ISwapRouter.ExactInputSingleParams memory uniswapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: params.wantsToken,
            tokenOut: params.givesToken,
            fee: params.fee,
            recipient: params.taker,
            deadline: type(uint256).max,
            amountIn: takerGot,
            amountOutMinimum: takerGave,
            sqrtPriceLimitX96: 0
        });
        amountOut = router.exactInputSingle(uniswapParams);
        require(amountOut >= takerGave, "MgvArbitrage/notProfitable");
    }

    function activateTokens(IERC20[] calldata tokens) external onlyAdmin {
        for (uint256 i = 0; i < tokens.length; ++i) {
            tokens[i].approve(address(router), type(uint256).max);
        }
    }
}
