// SPDX-License-Identifier:	AGPL-3.0

pragma solidity =0.5.16;

import {UniswapV2Factory} from '@uniswap/v2-core/contracts/UniswapV2Factory.sol';

contract MyUniswapFactory is UniswapV2Factory {

    constructor( address _feeToSetter) public  UniswapV2Factory(_feeToSetter){  }

}