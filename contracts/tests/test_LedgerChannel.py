from datetime import timedelta, datetime
from collections import defaultdict
import pytest
from utils import *

@pytest.fixture()
def balance(web3, parties):
    return [web3.eth.getBalance(party) for party in parties]

@pytest.fixture()
def costs():
    return defaultdict(int)

def deploy_lc(chain, parties, sender, other, libSignaturesAddr, costs, value=0):
    lc = chain.provider.deploy_contract('LedgerChannel', deploy_transaction={'from': parties[sender], 'value': value}, deploy_args=[parties[other], lcId, libSignaturesAddr])
    txn = chain.wait.for_receipt(lc[1])
    costs[sender] += txn.gasUsed
    print(party_name[sender] + ':', "lc deploy cost: ", txn.gasUsed)
    return lc[0]

@pytest.fixture()
def lsm(chain, setup):
    return chain.provider.get_or_deploy_contract('LibSignaturesMock')[0].address

def check_balance(web3, expected):
    for party, exp_bal in expected:
        assert abs(exp_bal - web3.eth.getBalance(web3.eth.accounts[party])) < 10**7

def check_lc_balance(web3, chain, lc, expected, parties=[alice, bob]):
    for party, name in zip(parties, ['alice', 'bob']):
        assert call_transaction(web3, chain, lc, 'lc', name, party, arguments=[], transact=False)[0][2] == expected[party]

def check_total_transfers(web3, chain, lc, expected, parties=[alice, bob]):
    for party, name in zip(parties, ['alice', 'bob']):
        assert call_transaction(web3, chain, lc, 'lc', name, party, arguments=[], transact=False)[0][1] == expected[party]

def check_vc_balance(web3, chain, lc, vid, expected, parties=[alice, bob]):
    vc = call_transaction(web3, chain, lc, 'lc', 'virtual', parties[0], arguments=[vid], transact=False)[0]
    assert vc[1] == expected[parties[0]]
    assert vc[5] == expected[parties[1]]


def test_LC_honest_simple(web3, chain, parties, lsm, balance, costs):
    lc = deploy_lc(chain, parties, alice, bob, lsm, costs, cash[alice])
    call_transaction(web3, chain, lc, 'lc', 'LCOpen', bob, arguments=[], value=cash[bob], costs=costs)
    check_balance(web3, [(p, balance[p] - cash[p]) for p in [alice, bob]])
    check_lc_balance(web3, chain, lc, cash)
    for party in [alice, bob]:
        call_transaction(web3, chain, lc, 'lc', 'LCClose', party, arguments=[cash[alice], cash[bob], version, sig], costs=costs)
    check_balance(web3, [(p, balance[p]) for p in [alice, bob]])
    print_costs(costs, 'LC Honest simple')

'''
def test_LC_vpc_honest_all(web3, chain, parties, lsm, balance, setup, costs):
    users = [[alice, ingrid], [ingrid, bob]]
    cashs = [{alice: 33 * 10**9, ingrid: 88 * 10**9}, {ingrid: 77 * 10**9, bob: 21 * 10**9}]
    change = [10 * 10**9, 13 * 10**9]
    lcs = []
    for lcId, u in enumerate(users):
        lcs.append(deploy_lc(chain, parties, u[0], u[1], lsm, costs, cashs[lcId][u[0]]))
    minus = {alice: cashs[0][alice], bob: 0, ingrid: cashs[1][ingrid]}
    check_balance(web3, [(p, balance[p] - minus[p]) for p in [alice, bob, ingrid]])

    for lc, cash, u in zip(lcs, list(cashs), users):
        call_transaction(web3, chain, lc, 'lc', 'LCOpen', u[1], arguments=[], value=cash[u[1]], costs=costs)
        check_lc_balance(web3, chain, lc, cash, parties=u)

#        for party in u:
#            call_transaction(web3, chain, lc, 'lc', 'stateRegister', party, arguments=[nid, vpc.address, sid] + vpc_parties(web3) + change + [version] + ['\x01'] * 2, costs=costs)
    minus = {alice: cashs[0][alice], bob: cashs[1][bob], ingrid: cashs[0][ingrid] + cashs[1][ingrid]}
    check_balance(web3, [(p, balance[p] - minus[p]) for p in [alice, bob, ingrid]])
    for party in [alice, bob]:
        call_transaction(web3, chain, vpc, 'vpc', 'close', party, arguments=vpc_parties(web3) + [sid, version] + change[::-1] + ['\x01'] * 2, costs=costs)
    check_balance(web3, [(p, balance[p] - minus[p]) for p in [alice, bob, ingrid]])
    for lc, cash, u in zip(lcs, list(cashs), users):
        call_transaction(web3, chain, lc, 'lc', 'execute', ingrid, arguments=[nid], costs=costs)
        for party in u:
            call_transaction(web3, chain, lc, 'lc', 'close', party, arguments=[], costs=costs)

    difference = {alice: -change[0] + change[1], ingrid: 0, bob: change[0] - change[1]}
    check_balance(web3, [(p, balance[p] + difference[p]) for p in [alice, bob, ingrid]])
    print_costs(costs, 'LC Honest all')
'''

def test_LC_refund(web3, chain, parties, lsm, balance, costs):
    lc = deploy_lc(chain, parties, alice, bob, lsm, costs, cash[alice])
    check_balance(web3, [(p, balance[p] - cash[p]) for p in [alice]])
    t = datetime.now()
    t = move_time(web3, t, timedelta(minutes=60))
    call_transaction(web3, chain, lc, 'lc', 'LCOpenTimeout', alice, arguments=[])
    check_balance(web3, [(p, balance[p] - cash[p]) for p in [alice]])
    t = move_time(web3, t, timedelta(minutes=60))
    call_transaction(web3, chain, lc, 'lc', 'LCOpenTimeout', alice, arguments=[], costs=costs)
    check_balance(web3, [(p, balance[p]) for p in [alice]])
    print_costs(costs, 'LC Refund')

def test_LC_CloseTimeout(web3, chain, parties, lsm, balance, costs):
    lc = deploy_lc(chain, parties, alice, bob, lsm, costs, cash[alice])
    call_transaction(web3, chain, lc, 'lc', 'LCOpen', bob, arguments=[], value=cash[bob], costs=costs)
    call_transaction(web3, chain, lc, 'lc', 'LCClose', bob, arguments=[cash2[alice], cash2[bob], version, sig], costs=costs)
    t = datetime.now()
    t = move_time(web3, t, timedelta(minutes=200))
    call_transaction(web3, chain, lc, 'lc', 'LCCloseTimeout', bob, arguments=[])
    check_balance(web3, [(p, balance[p] - cash[p]) for p in [alice, bob]])
    t = move_time(web3, t, timedelta(minutes=200))
    call_transaction(web3, chain, lc, 'lc', 'LCCloseTimeout', bob, arguments=[], costs=costs)
    check_balance(web3, [(p, balance[p] - cash[p] + cash2[p]) for p in [alice, bob]])
    print_costs(costs, 'LC CloseTimeout')

def test_LC_VCActive(web3, chain, parties, lsm, balance, costs):
    lc = deploy_lc(chain, parties, alice, ingrid, lsm, costs, cash[alice])
    call_transaction(web3, chain, lc, 'lc', 'LCOpen', ingrid, arguments=[], value=cash[bob], costs=costs)
    call_transaction(web3, chain, lc, 'lc', 'LCClose', ingrid, arguments=[cash2[alice], cash2[bob], version, sig], costs=costs)
    validity = int(datetime.now().timestamp())
    call_transaction(web3, chain, lc, 'lc', 'VCActive', alice, arguments=[vid, parties[alice], cashSmall[alice], lcId, parties[ingrid],
                                                                               parties[bob], cashSmall[bob], lcId+1, validity, sig], costs=costs)
    check_balance(web3, [(alice, balance[alice] + cash[bob]), (ingrid, balance[ingrid] - cash[bob])])
    print_costs(costs, 'LC VCActive')

def test_LC_VCCloseInit_VCAlreadyClosed(web3, chain, parties, lsm, balance, costs):
    lc = deploy_lc(chain, parties, alice, ingrid, lsm, costs, cashI[alice])
    call_transaction(web3, chain, lc, 'lc', 'LCOpen', ingrid, arguments=[], value=cashI[ingrid], costs=costs)
    validity = int(datetime.now().timestamp())
    call_transaction(web3, chain, lc, 'lc', 'VCCloseInit', ingrid, arguments=[vid, parties[alice], cashSmall[alice], lcId, parties[ingrid],
                                                                                   parties[bob], cashSmall[bob], lcId+1, validity, sig], costs=costs)
    check_vc_balance(web3, chain, lc, vid, cashSmallI, [alice, ingrid])
    call_transaction(web3, chain, lc, 'lc', 'VCAlreadyClosed', alice, arguments=[vid, sig], costs=costs)
    check_balance(web3, [(alice, balance[alice] + cashI[ingrid]), (ingrid, balance[ingrid] - cashI[ingrid])])
    print_costs(costs, 'LC VCCloseInit -> VCAlreadyClosed')

def test_LC_VCCloseInit_VCCloseInitTimeout(web3, chain, parties, lsm, balance, costs):
    lc = deploy_lc(chain, parties, alice, ingrid, lsm, costs, cash[alice])
    call_transaction(web3, chain, lc, 'lc', 'LCOpen', ingrid, arguments=[], value=cashI[ingrid], costs=costs)
    validity = int(datetime.now().timestamp())
    call_transaction(web3, chain, lc, 'lc', 'VCCloseInit', ingrid, arguments=[vid, parties[alice], cashSmall[alice], lcId, parties[ingrid],
                                                                                   parties[bob], cashSmall[bob], lcId+1, validity, sig], costs=costs)
    check_vc_balance(web3, chain, lc, vid, cashSmallI, [alice, ingrid])
    check_balance(web3, [(p, balance[p] - cashI[p]) for p in [alice, ingrid]])
    t = datetime.now()
    t = move_time(web3, t, timedelta(minutes=60))
    call_transaction(web3, chain, lc, 'lc', 'VCCloseInitTimeout', ingrid, arguments=[vid])
    check_vc_balance(web3, chain, lc, vid, cashSmallI, [alice, ingrid])
    check_balance(web3, [(p, balance[p] - cashI[p]) for p in [alice, ingrid]])
    t = move_time(web3, t, timedelta(minutes=60))
    call_transaction(web3, chain, lc, 'lc', 'VCCloseInitTimeout', ingrid, arguments=[vid], costs=costs)
    check_balance(web3, [(alice, balance[alice] - cashI[alice]), (ingrid, balance[ingrid] + cashI[alice])])
    print_costs(costs, 'LC VCCloseInit -> VCCloseInitTimeout')

def test_LC_VCCloseInit_VCClose_VCCloseFinal_VCCloseFinalTimeout(web3, chain, parties, lsm, balance, costs):
    lc = deploy_lc(chain, parties, alice, ingrid, lsm, costs, cash[alice])
    call_transaction(web3, chain, lc, 'lc', 'LCOpen', ingrid, arguments=[], value=cashI[ingrid], costs=costs)
    validity = int(datetime.now().timestamp())
    check_lc_balance(web3, chain, lc, cash)
    call_transaction(web3, chain, lc, 'lc', 'VCCloseInit', ingrid, arguments=[vid, parties[alice], cashSmall[alice], lcId, parties[ingrid],
                                                                                   parties[bob], cashSmall[bob], lcId+1, validity, sig], costs=costs)
    check_vc_balance(web3, chain, lc, vid, cashSmallI, [alice, ingrid])
    call_transaction(web3, chain, lc, 'lc', 'VCClose', alice, arguments=[vid, cashSmall2[alice], cashSmall2[bob], version, sig, sig], costs=costs)
    call_transaction(web3, chain, lc, 'lc', 'VCCloseFinal', ingrid, arguments=[vid, cashSmall2[alice], cashSmall2[bob], version, sig, sig,
                                                                                   cashSmall[alice], cashSmall[bob], version-1, sig, sig], costs=costs)
    t = datetime.now()
    t = move_time(web3, t, timedelta(minutes=60))
    call_transaction(web3, chain, lc, 'lc', 'VCCloseFinalTimeout', ingrid, arguments=[vid])
    check_total_transfers(web3, chain, lc, zero, [alice, ingrid])
    t = move_time(web3, t, timedelta(minutes=60))
    call_transaction(web3, chain, lc, 'lc', 'VCCloseFinalTimeout', ingrid, arguments=[vid], costs=costs)
    check_total_transfers(web3, chain, lc, cashSmallDiffI, [alice, ingrid])
    for party in [alice, ingrid]:
        call_transaction(web3, chain, lc, 'lc', 'LCClose', party, arguments=[cashI[alice], cashI[ingrid], version, sig], costs=costs)
    check_balance(web3, [(p, balance[p] - cashSmallI[p] + cashSmall2I[p]) for p in [alice, ingrid]])
    print_costs(costs, 'LC VCCloseInit -> VCClose -> VCCloseFinal -> VCCloseFinalTimeout')

def test_LC_VCCloseInit_VCCloseTimeout_VCClosedTimeoutTimeout(web3, chain, parties, lsm, balance, costs):
    lc = deploy_lc(chain, parties, alice, ingrid, lsm, costs, cash[alice])
    call_transaction(web3, chain, lc, 'lc', 'LCOpen', ingrid, arguments=[], value=cashI[ingrid], costs=costs)
    validity = int(datetime.now().timestamp())
    check_lc_balance(web3, chain, lc, cash)
    call_transaction(web3, chain, lc, 'lc', 'VCCloseInit', ingrid, arguments=[vid, parties[alice], cashSmall[alice], lcId, parties[ingrid],
                                                                                   parties[bob], cashSmall[bob], lcId+1, validity, sig], costs=costs)
    t = datetime.now()
    t = move_time(web3, t, timedelta(minutes=120))
    vc = call_transaction(web3, chain, lc, 'lc', 'virtual', alice, arguments=[vid], transact=False)[0]
    call_transaction(web3, chain, lc, 'lc', 'VCCloseTimeout', alice, arguments=[vid, parties[alice], cashSmall[alice], lcId, parties[ingrid],
                                                                                     parties[bob], cashSmall[bob], lcId+1, validity, sig], costs=costs)
    assert vc == call_transaction(web3, chain, lc, 'lc', 'virtual', alice, arguments=[vid], transact=False)[0]
    t = move_time(web3, t, timedelta(minutes=120))
    call_transaction(web3, chain, lc, 'lc', 'VCCloseTimeout', alice, arguments=[vid, parties[alice], cashSmall[alice], lcId, parties[ingrid],
                                                                                     parties[bob], cashSmall[bob], lcId+1, validity, sig], costs=costs)
    assert vc != call_transaction(web3, chain, lc, 'lc', 'virtual', alice, arguments=[vid], transact=False)[0]
    vc = call_transaction(web3, chain, lc, 'lc', 'virtual', alice, arguments=[vid], transact=False)[0]
    t = move_time(web3, t, timedelta(minutes=60))
    call_transaction(web3, chain, lc, 'lc', 'VCCloseTimeoutTimeout', alice, arguments=[vid], costs=costs)
    assert vc == call_transaction(web3, chain, lc, 'lc', 'virtual', alice, arguments=[vid], transact=False)[0]
    t = move_time(web3, t, timedelta(minutes=60))
    call_transaction(web3, chain, lc, 'lc', 'VCCloseTimeoutTimeout', alice, arguments=[vid], costs=costs)
    check_balance(web3, [(alice, balance[alice] + cashI[ingrid]), (ingrid, balance[ingrid] - cashI[ingrid])])
    print_costs(costs, 'LC VCCloseInit -> VCCloseTimeout -> VCClosedTimeoutTimeout')

def test_LC_VCCloseTimeout_VCAlreadyClosed(web3, chain, parties, lsm, balance, costs):
    lc = deploy_lc(chain, parties, alice, ingrid, lsm, costs, cash[alice])
    call_transaction(web3, chain, lc, 'lc', 'LCOpen', ingrid, arguments=[], value=cashI[ingrid], costs=costs)
    validity = int(datetime.now().timestamp())
    check_lc_balance(web3, chain, lc, cash)
    vc = call_transaction(web3, chain, lc, 'lc', 'virtual', alice, arguments=[vid], transact=False)[0]
    call_transaction(web3, chain, lc, 'lc', 'VCCloseTimeout', alice, arguments=[vid, parties[alice], cashSmall[alice], lcId, parties[ingrid],
                                                                                     parties[bob], cashSmall[bob], lcId+1, validity, sig], costs=costs)
    assert vc == call_transaction(web3, chain, lc, 'lc', 'virtual', alice, arguments=[vid], transact=False)[0]
    t = datetime.now()
    t = move_time(web3, t, timedelta(minutes=240))
    call_transaction(web3, chain, lc, 'lc', 'VCCloseTimeout', alice, arguments=[vid, parties[alice], cashSmall[alice], lcId, parties[ingrid],
                                                                                     parties[bob], cashSmall[bob], lcId+1, validity, sig], costs=costs)
    assert vc != call_transaction(web3, chain, lc, 'lc', 'virtual', alice, arguments=[vid], transact=False)[0]
    call_transaction(web3, chain, lc, 'lc', 'VCAlreadyClosed', ingrid, arguments=[vid, sig], costs=costs)
    check_balance(web3, [(alice, balance[alice] - cashI[alice]), (ingrid, balance[ingrid] + cashI[alice])])
    print_costs(costs, 'LC VCCloseTimeout -> VCAlreadyClosed')


