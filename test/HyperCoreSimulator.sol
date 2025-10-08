// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Converters} from "../src/libraries/Converters.sol";
import {L1ReadLibrary} from "../src/libraries/L1ReadLibrary.sol";
import {MockHyperCoreState} from "./MockHyperCoreState.sol";
import {MockHypeSystemContract} from "./MockHypeSystemContract.sol";
import {Vm} from "forge-std/Vm.sol";
import {MockPrecompileSpotBalance} from "./MockPrecompileSpotBalance.sol";
import {MockPrecompileDelegatorSummary} from "./MockPrecompileDelegatorSummary.sol";
import {MockCoreWriter} from "./MockCoreWriter.sol";
import {CoreWriterLibrary} from "../src/libraries/CoreWriterLibrary.sol";

library HyperCoreSimulator {
    address internal constant MOCK_HYPERCORE_STATE_ADDRESS = address(uint160(uint256(keccak256("MockHyperCoreState"))));

    /// @dev Cheat code address.
    /// Calculated as `address(uint160(uint256(keccak256("hevm cheat code"))))`.
    address internal constant VM_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;

    address public constant HYPE_SYSTEM_ADDRESS = 0x2222222222222222222222222222222222222222;

    function init() public {
        Vm vm = Vm(VM_ADDRESS);

        // Mock HyperCore state
        MockHyperCoreState mockHyperCoreState = new MockHyperCoreState();
        vm.etch(MOCK_HYPERCORE_STATE_ADDRESS, address(mockHyperCoreState).code);
        MockHyperCoreState(MOCK_HYPERCORE_STATE_ADDRESS).init();

        // Mock HYPE system contract
        MockHypeSystemContract mockHypeSystemContract = new MockHypeSystemContract(MOCK_HYPERCORE_STATE_ADDRESS);
        vm.etch(HYPE_SYSTEM_ADDRESS, address(mockHypeSystemContract).code);

        // Mock CoreWriter
        MockCoreWriter mockCoreWriter = new MockCoreWriter();
        vm.etch(CoreWriterLibrary.CORE_WRITER, address(mockCoreWriter).code);

        // Mock precompiles
        MockPrecompileSpotBalance mockPrecompileSpotBalance = new MockPrecompileSpotBalance();
        vm.etch(L1ReadLibrary.SPOT_BALANCE_PRECOMPILE_ADDRESS, address(mockPrecompileSpotBalance).code);
        MockPrecompileDelegatorSummary mockPrecompileDelegatorSummary = new MockPrecompileDelegatorSummary();
        vm.etch(L1ReadLibrary.DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS, address(mockPrecompileDelegatorSummary).code);
    }

    function nextBlock() public {
        MockHyperCoreState(MOCK_HYPERCORE_STATE_ADDRESS).processBlock();

        Vm vm = Vm(VM_ADDRESS);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
    }
}
