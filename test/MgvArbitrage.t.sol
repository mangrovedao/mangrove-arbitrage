// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {MangroveTest} from "mgv_test/lib/MangroveTest.sol";

import {PolygonFork, PinnedPolygonFork} from "mgv_test/lib/forks/Polygon.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";
import {IERC20} from "mgv_src/MgvLib.sol";
import "src/MgvArbitrage.sol";


contract MgvArbitrageTest is MangroveTest {

  PolygonFork fork;
  MgvArbitrage arbStrat;
  IERC20 WETH;
  IERC20 USDC;

  address payable taker;
  address payable seller;

  receive() external payable virtual {}

  function setUp() public override {
    // use the pinned Polygon fork
    fork = new PinnedPolygonFork(); // use polygon fork to use dai, usdc and weth addresses
    fork.setUp();
    mgv = setupMangrove();
    WETH = IERC20(fork.get("WETH"));
    USDC = IERC20(fork.get("USDC"));
    setupMarket(WETH, USDC); 

    taker = freshAddress();
    fork.set("taker", taker);
    seller = freshAddress();
    fork.set("seller", seller);

    deal(taker, 10 ether);
    deal( $(USDC), taker, cash(USDC, 20000));
    deal(seller, 10 ether);
    deal( $(WETH), seller,cash(WETH, 10));

    vm.startPrank(taker);
    USDC.approve($(mgv), type(uint).max);
    WETH.approve($(mgv), type(uint).max);
    vm.stopPrank();

    vm.startPrank(seller);
    WETH.approve(address(mgv), type(uint).max); 
    vm.stopPrank();

    deployStrat();
  }

  function deployStrat() public {
    arbStrat = new MgvArbitrage({
      _mgv: IMangrove($(mgv)),
      admin: address(this)
      });
    fork.set("MgvArbitrage", address(arbStrat));

    vm.startPrank(taker);
    mgv.approve($(WETH), $(USDC), address(arbStrat), type(uint).max); 
    mgv.approve($(USDC), $(WETH), address(arbStrat), type(uint).max); 
    WETH.approve(address(arbStrat), type(uint).max);
    vm.stopPrank();
    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = WETH;
    tokens[1] = USDC;

    arbStrat.activateTokens(tokens);
  }

  function test_isProfitable() public {
    vm.prank(seller);
    uint offerId = mgv.newOffer{value: 1 ether}({
    outbound_tkn: $(WETH),
    inbound_tkn: $(USDC),
    wants: cash(USDC, 1000),
    gives: cash(WETH, 1),
    gasreq: 50_000 ,
    gasprice: 0,
    pivotId: 0
    });

    ArbParams memory params = ArbParams( { 
        taker:taker, 
        offerId: offerId, 
        wantsToken: $(WETH), 
        wants: cash(USDC, 1000), 
        givesToken:$(USDC), 
        gives:cash(WETH, 1), 
        fee: 3000 } );

    uint usdcBalanceBefore = USDC.balanceOf(taker);
    uint wethBalanceBefore = WETH.balanceOf(taker);
    vm.prank(taker);
    uint amountOut = arbStrat.doArbitrage( params );
    uint usdcBalanceAfter = USDC.balanceOf(taker);
    uint wethBalanceAfter = WETH.balanceOf(taker);
    assertTrue( usdcBalanceAfter > usdcBalanceBefore, "Should have increased usdcBalance " );
    assertTrue( wethBalanceAfter == wethBalanceBefore, "Should have the same wethBalance" );
    assertTrue( amountOut > params.wants, "Amount out should be larger than the initial offer on Mangrove" );
  }

    function test_isNotProfitable() public {
    vm.prank(seller);
    uint offerId = mgv.newOffer{value: 1 ether}({
    outbound_tkn: $(WETH),
    inbound_tkn: $(USDC),
    wants: cash(USDC, 10000),
    gives: cash(WETH, 1),
    gasreq: 50_000 ,
    gasprice: 0,
    pivotId: 0
    });

    ArbParams memory params = ArbParams( { 
        taker:taker, 
        offerId: offerId, 
        wantsToken: $(WETH), 
        wants: cash(USDC, 1000), 
        givesToken:$(USDC), 
        gives:cash(WETH, 1), 
        fee: 3000 } );

    vm.prank(taker);
    vm.expectRevert("Too little received");
    arbStrat.doArbitrage( params );
    
  }

}
