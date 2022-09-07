import os
import json


contracts = ['MonksPublication', 'MonksERC20', 'MonksMarket']
indexer_path = '/Users/joaoabrantis/github/writingmonks/python/indexer/contracts'

for contract in contracts:
    with open(f'out/{contract}.sol/{contract}.json') as f:
        abi = json.load(f)['abi']
    
    with open(f'python/abis/{contract}.json', 'w') as f:
        json.dump(abi, f)

    with open(os.path.join(indexer_path, f'{contract}.json'), 'w') as f:
        json.dump(abi, f)
    

