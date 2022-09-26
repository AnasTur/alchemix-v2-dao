// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "./BaseTest.sol";

contract VotingTest is BaseTest {
    VotingEscrow veALCX;
    Voter voter;
    GaugeFactory gaugeFactory;
    BribeFactory bribeFactory;
    RewardsDistributor distributor;
    Minter minter;

    uint256 depositAmount = 999 ether;
    uint256 lockTime = 30 days;

    function setUp() public {
        mintAlcx(admin, TOKEN_1);

        hevm.startPrank(admin);

        veALCX = new VotingEscrow(address(alcx), address(MANA));
        gaugeFactory = new GaugeFactory();
        bribeFactory = new BribeFactory();
        voter = new Voter(address(veALCX), address(gaugeFactory), address(bribeFactory), address(MANA));

        address[] memory tokens = new address[](1);
        tokens[0] = address(alcx);
        voter.initialize(tokens, admin);

        alcx.approve(address(veALCX), TOKEN_1);
        veALCX.createLock(TOKEN_1, 4 * 365 * 86400);

        distributor = new RewardsDistributor(address(veALCX));
        veALCX.setVoter(address(voter));

        InitializationParams memory params = InitializationParams(
            address(voter),
            address(veALCX),
            address(distributor),
            supply,
            rewards,
            stepdown
        );

        minter = new Minter(params);

        distributor.setDepositor(address(minter));

        alcx.grantRole(keccak256("MINTER"), address(minter));

        voter.createGauge(alETHPool, Voter.GaugeType.Staking);

        hevm.roll(block.number + 1);
        assertGt(veALCX.balanceOfNFT(1), 995063075414519385);
        assertEq(alcx.balanceOf(address(veALCX)), TOKEN_1);

        address[] memory pools = new address[](1);
        pools[0] = alETHPool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 5000;
        voter.vote(1, pools, weights, 0);

        minter.initialize();

        assertEq(veALCX.ownerOf(1), admin);

        hevm.roll(block.number + 1);

        // TODO once we determine how to distribute rewards, add tests
        // to check veALCX holder balances increasing over an epoch
        uint256 before = alcx.balanceOf(address(minter));
        assertEq(before, 0);

        hevm.warp(block.timestamp + 86400 * 14);
        hevm.roll(block.number + 1);

        minter.updatePeriod();
        assertGt(alcx.balanceOf(address(distributor)), before);
        assertGt(alcx.balanceOf(address(voter)), before);
        hevm.stopPrank();
    }

    function testSameEpochVoteOrReset() public {
        hevm.startPrank(admin);

        uint256 period = minter.activePeriod();

        // Move forward a week relative to period
        hevm.warp(period + 1 weeks);

        address[] memory pools = new address[](1);
        pools[0] = alETHPool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 5000;
        voter.vote(1, pools, weights, 0);

        // Move forward half epoch relative to period
        hevm.warp(period + 1 weeks / 2);

        // Voting again fails
        pools[0] = alUSDPool;
        hevm.expectRevert(abi.encodePacked("TOKEN_ALREADY_VOTED_THIS_EPOCH"));
        voter.vote(1, pools, weights, 0);

        // Resetting fails
        hevm.expectRevert(abi.encodePacked("TOKEN_ALREADY_VOTED_THIS_EPOCH"));
        voter.reset(1);

        hevm.stopPrank();
    }

    function testNextEpochVoteOrReset() public {
        hevm.startPrank(admin);

        hevm.warp(block.timestamp + 1 weeks);

        address[] memory pools = new address[](1);
        pools[0] = alETHPool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 5000;

        voter.vote(1, pools, weights, 0);

        // Next epoch
        hevm.warp(block.timestamp + 1 weeks);

        // New vote succeeds
        pools[0] = alUSDPool;
        voter.vote(1, pools, weights, 0);

        // Next epoch
        hevm.warp(block.timestamp + 1 weeks);

        // Resetting succeeds
        voter.reset(1);

        hevm.stopPrank();
    }
}
