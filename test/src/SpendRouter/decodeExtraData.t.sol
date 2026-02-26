// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SpendRouter} from "src/SpendRouter.sol";
import {SpendRouterTestBase} from "test/src/SpendRouter/SpendRouterTestBase.sol";

contract DecodeExtraDataTest is SpendRouterTestBase {
    /// @notice Reverts with MalformedExtraData when extraData is empty.
    function test_reverts_whenExtraDataEmpty() public {
        vm.expectRevert(abi.encodeWithSelector(SpendRouter.MalformedExtraData.selector, 0, ""));
        router.decodeExtraData("");
    }

    /// @notice Reverts with MalformedExtraData when extraData is shorter than 64 bytes.
    /// @dev Uses abi.encode(address) which produces 32 bytes.
    function test_reverts_whenExtraDataTooShort() public {
        bytes memory extraData = abi.encode(address(1));
        vm.expectRevert(abi.encodeWithSelector(SpendRouter.MalformedExtraData.selector, 32, extraData));
        router.decodeExtraData(extraData);
    }

    /// @notice Reverts with MalformedExtraData when extraData is longer than 64 bytes.
    /// @dev Uses abi.encode(address, address, address) which produces 96 bytes.
    function test_reverts_whenExtraDataTooLong() public {
        bytes memory extraData = abi.encode(address(1), address(2), address(3));
        vm.expectRevert(abi.encodeWithSelector(SpendRouter.MalformedExtraData.selector, 96, extraData));
        router.decodeExtraData(extraData);
    }

    /// @notice Reverts with MalformedExtraData for any extraData that is not exactly 64 bytes.
    /// @dev Fuzz arbitrary bytes, excluding those with length == 64.
    function test_reverts_whenExtraDataNotSixtyFourBytes(bytes memory extraData) public {
        vm.assume(extraData.length != 64);
        vm.expectRevert(abi.encodeWithSelector(SpendRouter.MalformedExtraData.selector, extraData.length, extraData));
        router.decodeExtraData(extraData);
    }

    /// @notice Successfully decodes a valid 64-byte ABI-encoded payload into (executor, recipient).
    /// @dev Fuzz both addresses (including address(0) since decodeExtraData does not check for zero).
    ///      Asserts decoded values match the ABI-encoded inputs.
    function test_decodesCorrectly(address fuzzExecutor, address fuzzRecipient) public view {
        bytes memory extraData = abi.encode(fuzzExecutor, fuzzRecipient);
        (address decodedExecutor, address decodedRecipient) = router.decodeExtraData(extraData);
        assertEq(decodedExecutor, fuzzExecutor);
        assertEq(decodedRecipient, fuzzRecipient);
    }
}
