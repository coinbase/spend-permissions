import { hashTypedData, zeroAddress } from "viem";

function getHash(chainId, verifyingContract, spendPermission) {
  return hashTypedData({
    domain: {
      name: "Spend Permission Manager",
      version: "1",
      chainId,
      verifyingContract,
    },
    message: spendPermission,
    types: {
      SpendPermission: [
        { name: "account", type: "address" },
        { name: "spender", type: "address" },
        { name: "token", type: "address" },
        { name: "allowance", type: "uint160" },
        { name: "period", type: "uint48" },
        { name: "start", type: "uint48" },
        { name: "end", type: "uint48" },
        { name: "salt", type: "uint256" },
        { name: "extraData", type: "bytes" },
      ],
    },
    primaryType: "SpendPermission",
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
const spendPermission = {
  account: args[2],
  spender: args[3],
  token: args[4],
  allowance: BigInt(args[5]),
  period: parseInt(args[6]),
  start: parseInt(args[7]),
  end: parseInt(args[8]),
  salt: BigInt(args[9]),
  extraData: args[10],
};

// console.log({ chainId, verifyingContract, spendPermission });

console.log(getHash(chainId, verifyingContract, spendPermission));
