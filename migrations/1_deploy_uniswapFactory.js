var UniswapV2Factory = artifacts.require("MyUniswapFactory");
var LiquidityValueCalculator = artifacts.require("LiquidityValueCalculator");
require('dotenv').config({ path: require('find-config')('.env') })

module.exports = function(deployer) {
  // deployment steps
  const feeSetter = process.env.FEESETTER;
  if(!feeSetter){
    throw new Error("Missing FeeSettter")
  }
  deployer.deploy(UniswapV2Factory, feeSetter).then( function () {;
   return deployer.deploy(LiquidityValueCalculator, UniswapV2Factory.address);
  });

  
  
};
