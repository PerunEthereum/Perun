import pytest

account = '0xd0edc0d7073c2931edbadbdcab6b67ea4929a110'
message = '0xdeadbeef'

@pytest.fixture()
def libSignaturesMock(chain):
    return chain.provider.get_or_deploy_contract('LibSignaturesMock')[0]

def test_LibSignatures_ok(libSignaturesMock):
    assert libSignaturesMock.call().verify(account, message, '\x01') == True

def test_LibSignatures_wrong(libSignaturesMock):
    assert libSignaturesMock.call().verify(account, message, '\x00') == False

