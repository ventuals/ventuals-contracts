// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";
import {L1ReadLibrary} from "../../src/libraries/L1ReadLibrary.sol";

/// @dev Cheat code address.
/// Calculated as `address(uint160(uint256(keccak256("hevm cheat code"))))`.
address constant VM_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;

library L1ReadAdapter {
    function initialize() external {
        Vm vm = Vm(VM_ADDRESS);

        // Position
        vm.allowCheatcodes(L1ReadLibrary.POSITION_PRECOMPILE_ADDRESS);
        vm.etch(L1ReadLibrary.POSITION_PRECOMPILE_ADDRESS, address(new RpcCallPosition()).code);

        // Spot balance
        vm.allowCheatcodes(L1ReadLibrary.SPOT_BALANCE_PRECOMPILE_ADDRESS);
        vm.etch(L1ReadLibrary.SPOT_BALANCE_PRECOMPILE_ADDRESS, address(new RpcCallSpotBalance()).code);

        // Vault equity
        vm.allowCheatcodes(L1ReadLibrary.VAULT_EQUITY_PRECOMPILE_ADDRESS);
        vm.etch(L1ReadLibrary.VAULT_EQUITY_PRECOMPILE_ADDRESS, address(new RpcCallVaultEquity()).code);

        // Withdrawable
        vm.allowCheatcodes(L1ReadLibrary.WITHDRAWABLE_PRECOMPILE_ADDRESS);
        vm.etch(L1ReadLibrary.WITHDRAWABLE_PRECOMPILE_ADDRESS, address(new RpcCallWithdrawable()).code);

        // Delegations
        vm.allowCheatcodes(L1ReadLibrary.DELEGATIONS_PRECOMPILE_ADDRESS);
        vm.etch(L1ReadLibrary.DELEGATIONS_PRECOMPILE_ADDRESS, address(new RpcCallDelegations()).code);

        // Delegator summary
        vm.allowCheatcodes(L1ReadLibrary.DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS);
        vm.etch(L1ReadLibrary.DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS, address(new RpcCallDelegatorSummary()).code);

        // Mark price
        vm.allowCheatcodes(L1ReadLibrary.MARK_PX_PRECOMPILE_ADDRESS);
        vm.etch(L1ReadLibrary.MARK_PX_PRECOMPILE_ADDRESS, address(new RpcCallMarkPx()).code);

        // Oracle price
        vm.allowCheatcodes(L1ReadLibrary.ORACLE_PX_PRECOMPILE_ADDRESS);
        vm.etch(L1ReadLibrary.ORACLE_PX_PRECOMPILE_ADDRESS, address(new RpcCallOraclePx()).code);

        // Spot price
        vm.allowCheatcodes(L1ReadLibrary.SPOT_PX_PRECOMPILE_ADDRESS);
        vm.etch(L1ReadLibrary.SPOT_PX_PRECOMPILE_ADDRESS, address(new RpcCallSpotPx()).code);

        // L1 block number
        vm.allowCheatcodes(L1ReadLibrary.L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS);
        vm.etch(L1ReadLibrary.L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS, address(new RpcCallL1BlockNumber()).code);

        // Perp asset info
        vm.allowCheatcodes(L1ReadLibrary.PERP_ASSET_INFO_PRECOMPILE_ADDRESS);
        vm.etch(L1ReadLibrary.PERP_ASSET_INFO_PRECOMPILE_ADDRESS, address(new RpcCallPerpAssetInfo()).code);

        // Spot info
        vm.allowCheatcodes(L1ReadLibrary.SPOT_INFO_PRECOMPILE_ADDRESS);
        vm.etch(L1ReadLibrary.SPOT_INFO_PRECOMPILE_ADDRESS, address(new RpcCallSpotInfo()).code);

        // Token info
        vm.allowCheatcodes(L1ReadLibrary.TOKEN_INFO_PRECOMPILE_ADDRESS);
        vm.etch(L1ReadLibrary.TOKEN_INFO_PRECOMPILE_ADDRESS, address(new RpcCallTokenInfo()).code);

        // Token supply
        vm.allowCheatcodes(L1ReadLibrary.TOKEN_SUPPLY_PRECOMPILE_ADDRESS);
        vm.etch(L1ReadLibrary.TOKEN_SUPPLY_PRECOMPILE_ADDRESS, address(new RpcCallTokenSupply()).code);

        // BBO
        vm.allowCheatcodes(L1ReadLibrary.BBO_PRECOMPILE_ADDRESS);
        vm.etch(L1ReadLibrary.BBO_PRECOMPILE_ADDRESS, address(new RpcCallBbo()).code);

        // Account margin summary
        vm.allowCheatcodes(L1ReadLibrary.ACCOUNT_MARGIN_SUMMARY_PRECOMPILE_ADDRESS);
        vm.etch(
            L1ReadLibrary.ACCOUNT_MARGIN_SUMMARY_PRECOMPILE_ADDRESS, address(new RpcCallAccountMarginSummary()).code
        );

        // Core user exists
        vm.allowCheatcodes(L1ReadLibrary.CORE_USER_EXISTS_PRECOMPILE_ADDRESS);
        vm.etch(L1ReadLibrary.CORE_USER_EXISTS_PRECOMPILE_ADDRESS, address(new RpcCallCoreUserExists()).code);
    }
}

contract BaseRpcCall {
    function rpcCall(address to, bytes calldata data) internal returns (bytes memory) {
        Vm vm = Vm(VM_ADDRESS);
        string memory params =
            string(abi.encodePacked("[{\"to\": \"", vm.toString(to), "\", \"data\": \"", vm.toString(data), "\"}]"));
        bytes memory ethCallResult = vm.rpc("eth_call", params);
        return ethCallResult;
    }
}

contract RpcCallPosition is BaseRpcCall {
    fallback(bytes calldata data) external payable returns (bytes memory) {
        return rpcCall(L1ReadLibrary.POSITION_PRECOMPILE_ADDRESS, data);
    }
}

contract RpcCallSpotBalance is BaseRpcCall {
    fallback(bytes calldata data) external payable returns (bytes memory) {
        return rpcCall(L1ReadLibrary.SPOT_BALANCE_PRECOMPILE_ADDRESS, data);
    }
}

contract RpcCallVaultEquity is BaseRpcCall {
    fallback(bytes calldata data) external payable returns (bytes memory) {
        return rpcCall(L1ReadLibrary.VAULT_EQUITY_PRECOMPILE_ADDRESS, data);
    }
}

contract RpcCallWithdrawable is BaseRpcCall {
    fallback(bytes calldata data) external payable returns (bytes memory) {
        return rpcCall(L1ReadLibrary.WITHDRAWABLE_PRECOMPILE_ADDRESS, data);
    }
}

contract RpcCallDelegations is BaseRpcCall {
    fallback(bytes calldata data) external payable returns (bytes memory) {
        return rpcCall(L1ReadLibrary.DELEGATIONS_PRECOMPILE_ADDRESS, data);
    }
}

contract RpcCallDelegatorSummary is BaseRpcCall {
    fallback(bytes calldata data) external payable returns (bytes memory) {
        return rpcCall(L1ReadLibrary.DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS, data);
    }
}

contract RpcCallMarkPx is BaseRpcCall {
    fallback(bytes calldata data) external payable returns (bytes memory) {
        return rpcCall(L1ReadLibrary.MARK_PX_PRECOMPILE_ADDRESS, data);
    }
}

contract RpcCallOraclePx is BaseRpcCall {
    fallback(bytes calldata data) external payable returns (bytes memory) {
        return rpcCall(L1ReadLibrary.ORACLE_PX_PRECOMPILE_ADDRESS, data);
    }
}

contract RpcCallSpotPx is BaseRpcCall {
    fallback(bytes calldata data) external payable returns (bytes memory) {
        return rpcCall(L1ReadLibrary.SPOT_PX_PRECOMPILE_ADDRESS, data);
    }
}

contract RpcCallL1BlockNumber is BaseRpcCall {
    fallback(bytes calldata data) external payable returns (bytes memory) {
        return rpcCall(L1ReadLibrary.L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS, data);
    }
}

contract RpcCallPerpAssetInfo is BaseRpcCall {
    fallback(bytes calldata data) external payable returns (bytes memory) {
        return rpcCall(L1ReadLibrary.PERP_ASSET_INFO_PRECOMPILE_ADDRESS, data);
    }
}

contract RpcCallSpotInfo is BaseRpcCall {
    fallback(bytes calldata data) external payable returns (bytes memory) {
        return rpcCall(L1ReadLibrary.SPOT_INFO_PRECOMPILE_ADDRESS, data);
    }
}

contract RpcCallTokenInfo is BaseRpcCall {
    fallback(bytes calldata data) external payable returns (bytes memory) {
        return rpcCall(L1ReadLibrary.TOKEN_INFO_PRECOMPILE_ADDRESS, data);
    }
}

contract RpcCallTokenSupply is BaseRpcCall {
    fallback(bytes calldata data) external payable returns (bytes memory) {
        return rpcCall(L1ReadLibrary.TOKEN_SUPPLY_PRECOMPILE_ADDRESS, data);
    }
}

contract RpcCallBbo is BaseRpcCall {
    fallback(bytes calldata data) external payable returns (bytes memory) {
        return rpcCall(L1ReadLibrary.BBO_PRECOMPILE_ADDRESS, data);
    }
}

contract RpcCallAccountMarginSummary is BaseRpcCall {
    fallback(bytes calldata data) external payable returns (bytes memory) {
        return rpcCall(L1ReadLibrary.ACCOUNT_MARGIN_SUMMARY_PRECOMPILE_ADDRESS, data);
    }
}

contract RpcCallCoreUserExists is BaseRpcCall {
    fallback(bytes calldata data) external payable returns (bytes memory) {
        return rpcCall(L1ReadLibrary.CORE_USER_EXISTS_PRECOMPILE_ADDRESS, data);
    }
}
