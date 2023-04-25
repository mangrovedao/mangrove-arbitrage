// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20} from "mgv_src/MgvLib.sol";
import {AccessControlled} from "mgv_src/strategies/utils/AccessControlled.sol";


/// @param offerId The offer to be arbtraged
/// @param takerWantsToken The token the taker wants
/// @param takerWants The amount the taker wants
/// @param takerGivesToken The token the taker gives
/// @param takerGives The amount the taker gives
/// @param fee The fee used for the swap on Uniswap
/// @param minGain The minimum amount the abtriage needs to gain
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

    /// @param _mgv The Mangrove instance to be arbitraged
    /// @param admin The admin of the contract. The only address allowed to use the arbitrage functions.
    constructor(IMangrove _mgv, address admin) AccessControlled(admin) {
        mgv = _mgv;
    }

    /// @notice The router used to do the swap on Uniswap
    ISwapRouter router = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    receive() external payable virtual {}

    /// @notice This enables the admin to withdraw tokens from the contract.
    /// @param token The token to be withdrawn
    /// @param amount The amount to be withdrawn
    /// @param to The addrress the amount should be transferred to. 
    function withdrawToken(address token, uint256 amount, address to) external onlyAdmin returns (bool) {
        return IERC20(token).transfer(to, amount);
    }

    /// @notice This tries to snipe the offer on MGV and sell what it got on Uniswap
    /// It reverts if it is not profitable
    function doArbitrage(ArbParams calldata params) external onlyAdmin returns (uint256 amountOut) {
        uint256 givesBalance = IERC20(params.takerGivesToken).balanceOf(address(this)); // Important that this is done before any tranfers
        (uint256 takerGot, uint256 takerGave) = snipeOnMgv(params);
        amountOut = swapOnUniswap(params, takerGot, takerGave);
        checkGain( params.takerGivesToken, givesBalance, params.minGain);
    }

    /// @notice This tries do an initial exhange from the contracts current token, to the token need for the arbitrage, via Uniswap
    /// Then tries to snipe the offer on MGV and sell what it got on Uniswap
    /// At last it exchanges back to the contracts own token, via Uniswap
    /// It reverts if it is not profitable
    /// @param token The token need to do the arbitrage
    /// @param fee The fee on the pool to do the inital and final exchange
    function doArbitrageExchangeOnUniswap(ArbParams calldata params, address token, uint24 fee) external onlyAdmin returns (uint256 amountOut) {
        uint256 holdingTokenBalance = IERC20(token).balanceOf(address(this)); // Important that this is done before any tranfers
        preExchangeOnUniswap(params, token, fee);
        (uint256 takerGot, uint256 takerGave) = snipeOnMgv(params);
        amountOut = swapOnUniswap(params, takerGot, takerGave);
        postExchangeOnUniswap(params, token, fee, amountOut);
        checkGain( token, holdingTokenBalance, params.minGain);
    }

    /// @notice This tries do an initial exhange from the contracts current token, to the token need for the arbitrage, via MGV
    /// Then tries to snipe the offer on MGV and sell what it got on Uniswap
    /// At last it exchanges back to the contracts own token, via MGV
    /// It reverts if it is not profitable
    /// @param token The token need to do the arbitrage
    function doArbitrageExchangeOnMgv(ArbParams calldata params, address token) external onlyAdmin returns (uint256 amountOut) {
        uint256 holdingTokenBalance = IERC20(token).balanceOf(address(this)); // Important that this is done before any tranfers
        preExchangeOnMgv(params, token);
        (uint256 takerGot, uint256 takerGave) = snipeOnMgv(params);
        amountOut = swapOnUniswap(params, takerGot, takerGave);
        postExchangeOnMgv(params, token, amountOut);
        checkGain( token, holdingTokenBalance, params.minGain);
    }

    /// @notice This checks wether the gain has been positive and if the meets the minGain
    function checkGain(address takerGivesToken, uint256 givesBalance, uint256 minGain) view internal {
        uint balance = IERC20(takerGivesToken).balanceOf(address(this));
        require(balance > givesBalance, "MgvArbitrage/notProfitable");
        require(balance - givesBalance > minGain, "MgvArbitrage/notMinGain");
    }

    /// @notice This swaps the opposite of the Mangrove offer. 
    /// @param takerGot the amount the taker got from Mangrove
    /// @param takerGave the amount the taker gave to Mangrove 
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

    /// @notice This snipes the specified offer on Mangrove 
    function snipeOnMgv(ArbParams calldata params) internal returns (uint256, uint256) {
        uint256[4][] memory targets = new uint[4][](1);
        targets[0] = [params.offerId, params.takerWants, params.takerGives, type(uint256).max];
        (uint256 successes, uint256 takerGot, uint256 takerGave,,) =
            mgv.snipes(params.takerWantsToken, params.takerGivesToken, targets, false);
        require(successes == 1, "MgvArbitrage/snipeFail");
        return (takerGot, takerGave);
    }

    /// @notice this exchanges, on Uniswap, from the token the contract gain from the arbitrage, to the token the contract is holding
    /// @param token the token the contract is holding
    /// @param fee the fee used for the swap on Uniswap
    /// @param amountOut The amount received from the arbitrage
    function postExchangeOnUniswap(ArbParams calldata params, address token, uint24 fee, uint256 amountOut) internal {
        if (token != address(0) && token != params.takerGivesToken) {
            ISwapRouter.ExactInputSingleParams memory exhcangeParams = ISwapRouter.ExactInputSingleParams({
                tokenIn: params.takerGivesToken,
                tokenOut: token,
                fee: fee,
                recipient: address(this),
                deadline: type(uint256).max,
                amountIn: amountOut,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
            router.exactInputSingle(exhcangeParams);
        }
    }

    /// @notice this exchanges, on Mangrove, from the token the contract gain from the arbitrage, to the token the contract is holding
    /// @param token the token the contract is holding
    /// @param amountOut The amount received from the arbitrage
    function postExchangeOnMgv(ArbParams calldata params, address token, uint256 amountOut)
        internal
        returns (uint256)
    {
        if (token != address(0) && token != params.takerGivesToken) {
            (, uint takerGave,,) = mgv.marketOrder({
                outbound_tkn: token,
                inbound_tkn: params.takerGivesToken,
                takerWants: 0,
                takerGives: amountOut,
                fillWants: false
            });
            require(takerGave == amountOut, "MgvArbitrage/notEnoughOnMgv");
        }
        return 0;
    }

    /// @notice this exchanges, on Uniswap, from the token the contract is holding, to the token the contract needs for the arbitrage
    /// @param token the token the contract is holding
    /// @param fee the fee used for the swap on Uniswap
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

    /// @notice this exchanges, on Mangrove, from the token the contract is holding, to the token the contract need for the arbitrage
    /// @param token the token the contract is holding
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

    /// @notice This approves all the neccesary tokens on Mangrove and the Uniswap router
    function activateTokens(IERC20[] calldata tokens) external onlyAdmin {
        for (uint256 i = 0; i < tokens.length; ++i) {
            tokens[i].approve(address(mgv), type(uint256).max);
            tokens[i].approve(address(router), type(uint256).max);
        }
    }
}
