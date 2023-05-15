// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {MangroveTest} from "mgv_test/lib/MangroveTest.sol";

import {PinnedPolygonFork} from "src/MyPinnedPolygon.sol"; // have to use ar polygon fork on a newer block
// import {PinnedPolygonFork} from "mgv_test/lib/forks/Polygon.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";
import {IERC20} from "mgv_src/MgvLib.sol";
import "src/MgvArbitrage.sol";

contract MgvArbitrageTest is MangroveTest {
  PinnedPolygonFork fork;
  MgvArbitrage arbStrat;
  IERC20 WETH;
  IERC20 USDC;
  IERC20 DAI;

  address payable taker;
  address payable seller;
  address payable lp;

  receive() external payable virtual {}

  function setUp() public override {
    // use the pinned Polygon fork
    fork = new PinnedPolygonFork(); // use polygon fork to use dai, usdc and weth addresses
    fork.setUp();
    mgv = setupMangrove();
    WETH = IERC20(fork.get("WETH"));
    USDC = IERC20(fork.get("USDC"));
    DAI = IERC20(fork.get("DAI"));
    setupMarket(WETH, USDC);
    setupMarket(DAI, USDC);

    taker = freshAddress();
    fork.set("taker", taker);
    seller = freshAddress();
    fork.set("seller", seller);
    lp = freshAddress();
    fork.set("lp", lp);

    deal($(USDC), lp, cash(USDC, 100000));
    deal($(DAI), lp, cash(DAI, 100000));
    deal(taker, 10 ether);
    deal(seller, 10 ether);
    deal(lp, 10 ether);

    vm.startPrank(taker);
    USDC.approve($(mgv), type(uint).max);
    WETH.approve($(mgv), type(uint).max);
    vm.stopPrank();

    vm.startPrank(lp);
    mgv.newOffer{value: 1 ether}({
      outbound_tkn: $(USDC),
      inbound_tkn: $(DAI),
      wants: cash(DAI, 10000),
      gives: cash(USDC, 10000),
      gasreq: 50_000,
      gasprice: 0,
      pivotId: 0
    });
    mgv.newOffer({
      outbound_tkn: $(DAI),
      inbound_tkn: $(USDC),
      wants: cash(USDC, 10000),
      gives: cash(DAI, 10000),
      gasreq: 50_000,
      gasprice: 0,
      pivotId: 0
    });
    USDC.approve($(mgv), type(uint).max);
    DAI.approve($(mgv), type(uint).max);
    vm.stopPrank();

    vm.prank(seller);
    WETH.approve(address(mgv), type(uint).max);

    deployStrat();
  }

  function deployStrat() public {
    arbStrat = new MgvArbitrage({
      _mgv: IMangrove($(mgv)),
      admin: address(this)
      });
    fork.set("MgvArbitrage", address(arbStrat));

    vm.startPrank(taker);
    WETH.approve(address(arbStrat), type(uint).max);
    vm.stopPrank();
    IERC20[] memory tokens = new IERC20[](3);
    tokens[0] = WETH;
    tokens[1] = USDC;
    tokens[2] = DAI;

    arbStrat.activateTokens(tokens);
  }

  function test_isProfitable() public {
    deal($(USDC), address(arbStrat), cash(USDC, 20000));
    deal($(WETH), seller, cash(WETH, 10));
    vm.prank(seller);
    uint offerId = mgv.newOffer{value: 1 ether}({
      outbound_tkn: $(WETH),
      inbound_tkn: $(USDC),
      wants: cash(USDC, 1000),
      gives: cash(WETH, 1),
      gasreq: 50_000,
      gasprice: 0,
      pivotId: 0
    });

    ArbParams memory params = ArbParams({
      offerId: offerId,
      takerWantsToken: $(WETH),
      takerWants: cash(WETH, 1),
      takerGivesToken: $(USDC),
      takerGives: cash(USDC, 1000),
      fee: 3000,
      minGain: 0
    });

    uint usdcBalanceBefore = USDC.balanceOf(address(arbStrat));
    uint wethBalanceBefore = WETH.balanceOf(address(arbStrat));
    uint amountOut = arbStrat.doArbitrage(params);
    uint usdcBalanceAfter = USDC.balanceOf(address(arbStrat));
    uint wethBalanceAfter = WETH.balanceOf(address(arbStrat));
    assertTrue(usdcBalanceAfter > usdcBalanceBefore, "Should have increased usdcBalance ");
    assertTrue(wethBalanceAfter == wethBalanceBefore, "Should have the same wethBalance");
    assertTrue(amountOut > params.takerGives, "Amount out should be larger than the initial offer on Mangrove");
  }

  function test_isNotProfitable() public {
    deal($(USDC), address(arbStrat), cash(USDC, 20000));
    deal($(WETH), seller, cash(WETH, 10));
    vm.prank(seller);
    uint offerId = mgv.newOffer{value: 1 ether}({
      outbound_tkn: $(WETH),
      inbound_tkn: $(USDC),
      wants: cash(USDC, 10000),
      gives: cash(WETH, 1),
      gasreq: 50_000,
      gasprice: 0,
      pivotId: 0
    });

    ArbParams memory params = ArbParams({
      offerId: offerId,
      takerWantsToken: $(WETH),
      takerWants: cash(WETH, 1),
      takerGivesToken: $(USDC),
      takerGives: cash(USDC, 10000),
      fee: 3000,
      minGain: 0
    });

    vm.expectRevert("Too little received");
    arbStrat.doArbitrage(params);
  }

  function test_offerFailedOnMangrove() public {
    deal($(USDC), address(arbStrat), cash(USDC, 20000));
    vm.prank(seller);
    uint offerId = mgv.newOffer{value: 1 ether}({
      outbound_tkn: $(WETH),
      inbound_tkn: $(USDC),
      wants: cash(USDC, 1000),
      gives: cash(WETH, 1),
      gasreq: 50_000,
      gasprice: 0,
      pivotId: 0
    });

    ArbParams memory params = ArbParams({
      offerId: offerId,
      takerWantsToken: $(WETH),
      takerWants: cash(WETH, 1),
      takerGivesToken: $(USDC),
      takerGives: cash(USDC, 1000),
      fee: 3000,
      minGain: 0
    });

    vm.expectRevert("MgvArbitrage/snipeFail");
    arbStrat.doArbitrage(params);
  }

  function test_isProfitable_exchangeDaiCurrency_Uniswap() public {
    deal($(DAI), address(arbStrat), cash(DAI, 2000));
    deal($(WETH), seller, cash(WETH, 10));
    vm.prank(seller);
    uint offerId = mgv.newOffer{value: 1 ether}({
      outbound_tkn: $(WETH),
      inbound_tkn: $(USDC),
      wants: cash(USDC, 1000),
      gives: cash(WETH, 1),
      gasreq: 50_000,
      gasprice: 0,
      pivotId: 0
    });

    ArbParams memory params = ArbParams({
      offerId: offerId,
      takerWantsToken: $(WETH),
      takerWants: cash(WETH, 1),
      takerGivesToken: $(USDC),
      takerGives: cash(USDC, 1000),
      fee: 3000,
      minGain: 0
    });

    uint usdcBalanceBefore = USDC.balanceOf(address(arbStrat));
    uint wethBalanceBefore = WETH.balanceOf(address(arbStrat));
    uint daiBalanceBefore = DAI.balanceOf(address(arbStrat));
    uint amountOut = arbStrat.doArbitrageExchangeOnUniswap(params, address(DAI), 100);
    uint daiBalanceAfter = DAI.balanceOf(address(arbStrat));
    uint usdcBalanceAfter = USDC.balanceOf(address(arbStrat));
    uint wethBalanceAfter = WETH.balanceOf(address(arbStrat));
    assertEq(usdcBalanceAfter, usdcBalanceBefore, "Should have the same usdcBalance ");
    assertEq(wethBalanceAfter, wethBalanceBefore, "Should have the same wethBalance");
    assertGt(daiBalanceAfter, daiBalanceBefore, "Should have increased daiBalance");
    assertGt(amountOut, params.takerGives, "Amount out should be larger than the initial offer on Mangrove");
  }

  function test_isNotProfitable_exchangeDaiCurrency_Uniswap() public {
    deal($(DAI), address(arbStrat), cash(DAI, 2000));
    deal($(WETH), seller, cash(WETH, 10));
    vm.prank(seller);
    uint offerId = mgv.newOffer{value: 1 ether}({
      outbound_tkn: $(WETH),
      inbound_tkn: $(USDC),
      wants: cash(USDC, 1000),
      gives: cash(WETH, 1),
      gasreq: 50_000,
      gasprice: 0,
      pivotId: 0
    });

    ArbParams memory params = ArbParams({
      offerId: offerId,
      takerWantsToken: $(WETH),
      takerWants: cash(WETH, 1),
      takerGivesToken: $(USDC),
      takerGives: cash(USDC, 1000),
      fee: 3000,
      minGain: cash(DAI, 1000)
    });

    vm.expectRevert("MgvArbitrage/notMinGain");
    arbStrat.doArbitrageExchangeOnUniswap(params, address(DAI), 100);
  }

  function test_isProfitable_exchangeDaiCurrency_Mgv() public {
    deal($(DAI), address(arbStrat), cash(DAI, 2000));
    deal($(WETH), seller, cash(WETH, 10));
    vm.prank(seller);
    uint offerId = mgv.newOffer{value: 1 ether}({
      outbound_tkn: $(WETH),
      inbound_tkn: $(USDC),
      wants: cash(USDC, 1000),
      gives: cash(WETH, 1),
      gasreq: 50_000,
      gasprice: 0,
      pivotId: 0
    });

    ArbParams memory params = ArbParams({
      offerId: offerId,
      takerWantsToken: $(WETH),
      takerWants: cash(WETH, 1),
      takerGivesToken: $(USDC),
      takerGives: cash(USDC, 1000),
      fee: 3000,
      minGain: 0
    });

    uint usdcBalanceBefore = USDC.balanceOf(address(arbStrat));
    uint wethBalanceBefore = WETH.balanceOf(address(arbStrat));
    uint daiBalanceBefore = DAI.balanceOf(address(arbStrat));
    uint amountOut = arbStrat.doArbitrageExchangeOnMgv(params, address(DAI));
    uint daiBalanceAfter = DAI.balanceOf(address(arbStrat));
    uint usdcBalanceAfter = USDC.balanceOf(address(arbStrat));
    uint wethBalanceAfter = WETH.balanceOf(address(arbStrat));
    assertEq(usdcBalanceAfter, usdcBalanceBefore, "Should have the same usdcBalance ");
    assertEq(wethBalanceAfter, wethBalanceBefore, "Should have the same wethBalance");
    assertGt(daiBalanceAfter, daiBalanceBefore, "Should have increased daiBalance");
    assertGt(amountOut, params.takerGives, "Amount out should be larger than the initial offer on Mangrove");
  }

  function test_isNotProfitable_exchangeDaiCurrency_Mgv() public {
    deal($(DAI), address(arbStrat), cash(DAI, 2000));
    deal($(WETH), seller, cash(WETH, 10));
    vm.prank(seller);
    uint offerId = mgv.newOffer{value: 1 ether}({
      outbound_tkn: $(WETH),
      inbound_tkn: $(USDC),
      wants: cash(USDC, 1000),
      gives: cash(WETH, 1),
      gasreq: 50_000,
      gasprice: 0,
      pivotId: 0
    });

    ArbParams memory params = ArbParams({
      offerId: offerId,
      takerWantsToken: $(WETH),
      takerWants: cash(WETH, 1),
      takerGivesToken: $(USDC),
      takerGives: cash(USDC, 1000),
      fee: 3000,
      minGain: cash(DAI, 1000)
    });

    vm.expectRevert("MgvArbitrage/notMinGain");
    arbStrat.doArbitrageExchangeOnMgv(params, address(DAI));
  }

  function test_canWithdrawToken() public {
    uint daiAmount = cash(DAI, 2000);
    deal($(DAI), address(arbStrat), daiAmount);
    uint sellerDaiBalance = DAI.balanceOf(address(seller));
    arbStrat.withdrawToken($(DAI), daiAmount, address(seller));
    assertEq(DAI.balanceOf(address(seller)) - sellerDaiBalance, daiAmount, "Should have withdrawn the DAI");
  }

  function test_canWithdrawNative() public {
    deal(address(arbStrat), 10 ether);
    uint sellerNativeBalance = address(seller).balance;
    arbStrat.withdrawNative(10 ether, address(seller));
    assertEq(address(seller).balance - sellerNativeBalance, 10 ether, "Should have withdrawn the Native");
  }
}
