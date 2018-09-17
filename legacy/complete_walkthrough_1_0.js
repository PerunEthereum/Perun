const utils = require('ethereumjs-util');
const abi = require('ethereumjs-abi');

let gasUsedTotal = 0;
let functionCalls = [];

async function generateSignatures(hash) {
    const sigAlice = await web3.eth.personal.sign(hash, aliceAddr, "");
    //web3.eth.sign(hash,aliceAddr);
    const sigBob = await web3.eth.personal.sign(hash, bobAddr, "");
    //web3.eth.sign(hash,bobAddr);
    return {
        alice: sigAlice,
        bob: sigBob
    };
}

//Helper function to add a timeout
function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function called(label, gasUsed){
    gasUsedTotal += gasUsed;
    var priceWEI = gasUsed * gasPrice;
    var priceETH = web3.utils.fromWei(String(priceWEI), "ether");
    var priceUSD = priceETH * 400;
    functionCalls.push(label + "\t: " + gasUsed + "\t " + priceETH + "\t" + priceUSD);
}

function overview(){
    var priceWEI = gasUsedTotal * gasPrice;
    var priceETH = web3.utils.fromWei(String(priceWEI), "ether");
    var priceUSD = priceETH * 400;
    console.log("---------");
    console.log("Function name \t: gas used \t price in ETH \t price in USD")
    console.log("Total gas used\t: " + gasUsedTotal + "\t " + priceETH + "\t" + priceUSD);
    for(let i = 0; i < functionCalls.length; ++i)
        console.log(functionCalls[i]); "\t"
    console.log("---------");
}

//Compiles the smart contract
function getContract(contractName) {
    exec('solc --bin --abi --optimize --overwrite -o build/ contracts/'+contractName+'.sol');

    var code = "0x" + fs.readFileSync("build/" + contractName + ".bin");
    var abi = fs.readFileSync("build/" + contractName + ".abi");
    return {
        abi: abi,
        code: code
    };
}

function deployLibSig(){
    var lib = getContract("LibSignatures");
    var contract = new web3.eth.Contract(
        JSON.parse(lib.abi), 
        {from: aliceAddr, data: lib.code, gas: '200000000'});

    var cntr = contract.deploy({
         data: lib.code
    });
    var estGas = '4000000'
    cntr.estimateGas(function(err, gas){
        called("deployCostLibSig", gas);
        estGas = gas + '20000';
    });

    cntr.send(
        {   from: aliceAddr,
            gas: estGas}
        , function (e, contract){
           if(e){
            console.log(e);
           }
           if (typeof contract.address !== 'undefined') {
               console.log('Contract mined! address: ' + contract.address + 
                ' transactionHash: ' + contract.transactionHash);
           }
     }).then(async function(newContractInstance){
        console.log('Signature library deployed');
        deployVPC(newContractInstance);
    }).catch((error) => {console.log(error)});
}


function deployVPC(libAddress) {
    var vpc = getContract("VPC");

    var contract = new web3.eth.Contract(
        JSON.parse(vpc.abi), 
        {from: aliceAddr, data: vpc.code, gas: '200000000'});

    var cntr = contract.deploy({
         data: lib.code,
         arguments: [libAddress.options.address]
    });
    var estGas = '4000000'
    cntr.estimateGas(function(err, gas){
        called("deployCostVPC", gas);
        estGas = gas + '20000';
    });
    cntr.send(
        {   from: aliceAddr,
            gas: estGas}
        , function (e, contract){
           if(e){
            console.log(e);
           }
           if (typeof contract.address !== 'undefined') {
               console.log('Contract mined! address: ' + contract.address + 
                ' transactionHash: ' + contract.transactionHash);
           }
     }).then(async function(newContractInstance){
        console.log('VPC deployed at '+ newContractInstance.options.address);
        deployMSContract(libAddress, newContractInstance);
    }).catch((error) => {console.log(error)});
}

function deployMSContract(libAddress, vpc) {
    var msc = getContract("MSContract");

    var contract = new web3.eth.Contract(
        JSON.parse(msc.abi), 
        {from: aliceAddr, data: msc.code, gas: '200000000'});
    contract.deploy({
         data: msc.code,
         arguments: [libAddress.options.address, aliceAddr, bobAddr ]
     }).send(
        {   from: aliceAddr,
            gas: '2000000'}
        , function (e, contract){
           if(e){
            console.log(e);
           }
           if (typeof contract.address !== 'undefined') {
               console.log('Contract mined! address: ' + contract.address + ' transactionHash: ' + contract.transactionHash);
           }
     }).then(function(newContractInstance){
        console.log('MSContract deployed');
        runSimulation(newContractInstance,vpc);
    });
}

function runSimulation(msc, vpc) {
    var initialized = false;
    var events = msc.events.allEvents({fromBlock: 0, toBlock: 'latest'},
        (async function(error, event) {
        if (!error) {
            if(event.event == "EventInitializing") {
                if (!initialized) {
                    initialized = true;
                    console.log("Channel Initialized for alice: "+
                        event.returnValues.addressAlice+" bob: "+
                        event.returnValues.addressBob);

                    resp = msc.methods.confirm();
                    snd = await resp.send(
                    {   from: aliceAddr,
                        gas: '2000000',
                        gasPrice: '1',
                        value: web3.utils.toWei("10", "ether")
                    }).catch((error) => {console.log(error)});
                    called("confirm_alice", snd.gasUsed);

                    resp = msc.methods.confirm();
                    snd = await resp.send(
                    {   from: bobAddr,
                        gas: '2000000',
                        gasPrice: '1',
                        value: web3.utils.toWei("10", "ether")
                    }).catch((error) => {console.log(error)});
                    called("confirm_bob", snd.gasUsed);
                }
            } else if (event.event == "EventInitialized") {
                console.log("Both Parties confirmed alice put in: "+
                    web3.utils.fromWei(event.returnValues.cashAlice, "ether")+" bob: "+
                    web3.utils.fromWei(event.returnValues.cashBob, "ether"));

                // we assume both parties have agreed on these parameters here
                const sid = 10;
                const blockedAlice = web3.utils.toWei("10", "ether");
                const blockedBob = web3.utils.toWei("10", "ether");
                const version = 1;

                hash = await web3.utils.soliditySha3(
                    {type: 'address', value: vpc.options.address},
                    {type: 'uint', value: sid},
                    {type: 'uint', value: blockedAlice},
                    {type: 'uint', value: blockedBob},
                    {type: 'uint', value: version});
                signatures = await generateSignatures(hash);

                resp = msc.methods.stateRegister(
                    vpc.options.address,
                    sid,
                    blockedAlice,
                    blockedBob,
                    version,
                    signatures.alice,
                    signatures.bob);
                snd = await resp.send(
                {   from: aliceAddr,
                    gas: '2000000',
                    gasPrice: '1'
                }).catch((error) => {console.log(error)});
                called("stateRegister_alice", snd.gasUsed);

            } else if (event.event == "EventStateRegistering") {
                console.log("State registered from participant");

                // only Alice registered state 
                // conract in state 'InConflict'
                // register state for bob
                const sid = 10; 
                const blockedAlice = web3.utils.toWei("10", "ether");
                const blockedBob = web3.utils.toWei("10", "ether");
                const version = 1;

                hash = await web3.utils.soliditySha3(
                    {type: 'address', value: vpc.options.address},
                    {type: 'uint', value: sid},
                    {type: 'uint', value: blockedAlice},
                    {type: 'uint', value: blockedBob},
                    {type: 'uint', value: version});
                signatures = await generateSignatures(hash);

                resp = msc.methods.stateRegister(
                    vpc.options.address,
                    sid,
                    blockedAlice,
                    blockedBob,
                    version,
                    signatures.alice,
                    signatures.bob);
                snd = await resp.send(
                {   from: bobAddr,
                    gas: '2000000',
                    gasPrice: '1'
                }).catch((error) => {console.log(error)});
                called("stateRegister_bob", snd.gasUsed);

                
            } else if (event.event == "EventStateRegistered") {
                console.log("Both Participants registered their state: "+
                    event.returnValues.blockedAlice+"-"+event.returnValues.blockedBob);

                // Contract is now in state 'Settled'
                // alice interact with the vpc conract to establish a final distribution of funds
                // assume they shared a lot states offline and arrived at this final state
                const sid = 10; 
                const aliceCash = web3.utils.toWei("7", "ether");
                const bobCash = web3.utils.toWei("13", "ether");
                const version = 10;

                // id hash as input for next hash
                const id = await web3.utils.soliditySha3(aliceAddr, bobAddr, sid);

                hash = await web3.utils.soliditySha3(
                    {type: 'bytes32', value: id},
                    {type: 'uint', value: version},
                    {type: 'uint', value: aliceCash},
                    {type: 'uint', value: bobCash});
                signatures = await generateSignatures(hash);
                sleep(100);
                console.log(vpc.options.address);
                resp = vpc.methods.close(
                    aliceAddr,
                    bobAddr,
                    sid,
                    version,
                    aliceCash,
                    bobCash,
                    signatures.alice,
                    signatures.bob);
                //console.log(await resp.estimateGas());
                
                snd = await resp.send(
                {   from: aliceAddr,
                    gas: '2000000',
                    gasPrice: '1'
                }).catch((error) => {console.log(error)});
                called("close_alice", snd.gasUsed);
                overview();
            } else if (event.event == "EventClosed") {
                console.log("Multi state channel closed!");
                overview();
                process.exit();

            }else if(event.event == "Event_Data"){
                console.log("Data: "+event.returnValues.a+
                    " : "+event.returnValues.data);

            }else {
                console.log("Unknown Event: "+event.event);
            }
        } else {
            console.log(error);
            process.exit();
        }
    }));


    var events = vpc.events.allEvents({fromBlock: 0, toBlock: 'latest'},
    (async function(error, event) {
        if (!error) {
            console.log(event.event);
            if(event.event == "EventVpcClosing") {
                console.log("One participant started closing procedure for channel with id: "
                 + event.returnValues._id);

                // other participant closes the channel as well to speed things up
                // same input so we do not create a conflict
                const sid = 10; 
                const aliceCash = web3.utils.toWei("7", "ether");
                const bobCash = web3.utils.toWei("13", "ether");
                const version = 10;

                // id hash as input for next hash
                const id = await web3.utils.soliditySha3(aliceAddr, bobAddr, sid);
                
                hash = await web3.utils.soliditySha3(
                    {type: 'bytes32', value: id},
                    {type: 'uint', value: version},
                    {type: 'uint', value: aliceCash},
                    {type: 'uint', value: bobCash});
                signatures = await generateSignatures(hash);

                resp = vpc.methods.close(
                    aliceAddr,
                    bobAddr,
                    sid,
                    version,
                    aliceCash,
                    bobCash,
                    signatures.alice,
                    signatures.bob);
                snd = await resp.send(
                {   from: bobAddr,
                    gas: '2000000',
                    gasPrice: '1'
                }).catch((error) => {console.log(error)});
                called("close_bob", snd.gasUsed);

            } else if (event.event == "EventVpcClosed") {
                console.log("Both parties closed the channel: "+event.returnValues._id+
                    " with final distribution of funds:\n"+
                    web3.utils.fromWei(event.returnValues.cashAlice, "ether")
                    +" Ether - "+web3.utils.fromWei(event.returnValues.cashBob, "ether")+
                    " Ether");
                // now alice calls the execute function in MSContract 
                // to distribute the funds and delete the contract
                
                resp = msc.methods.execute(
                    aliceAddr,
                    bobAddr);
                snd = await resp.send(
                {   from: aliceAddr,
                    gas: '2000000',
                    gasPrice: '1'
                }).catch((error) => {console.log(error)});
                called("close_bob", snd.gasUsed);

            } else {
                console.log("Unknown Event: "+event.event);
            }
        } else {
            console.log(error);
            process.exit();
        }
    }));

}

// load web3, this assumes a running geth/parity instance
const Web3 = require('web3');
const Personal = require('web3-eth-personal');
var net = require('net');
var web3;
var personal;
if (typeof web3 !== 'undefined') {
  web3 = new Web3(web3.currentProvider);
} else {
  // set the provider you want from Web3.providers
  web3 = new Web3(Web3.givenProvider || new Web3.providers.WebsocketProvider("ws://localhost:8545"));
  var web3 = new Web3('/tmp/geth.ipc', net); // same output as with option below
}
const fs = require('fs');
const exec = require('child_process').execSync;
var lib = getContract("LibSignatures");

if(typeof lib == 'undefined'){
    console.log('lib undefined');
}

var aliceAddr;
var bobAddr;
web3.eth.getAccounts(async function(error, result) {
    if(error != null)
        console.log("Couldn't get accounts: "+ error);
    aliceAddr = result[0];
    bobAddr = result[1];
    var block = web3.eth.getBlock("latest");
    console.log('account 1: '+aliceAddr);
    console.log('account 2: '+bobAddr);
    gasPrice = web3.utils.toWei("4", "gwei");
    var timeoutInSec = 15000;

    await web3.eth.personal.unlockAccount(aliceAddr, "",timeoutInSec);
    await web3.eth.personal.unlockAccount(bobAddr, "",timeoutInSec);

    await web3.eth.sendTransaction({
        from: aliceAddr, 
        to: bobAddr, 
        value: web3.utils.toWei("20", "ether"), function(err, transactionHash) {
            if (err)
                console.log(err);
        }});

    aliceMoney = await web3.eth.getBalance(aliceAddr);
    bobMoney = await web3.eth.getBalance(bobAddr);

    deployLibSig();
});




