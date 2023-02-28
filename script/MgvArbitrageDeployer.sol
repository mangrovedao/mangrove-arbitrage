// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MangroveDeployer} from "mgv_script/MangroveDeployer.s.sol";
import {ActivateMarket} from "mgv_script/ActivateMarket.s.sol";
import {MgvArbitrage} from "src/MgvArbitrage.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";


contract MgvArbitrageDeployer is Deployer {

  function run() public {
    innerRun({admin: broadcaster(), mgv: envAddressOrName("MANGROVE")});
    outputDeployment();
  }

    function innerRun(address admin, address mgv) public {
        MangroveDeployer mgvDeployer = new MangroveDeployer();
        mgvDeployer.innerRun({chief: admin, gasprice: 1, gasmax: 2_000_000});

        ActivateMarket activateMarket = new ActivateMarket();
        address weth = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
        address dai = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
        activateMarket.innerRun(weth, dai, 1e9, 1e9 / 1000, 0);

        
        broadcast();
        MgvArbitrage mgvArb = new MgvArbitrage(IMangrove(payable(mgv)), admin);
        fork.set("MgvArbitrage", address(mgvArb));
    }
}