source .testenv
RUST_LOG=forge forge script ./Publish.s.sol:Resolve --fork-url http://localhost:8545 --private-key $PRIVATE_KEY --broadcast -vvvv --gas-estimate-multiplier 1000