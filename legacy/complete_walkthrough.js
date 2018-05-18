const utils = require('ethereumjs-util');
const abi = require('ethereumjs-abi');

function generateSignatures(argType, args) {
    const msgHash = "0x" + abi.soliditySHA3(
        argType,
        args
    ).toString("hex");
    const sigAlice = web3.eth.sign(aliceAddr, msgHash);
    const sigBob = web3.eth.sign(bobAddr, msgHash);
    return {
        alice: sigAlice,
        bob: sigBob
    };
}

// XXX: NOTE THIS USES THE OLD web3.js 0.18.0 version, not the 1.0 API
function getContract(contractName, libAddress) {
    if (typeof libAddress !== 'undefined') {
        exec('solc --bin --abi --optimize --overwrite -o build/ --libraries LibSignatures:'+libAddress+' contracts/'+contractName+'.sol');
    } else {
        exec('solc --bin --abi --optimize --overwrite -o build/ contracts/'+contractName+'.sol');
    }

    // compile library first 
    var code = "0x" + fs.readFileSync("build/" + contractName + ".bin");
    var abi = fs.readFileSync("build/" + contractName + ".abi");
    var contract = web3.eth.contract(JSON.parse(abi));

    return {
        contract: contract,
        code: code
    };
}

function deployVPC(libAddress) {
    var vpc = getContract("VPC", libAddress);

    vpc.contract.new(
       {
         from: aliceAddr, 
         data: vpc.code, 
         gas: '2000000'
       }, function (e, contract){
           if(e){
            console.log(e);
           }
           if (typeof contract.address !== 'undefined') {
               console.log('Contract mined! address: ' + contract.address + ' transactionHash: ' + contract.transactionHash);
               deployMSContract(libAddress, contract);
           }
     });
    console.log('VPC deployed');
}

function deployMSContract(libAddress, vpc) {
    var msc = getContract("MSContract", libAddress);

    msc.contract.new(
        aliceAddr,
        bobAddr,
       {
         from: aliceAddr, 
         data: msc.code, 
         gas: '2000000'
       }, function (e, contract){
           if (typeof contract.address !== 'undefined') {
               console.log('Contract mined! address: ' + contract.address + ' transactionHash: ' + contract.transactionHash);

               runSimulation(contract, vpc);
           }
     });
    console.log('MSContract deployed');
}

function runSimulation(msc, vpc) {
    var events = msc.allEvents({fromBlock: 0, toBlock: 'latest'});
    var initialized = false;

    // setup MSContract watcher with async callbacks
    events.watch(function(error, event) {
        if (!error) {

            if(event.event == "EventInitializing") {
                if (!initialized) {
                    initialized = true;
                    console.log("Channel Initialized for alice: "+event.args.addressAlice+" bob: "+event.args.addressBob);

                    // confirm from both accounts, real world this would obviously seperated
                    msc.confirm.sendTransaction({
                        from: aliceAddr,
                        value: web3.toWei(10, "ether")
                    }, function(err, txHash) {
                        if(err) {
                            console.log(err);
                        } else {
                        }
                    });
                    msc.confirm.sendTransaction({
                        from: bobAddr,
                        value: web3.toWei(10, "ether")
                    }, function(err, txHash) {
                        if(err) {
                            console.log(err);
                        } else {
                        }
                    });
                }

            } else if (event.event == "EventInitialized") {
                console.log("Both Parties confirmed alice put in: "+web3.fromWei(event.args.cashAlice, "ether")+" bob: "+web3.fromWei(event.args.cashBob, "ether"));

                // we assume both parties have agreed on these parameters here
                const sid = 10;
                const blockedAlice = web3.toWei(10, "ether");
                const blockedBob = web3.toWei(10, "ether");
                const version = 0;

                signatures = generateSignatures(
                    ["address", "uint", "uint", "uint", "uint"],
                    [vpc.address, sid, blockedAlice, blockedBob, version]
                );

                msc.stateRegister.sendTransaction(
                    vpc.address,
                    sid,
                    blockedAlice,
                    blockedBob,
                    version,
                    signatures.alice,
                    signatures.bob,
                    {from: aliceAddr}
                );

            } else if (event.event == "EventStateRegistering") {
                console.log("State registered from participant");

                // only Alice registered state 
                // conract in state 'InConflict'
                // register state for bob
                const sid = 10; 
                const blockedAlice = web3.toWei(10, "ether");
                const blockedBob = web3.toWei(10, "ether");
                const version = 0;

                signatures = generateSignatures(
                    ["address", "uint", "uint", "uint", "uint"],
                    [vpc.address, sid, blockedAlice, blockedBob, version]
                );


                msc.stateRegister.sendTransaction(
                    vpc.address,
                    sid,
                    blockedAlice,
                    blockedBob,
                    version,
                    signatures.alice,
                    signatures.bob,
                    {from: bobAddr}
                );

                
            } else if (event.event == "EventStateRegistered") {
                console.log("Both Participants registered their state: "+event.args.blockedAlice
                    +"-"+event.args.blockedBob);

                // Contract is now in state 'Settled'
                // alice interact with the vpc conract to establish a final distribution of funds
                // assume they shared a lot states offline and arrived at this final state
                const sid = 10; 
                const aliceCash = web3.toWei(7, "ether");
                const bobCash = web3.toWei(13, "ether");
                const version = 10;

                // id hash as input for next hash
                const id = abi.soliditySHA3(
                    ["address", "address", "uint"],
                    [aliceAddr, bobAddr, sid]
                );

                const leftPad = require("left-pad");
                // we pad our own hash here since the abi.soliditySHA3 function
                // does not work correctly with bytes32
                const msgHash = web3.sha3(
                    "0x" + id.toString("hex").concat(
                        leftPad(web3.toHex(version).slice(2), 64, 0),
                        leftPad(web3.toHex(aliceCash).slice(2), 64, 0),
                        leftPad(web3.toHex(bobCash).slice(2), 64, 0),
                    ),
                    {encoding: "hex"}
                );

                const aliceSig = web3.eth.sign(aliceAddr, msgHash);
                const bobSig = web3.eth.sign(bobAddr, msgHash);

                vpc.close.sendTransaction(
                    aliceAddr,
                    bobAddr,
                    sid,
                    version,
                    aliceCash,
                    bobCash,
                    aliceSig,
                    bobSig,
                    {from: aliceAddr}
                );

            } else if (event.event == "EventClosed") {
                console.log("Multi state channel closed!");

            } else {
                console.log("Unknown Event: "+event.event);
            }
        } else {
            console.log(error);
            process.exit();
        }
    });


    var events = vpc.allEvents({fromBlock: 0, toBlock: 'latest'});


    // vpc watcher
    events.watch(function(error, event) {
        if (!error) {

            if(event.event == "EventVpcClosing") {
                console.log("One participant started closing procedure for channel with id: " + event.args._id);

                // other participant closes the channel as well to speed things up
                // same input so we do not create a conflict
                const sid = 10; 
                const aliceCash = web3.toWei(7, "ether");
                const bobCash = web3.toWei(13, "ether");
                const version = 10;

                // id hash as input for next hash
                const id = abi.soliditySHA3(
                    ["address", "address", "uint"],
                    [aliceAddr, bobAddr, sid]
                );

                const leftPad = require("left-pad");
                // we pad our own hash here since the abi.soliditySHA3 function
                // does not work correctly with bytes32
                const msgHash = web3.sha3(
                    "0x" + id.toString("hex").concat(
                        leftPad(web3.toHex(version).slice(2), 64, 0),
                        leftPad(web3.toHex(aliceCash).slice(2), 64, 0),
                        leftPad(web3.toHex(bobCash).slice(2), 64, 0),
                    ),
                    {encoding: "hex"}
                );

                const aliceSig = web3.eth.sign(aliceAddr, msgHash);
                const bobSig = web3.eth.sign(bobAddr, msgHash);

                vpc.close.sendTransaction(
                    aliceAddr,
                    bobAddr,
                    sid,
                    version,
                    aliceCash,
                    bobCash,
                    aliceSig,
                    bobSig,
                    {from: bobAddr}
                );

            } else if (event.event == "EventVpcClosed") {
                console.log("Both parties closed the channel: "+event.args._id+
                    " with final distribution of funds:\n"+web3.fromWei(event.args.cashAlice, "ether")
                    +" Ether - "+web3.fromWei(event.args.cashBob, "ether")+" Ether");

                // now alice calls the execute function in MSContract to distribute the funds and delete the
                // contract
                msc.execute.sendTransaction(
                    aliceAddr,
                    bobAddr,
                    {from: aliceAddr}, function(err, txHash) {
                        if(err) {
                            console.log(err);
                        } else {
                            console.log("TX mined: "+txHash);
                        }
                    });

            } else {
                console.log("Unknown Event: "+event.event);
            }

        } else {
            console.log(error);
            process.exit();
        }
    });

}

// load web3, this assumes a running geth/parity instance
const Web3 = require('web3');
var web3;

if (typeof web3 !== 'undefined') {
  web3 = new Web3(web3.currentProvider);
} else {
  // set the provider you want from Web3.providers
  web3 = new Web3(new Web3.providers.HttpProvider("http://localhost:8545"));
}


const fs = require('fs');
const exec = require('child_process').execSync;

var lib = getContract("LibSignatures");

if(typeof lib == 'undefined'){
    console.log('lib undefined');
}


var aliceAddr = web3.eth.accounts[0];
var bobAddr = web3.eth.accounts[1];

console.log('account 1: '+aliceAddr);
console.log('account 2: '+bobAddr);

var timeoutInSec = 15000;

web3.personal.unlockAccount(aliceAddr, "password",timeoutInSec);
web3.personal.unlockAccount(bobAddr, "password",timeoutInSec);


// preload Bobs account
web3.eth.sendTransaction({
    from: aliceAddr, 
    to: bobAddr, 
    value: web3.toWei(10, "ether")}, function(err, transactionHash) {
  if (err)
    console.log(err);
});

lib = lib.contract.new(
   {
     from: aliceAddr, 
     data: lib.code, 
     gas: '2000000'
   }, function (e, contract){
    if(e)
        console.log(e);
    if (typeof contract.address !== 'undefined') {
        console.log('Contract mined! address: ' + contract.address + ' transactionHash: ' + contract.transactionHash);
        lib = contract;
        deployVPC(contract.address);
    }
 });
