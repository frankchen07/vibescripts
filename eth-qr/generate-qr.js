#!/usr/bin/env node

const EthereumQRplugin = require('ethereum-qr-code');
const QRCode = require('qrcode');
const fs = require('fs');
const path = require('path');
const https = require('https');

// USDC contract address on Ethereum mainnet
const USDC_CONTRACT = '0xA0b86991c6218b36c1d19d4a2e9eb0ce3606eb48';

// Token decimals
const USDC_DECIMALS = 6; // USDC has 6 decimal places
const ETH_DECIMALS = 18;

// Fetch current ETH price in USD
async function getETHPrice() {
  return new Promise((resolve, reject) => {
    https.get('https://api.coinbase.com/v2/exchange-rates?currency=ETH', (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          const price = parseFloat(json.data.rates.USD);
          resolve(price);
        } catch (error) {
          reject(error);
        }
      });
    }).on('error', reject);
  });
}

// Parse command line arguments
const args = process.argv.slice(2);
if (args.length === 0) {
  console.log('Usage: node generate-qr.js <ethereum-address> [amount] [type] [chain-id]');
  console.log('');
  console.log('Examples:');
  console.log('  node generate-qr.js 0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb');
  console.log('  node generate-qr.js 0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb 5 usdc');
  console.log('  node generate-qr.js 0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb 5 usd');
  console.log('  node generate-qr.js 0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb 0.1 eth');
  process.exit(1);
}

const address = args[0];
const amount = args[1] ? parseFloat(args[1]) : null;
const type = (args[2] || 'eth').toLowerCase(); // eth, usdc, or usd
const chainId = args[3] ? parseInt(args[3]) : 1; // Default to mainnet

// Validate Ethereum address
if (!/^0x[a-fA-F0-9]{40}$/.test(address)) {
  console.error('Error: Invalid Ethereum address format');
  process.exit(1);
}

async function generateQR() {
  let config = {
    to: address,
    gas: 21000,
    chainId: chainId
  };

  let outputLabel = '';
  let outputValue = '';

  if (amount) {
    if (type === 'usdc') {
      // 5 USDC = 5000000 (with 6 decimals)
      const usdcAmount = BigInt(Math.floor(amount * Math.pow(10, USDC_DECIMALS))).toString();
      
      config = {
        to: USDC_CONTRACT,  // Contract address goes in 'to' field
        mode: 'erc20__transfer',
        argsDefaults: [
          { name: 'to', value: address },      // Recipient goes in argsDefaults
          { name: 'value', value: usdcAmount }
        ],
        gas: 100000,
        chainId: chainId
      };
      
      outputLabel = '💰 Amount';
      outputValue = `${amount} USDC (≈ $${amount})`;
    } else if (type === 'usd') {
      // Fetch ETH price and calculate amount
      console.log('Fetching current ETH price...');
      try {
        const ethPrice = await getETHPrice();
        const ethAmount = amount / ethPrice;
        const weiAmount = BigInt(Math.floor(ethAmount * Math.pow(10, ETH_DECIMALS))).toString();
        
        config.value = weiAmount;
        outputLabel = '💰 Amount';
        outputValue = `$${amount} worth (≈ ${ethAmount.toFixed(6)} ETH @ $${ethPrice.toFixed(2)}/ETH)`;
      } catch (error) {
        console.error('Error fetching ETH price:', error.message);
        console.log('Falling back to USDC instead...');
        // Fallback to USDC
        const usdcAmount = BigInt(Math.floor(amount * Math.pow(10, USDC_DECIMALS))).toString();
        config = {
          to: USDC_CONTRACT,  // Contract address goes in 'to' field
          mode: 'erc20__transfer',
          argsDefaults: [
            { name: 'to', value: address },      // Recipient goes in argsDefaults
            { name: 'value', value: usdcAmount }
          ],
          gas: 100000,
          chainId: chainId
        };
        outputLabel = '💰 Amount';
        outputValue = `${amount} USDC (stablecoin, $1 = 1 USDC)`;
      } 
    } else {
      // ETH
      const weiAmount = BigInt(Math.floor(amount * Math.pow(10, ETH_DECIMALS))).toString();
      config.value = weiAmount;
      outputLabel = '💰 Amount';
      outputValue = `${amount} ETH`;
    }
  }

  // Generate proper ethereum: URI
  let ethereumUri;
  
  if (type === 'usdc' && amount) {
    // For ERC-20 transfers, the standard doesn't fully support URI format
    // Some wallets use a format with the contract address and recipient
    // We'll encode the contract address with recipient info as a parameter
    // Format: ethereum:CONTRACT_ADDRESS?to=RECIPIENT&value=AMOUNT
    const usdcAmount = BigInt(Math.floor(amount * Math.pow(10, USDC_DECIMALS))).toString();
    const params = [`to=${address}`, `value=${usdcAmount}`];
    if (chainId !== 1) {
      params.push(`chainId=${chainId}`);
    }
    ethereumUri = `ethereum:${USDC_CONTRACT}?${params.join('&')}`;
  } else {
    // For ETH transfers, use the library's proper URI encoding
    const qr = new EthereumQRplugin();
    ethereumUri = qr.produceEncodedValue(config);
    
    // Verify it's a proper URI (starts with ethereum:)
    // If the library returns JSON (for modes), we'll construct it manually
    if (!ethereumUri.startsWith('ethereum:')) {
      // Fallback: construct URI manually
      const params = [];
      if (config.value) params.push(`value=${config.value}`);
      if (config.gas) params.push(`gas=${config.gas}`);
      if (config.chainId && config.chainId !== 1) params.push(`chainId=${config.chainId}`);
      const paramsStr = params.length > 0 ? '?' + params.join('&') : '';
      ethereumUri = `ethereum:${config.to}${paramsStr}`;
    }
  }

  // Output file path
  const typeLabel = amount ? `-${type}-${amount}` : '';
  const outputFile = path.join(__dirname, `qr-${address.slice(0, 8)}${typeLabel}-${Date.now()}.png`);

  // Generate QR code directly from the URI string using qrcode library
  QRCode.toFile(outputFile, ethereumUri, {
    type: 'png',
    width: 500,
    margin: 2,
    errorCorrectionLevel: 'M'
  }, (error) => {
    if (error) {
      console.error('❌ Error generating QR code:', error.message);
      console.error(error);
      process.exit(1);
    }
    
    console.log('');
    console.log('✅ QR code generated successfully!');
    console.log(`📁 Saved to: ${outputFile}`);
    console.log(`📍 Address: ${address}`);
    console.log(`🔗 URI: ${ethereumUri}`);
    if (amount) {
        console.log(`${outputLabel}: ${outputValue}`);
    }
    if (type === 'usdc') {
        console.log(`🪙 Token: USDC (ERC-20)`);
        console.log(`📄 Contract: ${USDC_CONTRACT}`);
    }
    console.log(`🔗 Chain ID: ${chainId}`);
    console.log('');
  });
}

generateQR();