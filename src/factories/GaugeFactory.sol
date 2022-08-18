// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "../Gauge.sol";

contract GaugeFactory {
    address public lastGauge;

    function createGauge(
        address _pool,
        address _bribe,
        address _ve,
        bool isPair
    ) external returns (address) {
        lastGauge = address(new Gauge(_pool, _bribe, _ve, msg.sender, isPair));
        return lastGauge;
    }
}
