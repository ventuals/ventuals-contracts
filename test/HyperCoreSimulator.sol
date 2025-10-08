// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ICoreWriter} from "../src/interfaces/ICoreWriter.sol";
import {Converters} from "../src/libraries/Converters.sol";
import {L1ReadLibrary} from "../src/libraries/L1ReadLibrary.sol";
import {MockHyperCoreState} from "./MockHyperCoreState.sol";
import {MockHypeSystemContract} from "./MockHypeSystemContract.sol";
import {Vm} from "forge-std/Vm.sol";
import {MockPrecompileSpotBalance} from "./MockPrecompileSpotBalance.sol";
import {MockPrecompileDelegatorSummary} from "./MockPrecompileDelegatorSummary.sol";
import {MockPrecompileDelegations} from "./MockPrecompileDelegations.sol";
import {MockCoreWriter} from "./MockCoreWriter.sol";
import {CoreWriterLibrary} from "../src/libraries/CoreWriterLibrary.sol";
import {CommonBase} from "forge-std/Base.sol";

contract HyperCoreSimulator is CommonBase {
    address internal constant MOCK_HYPERCORE_STATE_ADDRESS = address(uint160(uint256(keccak256("MockHyperCoreState"))));

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
        MockPrecompileDelegations mockPrecompileDelegations = new MockPrecompileDelegations();
        vm.etch(L1ReadLibrary.DELEGATIONS_PRECOMPILE_ADDRESS, address(mockPrecompileDelegations).code);
    }

    function nextBlock() public {
        MockHyperCoreState(MOCK_HYPERCORE_STATE_ADDRESS).processBlock();

        Vm vm = Vm(VM_ADDRESS);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
    }

    function expectCoreWriterCall(bytes3 actionId, bytes memory encodedAction) public {
        Vm vm = Vm(VM_ADDRESS);
        vm.expectCall(
            CoreWriterLibrary.CORE_WRITER,
            abi.encodeCall(ICoreWriter.sendRawAction, coreWriterCallData(actionId, encodedAction))
        );
    }

    function expectCoreWriterCall(bytes3 actionId, bytes memory encodedAction, uint64 count) public {
        Vm vm = Vm(VM_ADDRESS);
        vm.expectCall(
            CoreWriterLibrary.CORE_WRITER,
            abi.encodeCall(ICoreWriter.sendRawAction, coreWriterCallData(actionId, encodedAction)),
            count
        );
    }

    function coreWriterCallData(bytes3 actionId, bytes memory encodedAction) internal pure returns (bytes memory) {
        bytes memory data = new bytes(4 + encodedAction.length);
        data[0] = CoreWriterLibrary.CORE_WRITER_VERSION;
        for (uint256 i = 0; i < 3; i++) {
            data[1 + i] = actionId[i];
        }
        for (uint256 i = 0; i < encodedAction.length; i++) {
            data[4 + i] = encodedAction[i];
        }
        return data;
    }
}
