# Contracts

These repository as the Writing Monks contract:

### MonksPublication.sol

Each DAO's Twitter has a corresponding `MonksPublication` contract that manages the access to the twitter account.

This where people:
- add content suggestions

Moderators:
- flag posts
- publish posts (by interacting with the TweetRelayer.sol

### MonksMarket.sol
Every content suggestion has a corresponding `MonksMarket` contract. This contract is where the prediction market logic lives.

### MonksERC20.sol
Currently, this is vanilla ERC20 token, we will add more features in future.

### TweeterRelayer.sol
Talks with our Chainlink Operator to post and read information from the DAOs' Twitter accounts.

(we still need to add some access restrictions to this contract so that only publications can call the write functions).
