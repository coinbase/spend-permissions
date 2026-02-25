// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SpendRouter} from "../../../src/SpendRouter.sol";
import {SpendRouterTestBase} from "./SpendRouterTestBase.sol";

contract EncodeExtraDataTest is SpendRouterTestBase {
    /// @notice Reverts with ZeroAddress when app is address(0).
    /// @dev First check in encodeExtraData(). Recipient is a valid non-zero address.
    function test_reverts_whenAppIsZeroAddress() public {
        vm.expectRevert(SpendRouter.ZeroAddress.selector);
        router.encodeExtraData(address(0), address(2));
    }

    /// @notice Reverts with ZeroAddress when recipient is address(0).
    /// @dev Second check in encodeExtraData(). App is a valid non-zero address.
    function test_reverts_whenRecipientIsZeroAddress() public {
        vm.expectRevert(SpendRouter.ZeroAddress.selector);
        router.encodeExtraData(address(1), address(0));
    }

    /// @notice Encodes two addresses into a 64-byte payload that roundtrips correctly through decodeExtraData.
    /// @dev Fuzz both addresses, excluding address(0). Asserts decoded values match inputs and length is 64.
    function test_encodesAndDecodesCorrectly(address fuzzApp, address fuzzRecipient) public view {
        vm.assume(fuzzApp != address(0));
        vm.assume(fuzzRecipient != address(0));

        bytes memory extraData = router.encodeExtraData(fuzzApp, fuzzRecipient);
        assertEq(extraData.length, 64);

        (address decodedApp, address decodedRecipient) = abi.decode(extraData, (address, address));
        assertEq(decodedApp, fuzzApp);
        assertEq(decodedRecipient, fuzzRecipient);
    }
}
