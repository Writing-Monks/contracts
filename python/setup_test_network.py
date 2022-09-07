import web3
import os

monk = "0xccb4D1786a2d25484957f33F1354cc487bE157CD"

w3 = web3.Web3(web3.Web3.HTTPProvider('HTTP://127.0.0.1:8545', request_kwargs={'timeout': 120}))
w3.HTTPProvider().make_request(method='anvil_setBalance', params=[monk, hex(int(10E18))])

os.chdir('/Users/joaoabrantis/github/writingmonks/contracts/script')
os.system('sh deploy_publication.sh')
print('All done')