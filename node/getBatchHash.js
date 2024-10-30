import { hashTypedData, zeroAddress } from "viem";

function getHash(chainId, verifyingContract, spendPermissionBatch) {
  return hashTypedData({
    domain: {
      name: "Spend Permission Manager",
      version: "1",
      chainId,
      verifyingContract,
    },
    message: spendPermissionBatch,
    types: {
      SpendPermissionBatch: [
        { name: "account", type: "address" },
        { name: "period", type: "uint48" },
        { name: "start", type: "uint48" },
        { name: "end", type: "uint48" },
        { name: "permissions", type: "PermissionDetails[]" },
      ],
      PermissionDetails: [
        { name: "spender", type: "address" },
        { name: "token", type: "address" },
        { name: "allowance", type: "uint160" },
        { name: "salt", type: "uint256" },
        { name: "extraData", type: "bytes" },
      ],
    },
    primaryType: "SpendPermissionBatch",
  });
}

const args = process.argv.slice(2);

// Check expected arguments
if (args.length !== 11) {
  console.log("Please provide exactly 11 arguments.");
  process.exit(1);
}

const chainId = parseInt(args[0]);
const verifyingContract = args[1];
const spendPermissionBatch = {
  account: args[2],
  period: parseInt(args[6]),
  start: parseInt(args[7]),
  end: parseInt(args[8]),
  permissions: [
    {
      spender: args[3],
      token: args[4],
      allowance: BigInt(args[5]),
      salt: BigInt(args[9]),
      extraData: args[10],
    },
  ],
};

// console.log({ chainId, verifyingContract, spendPermission });

console.log(getHash(chainId, verifyingContract, spendPermissionBatch));
