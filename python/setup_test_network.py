import web3
import os

monk = "0xA12Dd3E2049ebb0B953AD0B01914fF399955924d"

w3 = web3.Web3(web3.Web3.HTTPProvider('HTTP://127.0.0.1:8545', request_kwargs={'timeout': 120}))
w3.HTTPProvider().make_request(method='anvil_setBalance', params=[monk, hex(int(10E18))])

os.chdir('/Users/joaoabrantis/github/writingmonks/contracts/script')
os.system('sh deploy_publication.sh')
print('All done')