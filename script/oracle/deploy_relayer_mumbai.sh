source .env
forge script ./DeployRelayerMumbai.s.sol:MumbaiDeployer --rpc-url $RPC_URL --private-key $PRIVATE_KEY --etherscan-api-key $ETHERSCAN_API_KEY --verify -vvvv

# --optimize --optimizer-runs 1000 --broadcast