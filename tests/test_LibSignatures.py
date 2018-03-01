import pytest

accounts = ['0xd0edc0d7073c2931edbadbdcab6b67ea4929a110', '0xa7183ed8bd8961a004f2213daa307386a49745d7', '0xa5b40bbbe0cc5f7f9ce2fae5aa0e3572a55bd02c']
messages = ['0123456789', '', 'test' * 100]
signatures = ['0xa03cdc8c0af5867cb0d97d0fd23ff54fc792c9537adcbd71148172b77b079336697d0a12245d8797e5266d2e81aa6908490bad393a950d0572c1a483fb4f26341c',
              '0x40afe208deede24693c3e459e5d3a26013d2f0fa7322a2695e5a7dd70032917f56e7da6e44541432fa5c669ffcac95846e204e3624876a97b550703f69eb39bb1b',
              '0xd3c8f0adf9782c251a31fbf1e83c5e4ab36940b59d5f175fb7ccbe89e5079d2c434eefa46d8d129f04ac15a6236f165debee07334898036262c36ef39247829a1b']

@pytest.fixture()
def libSignatures(chain):
    return chain.provider.get_or_deploy_contract('LibSignatures')[0]

def add_prefix(message):
    return '\x19Ethereum Signed Message:\n' + str(len(message)) + message

def prepare_message(web3, message):
    return web3.toAscii(web3.sha3(web3.toHex(add_prefix(message))))

def generic_test_LibSignatures(libSignatures, account, message, signature, result):
    assert libSignatures.call().verify(account, message, signature) == result

def test_LibSignatures_ok(web3, libSignatures):
    for acc, mess, sig in zip(accounts, messages, signatures):
        generic_test_LibSignatures(libSignatures, acc, prepare_message(web3, mess), web3.toAscii(sig), True)

def test_LibSignatures_wrong(web3, libSignatures):
    wrong_accounts = accounts[1:] + [accounts[0]]
    for acc, mess, sig in zip(wrong_accounts, messages, signatures):
        generic_test_LibSignatures(libSignatures, acc, prepare_message(web3, mess), web3.toAscii(sig), False)
