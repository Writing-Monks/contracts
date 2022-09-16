import os
import json


contracts = ['MonksPublication', 'MonksERC20', 'MonksMarket', 'MonksTestFaucet']
out_path = '/Users/joaoabrantis/github/writingmonks/contracts/out'

output_path = '/Users/joaoabrantis/github/writingmonks/contracts/python/abis'
indexer_path = '/Users/joaoabrantis/github/writingmonks/python/indexer/contracts'


for contract in contracts:
    with open(os.path.join(out_path, f'{contract}.sol/{contract}.json')) as f:
        abi = json.load(f)['abi']
    
    with open(os.path.join(output_path, f'{contract}.json'), 'w') as f:
        json.dump(abi, f)

    with open(os.path.join(indexer_path, f'{contract}.json'), 'w') as f:
        json.dump(abi, f)
    

