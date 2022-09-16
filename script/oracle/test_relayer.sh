source .env
RUST_LOG=forge forge script ./TestRelayerMumbai.s.sol:RelayerTest --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -vvvv

# --optimize --optimizer-runs 1000 --broadcast