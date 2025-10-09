// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Vm} from "forge-std/Vm.sol";
import {CommonBase} from "forge-std/Base.sol";
import {ICoreWriter} from "../src/interfaces/ICoreWriter.sol";
import {Converters} from "../src/libraries/Converters.sol";
import {L1ReadLibrary} from "../src/libraries/L1ReadLibrary.sol";
import {CoreWriterLibrary} from "../src/libraries/CoreWriterLibrary.sol";
import {MockHyperCoreState} from "./mocks/MockHyperCoreState.sol";
import {MockHypeSystemContract} from "./mocks/MockHypeSystemContract.sol";
import {MockPrecompileSpotBalance} from "./mocks/MockPrecompileSpotBalance.sol";
import {MockPrecompileDelegatorSummary} from "./mocks/MockPrecompileDelegatorSummary.sol";
import {MockPrecompileDelegations} from "./mocks/MockPrecompileDelegations.sol";
import {MockPrecompileCoreUserExists} from "./mocks/MockPrecompileCoreUserExists.sol";
import {MockCoreWriter} from "./mocks/MockCoreWriter.sol";
import {Constants} from "./mocks/Constants.sol";

contract HyperCoreSimulator is CommonBase {
    MockHyperCoreState hl;

    constructor() {
        // Mock HyperCore state
        vm.etch(Constants.MOCK_HYPERCORE_STATE_ADDRESS, address(new MockHyperCoreState()).code);

        // Mock HYPE system contract
        MockHypeSystemContract mockHypeSystemContract = new MockHypeSystemContract();
        vm.etch(Constants.HYPE_SYSTEM_ADDRESS, address(mockHypeSystemContract).code);

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
        MockPrecompileCoreUserExists mockPrecompileCoreUserExists = new MockPrecompileCoreUserExists();
        vm.etch(L1ReadLibrary.CORE_USER_EXISTS_PRECOMPILE_ADDRESS, address(mockPrecompileCoreUserExists).code);

        hl = MockHyperCoreState(Constants.MOCK_HYPERCORE_STATE_ADDRESS);
        hl.init();
    }

    function warp(uint256 timestamp) public {
        hl.afterBlock();

        vm.roll(vm.getBlockNumber() + timestamp - vm.getBlockTimestamp());
        vm.warp(timestamp);

        hl.beforeBlock();
    }

    function expectCoreWriterCall(bytes3 actionId, bytes memory encodedAction) public {
        vm.expectCall(
            CoreWriterLibrary.CORE_WRITER,
            abi.encodeCall(ICoreWriter.sendRawAction, coreWriterCallData(actionId, encodedAction))
        );
    }

    function expectCoreWriterCall(bytes3 actionId, bytes memory encodedAction, uint64 count) public {
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
