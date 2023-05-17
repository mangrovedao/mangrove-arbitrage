// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MangroveDeployer} from "mgv_script/MangroveDeployer.s.sol";
import {MangroveOrderDeployer} from "mgv_script/strategies/mangroveOrder/MangroveOrderDeployer.s.sol";
import {ActivateMarket} from "mgv_script/ActivateMarket.s.sol";
import {MgvArbitrage} from "src/MgvArbitrage.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";

contract MgvArbitrageDeployer is Deployer {
  function run() public {
    innerRun({admin: broadcaster(), arbitrager: envAddressOrName("ARBITRAGER")});
    outputDeployment();
  }

  function innerRun(address admin, address arbitrager) public {
    MangroveDeployer mgvDeployer = new MangroveDeployer();
    mgvDeployer.innerRun({chief: admin, gasprice: 1, gasmax: 2_000_000});
    address mgv = address(mgvDeployer.mgv());
    ActivateMarket activateMarket = new ActivateMarket();
    address weth = fork.get("WETH");
    address dai = fork.get("DAI");
    address usdc = fork.get("USDC");
    activateMarket.innerRun(dai, usdc, 1e9 / 1000, 1e9 / 1000, 0);
    activateMarket.innerRun(weth, dai, 1e9, 1e9 / 1000, 0);
    activateMarket.innerRun(weth, usdc, 1e9, 1e9 / 1000, 0);

    MangroveOrderDeployer mgoeDeployer = new MangroveOrderDeployer();
    mgoeDeployer.innerRun({admin: admin, mangrove: mgv});

    broadcast();
    MgvArbitrage mgvArb = new MgvArbitrage(IMangrove(payable(mgv)), admin, arbitrager);
    fork.set("MgvArbitrage", address(mgvArb));
  }
}
