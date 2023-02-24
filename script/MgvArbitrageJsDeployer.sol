// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Deployer} from "@mangrovedao/mangrove-core/script/lib/Deployer.sol";
import {MgvArbitrage} from "src/MgvArbitrage.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract MgvArbitrageJsDeployer is Deployer, StdCheats {
    function run() public {
        innerRun({admin: broadcaster(), mgv: envAddressOrName("MANGROVE"), token: envAddressOrName("ArbToken")});
        outputDeployment();
    }

    function innerRun(address admin, address mgv, address token) public {
        broadcast();
        MgvArbitrage mgvArb = new MgvArbitrage(IMangrove(payable(mgv)), admin);
        fork.set("MgvArbitrage", address(mgvArb));
        deal(token, address(mgvArb), 10000);
    }
}
