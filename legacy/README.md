## Perun Implementation

In this Git you will find a proof of concept implementation of the Perun Channels. The goal of this project is to build a decentralized trustless state channel network, which runs offline, fast and cheap based on top of the Ethereum Blockchain.

We are currently working on release 0.2 but we do not recomend to use this software to send real Ether, since this is still ongoing development.

## Prerequisite

- Node.js
- npm
- a working geth/parity instance (testrpc will generate a wrong signature and will not work properly!)
	- thus its recommended to use the [parity dev chain](https://github.com/paritytech/parity/wiki/Private-development-chain) with the '--geth' flag for instant mining

## Run 
Install the necessary packages and make a build directory
```
$ mkdir build
$ mkdir dataDir
$ npm install
```

Start the geth network with your custom genesis block and connect to it
```
$ geth --identity "MyNodeName" --rpc --rpcport "8545" --rpccorsdomain "*" --datadir "dataDir" --port "30303" --nodiscover --rpcapi "db,eth,net,web3" --networkid 1999 init CustomGenesis.json
$ geth --identity "MyNodeName" --rpc --rpcport "8545" --rpccorsdomain "*" --datadir "dataDir" --port "30303" --nodiscover --rpcapi "db,eth,net,web3,personal" --ipcpath "/tmp/geth.ipc" --networkid 1999 console
```
In the Console:
```
//Create two new Accounts
personal.newAccount("")
personal.newAccount("")
//start mining
miner.setEtherbase(personal.listAccounts[0]) 
miner.start()

//stop after a few blocks and check your balance (you need some ether to run)
miner.stop()
balance = web3.fromWei(eth.getBalance(eth.accounts[0]), "ether");

//restart the miner
miner.start()
```
Run the simulation.
```
$ node complete_walkthrough.js
```


