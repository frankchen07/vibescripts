# Ethereum QR Code Generator

generate QR codes with prefilled fields to pay your ethereum address

## Installation

npm install## Usage

### Command Line

Generate a QR code for an address:

node generate-qr.js 0x742d35Cc6634C0532925a3b844Bc9e7595f0bEbGenerate with a specific amount (in ETH):
sh
node generate-qr.js 0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb 0.1Generate for a specific chain:

node generate-qr.js 0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb 0.1 1(Chain IDs: 1 = Mainnet, 5 = Goerli, 11155111 = Sepolia)

### Browser (HTML)

Open `view.html` in your browser for an interactive interface.

## What it does

The QR code uses EIP-67 URI scheme format. When scanned with a compatible wallet (MetaMask, Trust Wallet, etc.), it will:
- Pre-fill the recipient address
- Optionally pre-fill the amount to send
- Set the chain/network

Makes it easy for people to send you ETH without typing addresses manually.