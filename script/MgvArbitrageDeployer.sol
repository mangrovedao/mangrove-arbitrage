// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Deployer} from "@mangrovedao/mangrove-core/script/lib/Deployer.sol";
import {MgvArbitrage} from "src/MgvArbitrage.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";


contract MgvArbitrageDeployer is Deployer {

  function run() public {
    innerRun({admin: broadcaster(), mgv: envAddressOrName("MANGROVE")});
    outputDeployment();
  }

    function innerRun(address admin, address mgv) public {
        broadcast();
        MgvArbitrage mgvArb = new MgvArbitrage(IMangrove(payable(mgv)), admin);
        fork.set("MgvArbitrage", address(mgvArb));
    }
}