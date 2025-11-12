import { ethers } from 'ethers';

const EIP6492_MAGIC_VALUE = '0x6492649264926492649264926492649264926492649264926492649264926492';

interface SpendPermission {
  account: string;
  spender: string;
  token: string;
  allowance: string;
  period: number;
  start: number;
  end: number;
  salt: string;
  extraData: string;
}

interface CoinbaseSmartWalletCall {
  target: string;
  value: string;
  data: string;
}

class SignatureHooksSignatureGenerator {
  private permit3Address: string;
  private signatureHookAddress: string;
  private chainId: number;

  constructor(permit3Address: string, signatureHookAddress: string, chainId: number) {
    this.permit3Address = permit3Address;
    this.signatureHookAddress = signatureHookAddress;
    this.chainId = chainId;
  }

  // Generate ERC6492 signature for spend permission with signed calls
  async generateSignature(
    spendPermission: SpendPermission,
    ownerPrivateKey: string,
    ownerIndex: number = 0,
    signatureHookOwnerIndex: number = 1
  ): Promise<string> {
    
    // 0. Calculate spend permission hash (would come from permit3.getHash())
    const spendPermissionHash = calculateSpendPermissionHash(spendPermission);
   
    // 1. Create approve call
    const approveSelector = ethers.utils.id('approve(address,uint256)').slice(0, 10);
    const approveData = ethers.utils.defaultAbiCoder.encode(
      ['bytes4', 'address', 'uint256'],
      [approveSelector, this.permit3Address, ethers.constants.MaxUint256]
    );
    
    const calls = [{
      target: spendPermission.token,
      value: '0',
      data: approveData
    }];

    // 2. Create the message to sign: keccak256(abi.encode(verifyingContract, calls, hash))
    const messageToSign = ethers.utils.keccak256(
      ethers.utils.defaultAbiCoder.encode(
        ['address', 'tuple(address,uint256,bytes)[]', 'bytes32'],
        [this.permit3Address, calls, spendPermissionHash]
      )
    );
    
    // 3. Calculate CoinbaseSmartWallet's replaySafeHash 
    const replaySafeHash = calculateReplaySafeHash(messageToSign, spendPermission.account);
    
    // 4. Sign the replaySafeHash with owner's private key
    const wallet = new ethers.Wallet(ownerPrivateKey);
    const signature = await wallet.signMessage(ethers.utils.arrayify(replaySafeHash));
    
    // 5. Wrap signature with owner index (CoinbaseSmartWallet.SignatureWrapper)
    const wrappedSignature = ethers.utils.defaultAbiCoder.encode(
      ['tuple(uint256,bytes)'],
      [[ownerIndex, signature]]
    );
    
    // 6. Create prepare data for SignatureHooks.executeSignedCallsWithMessage
    const executeSignedCallsSelector = ethers.utils.id('executeSignedCallsWithMessage(address,bytes,bytes,address,bytes32)').slice(0, 10);
    const prepareData = ethers.utils.defaultAbiCoder.encode(
      ['bytes4', 'address', 'bytes', 'bytes', 'address', 'bytes32'],
      [
        executeSignedCallsSelector,
        spendPermission.account,
        ethers.utils.defaultAbiCoder.encode(['tuple(address,uint256,bytes)[]'], [calls]),
        wrappedSignature,
        this.permit3Address,
        spendPermissionHash
      ]
    );
    
    // 7. Create inner signature: {signatureHookOwnerIndex}{empty bytes}
    const innerSignature = ethers.utils.defaultAbiCoder.encode(
      ['tuple(uint256,bytes)'],
      [[signatureHookOwnerIndex, '0x']]
    );
    
    // 8. Wrap everything in EIP6492 format
    const eip6492Signature = ethers.utils.defaultAbiCoder.encode(
      ['address', 'bytes', 'bytes'],
      [this.signatureHookAddress, prepareData, innerSignature]
    );
    
    return eip6492Signature + EIP6492_MAGIC_VALUE.slice(2);
  }
  
  // Helper to create ERC20 approval call
  createERC20ApprovalCall(tokenAddress: string): CoinbaseSmartWalletCall {

  }
  
  // Helper to create hook registration call

  
  // Simplified spend permission hash calculation (would typically come from contract)
  private calculateSpendPermissionHash(spendPermission: SpendPermission): string {
    return ethers.utils.keccak256(
      ethers.utils.defaultAbiCoder.encode(
        ['address', 'address', 'address', 'uint160', 'uint48', 'uint48', 'uint48', 'uint256', 'bytes'],
        [
          spendPermission.account,
          spendPermission.spender,
          spendPermission.token,
          spendPermission.allowance,
          spendPermission.start,
          spendPermission.end,
          spendPermission.period,
          spendPermission.salt,
          spendPermission.extraData
        ]
      )
    );
  }
}

// Example usage
async function demonstrateSignatureGeneration() {
  const generator = new SignatureHooksSignatureGenerator(
    '0x...', // permit3 address
    '0x...', // signatureHook address
    1 // mainnet chainId
  );
  
  const spendPermission: SpendPermission = {
    account: '0x...',
    spender: '0x...',
    token: '0x...', // ERC20 token address
    allowance: ethers.utils.parseEther('1').toString(),
    period: 604800, // 1 week
    start: Math.floor(Date.now() / 1000),
    end: Math.floor(Date.now() / 1000) + 365 * 24 * 60 * 60, // 1 year
    salt: '0',
    extraData: '0x'
  };
  
  // Create calls array - just ERC20 approval for this example
  const calls = [
    generator.createERC20ApprovalCall(spendPermission.token)
  ];
  
  // Generate signature
  const signature = await generator.generateSpendPermissionSignature(
    spendPermission,
    calls,
    '0x...', // owner private key
    0, // owner index
    1  // signature hook owner index
  );
  
  console.log('Generated EIP6492 signature:', signature);
  return signature;
}
