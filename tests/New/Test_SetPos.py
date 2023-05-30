import pytest
from brownie import (accounts, 
                    Contract, 
                    chain,
                    MockToken, PoolFactory, Pool, NFT, NFTManager, HelpFunctions)

@pytest.fixture
def deployLibrary():
    libDeployer =accounts[9]

    lib = HelpFunctions.deploy({"from":libDeployer})
    # print contract address
    print(f"Lib contract deployed at {lib}")
    return lib

@pytest.fixture
def Atoken():
    # fetch the account
    account = accounts[0]

    # deploy contract
    Atoken = MockToken.deploy("TokenA","TA",18,{"from":account})
    # print contract address
    print(f"Token contract deployed at {Atoken}")

    return Atoken

@pytest.fixture
def Btoken():
    # fetch the account
    account = accounts[0]

    # deploy contract
    Btoken = MockToken.deploy("TokenB","TB",18,{"from":account})
    # print contract address
    print(f"Token contract deployed at {Btoken}")
    return Btoken

@pytest.fixture
def Xtoken():
    # fetch the account
    account = accounts[0]

    # deploy contract
    Xtoken = MockToken.deploy("TokenX","TX",18,{"from":account})
    # print contract address
    print(f"Token contract deployed at {Xtoken}")
    return Xtoken

@pytest.fixture
def Ytoken():
    # fetch the account
    account = accounts[0]

    # deploy contract
    Ytoken = MockToken.deploy("TokenY","TY",18,{"from":account})
    # print contract address
    print(f"Token contract deployed at {Ytoken}")
    return Ytoken

@pytest.fixture
def factoryContract():
    # fetch the account
    account = accounts[0]

    # deploy Staking contract
    factory = PoolFactory.deploy({"from":account})
    # print contract address
    print(f"Factory contract deployed at {factory}")
    return factory

@pytest.fixture
def NFTContract(factoryContract, deployLibrary):
    # fetch the account
    account = accounts[0]

    # deploy Staking contract
    nft = NFT.deploy(factoryContract, {"from":account})
    # print contract address
    print(f"NFT contract deployed at {nft}")
    return nft

@pytest.fixture
def managerContract(factoryContract, NFTContract, deployLibrary):
    # fetch the account
    account = accounts[0]

    # deploy Staking contract
    manager = NFTManager.deploy(factoryContract, NFTContract, {"from":account})
    # print contract address
    print(f"Factory contract deployed at {manager}")
    return manager

@pytest.fixture
def ABPool(Atoken, Btoken, factoryContract):
    
    # fetch the account
    account = accounts[0]
    
    #Variables
    feeAB=500

    #Create pool AB
    poolCreation = factoryContract.createPool(Atoken, 
                                            Btoken,
                                            feeAB,
                                            {"from": account})
                                            
    poolAB_address = poolCreation.events['PoolCreated']['pool']

    print("Pool Created at ", poolAB_address)

    assert poolAB_address == factoryContract.pools(Atoken, Btoken, 500)

    #Turn pool address into a contract
    poolABI = Pool.abi
    ABPool = Contract.from_abi("Pool", poolAB_address, poolABI)

    return ABPool

@pytest.fixture
def XYPool(Xtoken, Ytoken, factoryContract):
    
    # fetch the account
    account = accounts[0]
    
    #Variables
    feeXY=500

    #Create pool XY
    poolCreation = factoryContract.createPool(Xtoken, 
                                            Ytoken,
                                            feeXY,
                                            {"from": account})

    poolXY_address = poolCreation.events['PoolCreated']['pool']

    print("Pool Created at ", poolXY_address)

    #Turn pool address into a contract
    poolABI = Pool.abi
    XYPool = Contract.from_abi("Pool", poolXY_address, poolABI)

    return XYPool

'''
Tests the minting, checking ownership and data, and burning positions within range
'''
def test_inRange(Atoken, Btoken, NFTContract, managerContract, deployLibrary, ABPool):
    # fetch the accounts
    account = accounts[0]

    #Fund the users
    Alice = accounts[1]
    Atoken.mint(Alice, 100000*10**18,{"from": account})
    Btoken.mint(Alice, 100000*10**18,{"from": account})

    #Variables
    fraq=2**96
    initP_AB=5000

    #Initialize pool AB
    ABPool.initialize(initP_AB, {"from": account})
    print("Slot0:",ABPool.slot0({"from": account}))
    assert ABPool.slot0({"from": account})[0] != (0)


    #First alice position
    Atoken.approve(NFTContract, 1*10**18, {"from": Alice})
    Btoken.approve(NFTContract, 5000*10**18, {"from": Alice})

    chain.sleep(30)
    pos = NFTContract.mint([Alice, Atoken, Btoken, 500, 84220, 86130, 1*10**18, 5000*10**18, 0, 0], {"from": Alice} )
    chain.sleep(30)

    tokens = NFTContract.totalSupply( {"from": Alice} )
    assert tokens == 1
    print('Total token Supply:',tokens)

    ownedTokens = NFTContract.tokensOfOwner(Alice, {"from": Alice} )
    assert ownedTokens[0] == 0
    assert len(ownedTokens) == 1
    print('Tokens of Alice:',ownedTokens)

    pos = NFTContract.tokenIDtoPosition(0, {"from": Alice})
    print('Position:',pos)
    assert pos == (ABPool, 84220, 86130)

    #Second Alice position
    Atoken.approve(NFTContract, 0.11*10**18, {"from": Alice})
    Btoken.approve(NFTContract, 500*10**18, {"from": Alice})

    chain.sleep(30)
    pos = NFTContract.mint([Alice, Atoken, Btoken, 500, 82220, 87130, 0.1*10**18, 500*10**18, 0, 0], {"from": Alice} )
    chain.sleep(30)

    tokens = NFTContract.totalSupply( {"from": Alice} )
    assert tokens == 2
    print('Total token Supply:',tokens)

    ownedTokens = NFTContract.tokensOfOwner(Alice, {"from": Alice} )
    print('Tokens of Alice:',ownedTokens)
    assert ownedTokens == (0,1)
    assert len(ownedTokens) == 2


    pos = NFTContract.tokenIDtoPosition(0, {"from": Alice})
    assert pos == (ABPool, 84220, 86130)
    second_pos = NFTContract.tokenIDtoPosition(1, {"from": Alice})
    assert second_pos == (ABPool, 82220, 87130)

    #Burn first position
    NFTContract.burn(0,{"from": Alice})

    tokens = NFTContract.totalSupply( {"from": Alice} )
    assert tokens == 1
    print('Total token Supply:',tokens)

    ownedTokens = NFTContract.tokensOfOwner(Alice, {"from": Alice} )
    print('Tokens of Alice:',ownedTokens)
    assert ownedTokens[0] == 1
    assert len(ownedTokens) == 1


# def test_aboveRange(Atoken, Btoken, Xtoken, Ytoken, factoryContract, managerContract, ABPool, XYPool):
#     # fetch the accounts
#     account = accounts[0]

#     #Fund the users
#     Alice = accounts[1]
#     Atoken.mint(Alice, 10000*10**18,{"from": account})
#     Btoken.mint(Alice, 10000*10**18,{"from": account})

#     #Variables
#     fraq=2**96
#     initP_AB=5000

#     #Initialize pool AB
#     ABPool.initialize(initP_AB, {"from": account})
#     print("Slot0:",ABPool.slot0({"from": account}))
#     assert ABPool.slot0({"from": account})[0] != (0)


#     #Set pos
#     Atoken.approve(managerContract, 1*10**18, {"from": Alice})
#     Btoken.approve(managerContract, 5000*10**18, {"from": Alice})

#     managerContract.mint([Atoken, Btoken, 500, 86130, 89130, 1*10**18, 5000*10**18, 0, 0], {"from": Alice} )

#     pos = managerContract.getPosition([Atoken, Btoken, 500, Alice, 86130, 89130], {"from": Alice})
#     print('Position:',pos)
#     assert pos[0]!=0

# def test_bellowRange(Atoken, Btoken, Xtoken, Ytoken, factoryContract, managerContract, ABPool, XYPool):
    # # fetch the accounts
    # account = accounts[0]

    # #Fund the users
    # Alice = accounts[1]
    # Atoken.mint(Alice, 10000*10**18,{"from": account})
    # Btoken.mint(Alice, 10000*10**18,{"from": account})

    # Xander = accounts[2]
    # Xtoken.mint(Xander, 10000*10**18,{"from": account})
    # Ytoken.mint(Xander, 10000*10**18,{"from": account})

    # #Variables
    # fraq=2**96
    # initP_AB=5000

    # #Initialize pool AB
    # ABPool.initialize(initP_AB, {"from": account})
    # print("Slot0:",ABPool.slot0({"from": account}))
    # assert ABPool.slot0({"from": account})[0] != (0)


    # #Set pos
    # Atoken.approve(managerContract, 5000*10**18, {"from": Alice})
    # Btoken.approve(managerContract, 5000*10**18, {"from": Alice})

    # tx = managerContract.mint([Atoken, Btoken, 500, 81000, 82000, 1*10**18, 5000*10**18, 0, 0], {"from": Alice} )
    # print(tx.info())
    # pos = managerContract.getPosition([Atoken, Btoken, 500, Alice, 81000, 82000], {"from": Alice})
    # print('Position:',pos)
    # assert pos[0]!=0

    # print(ABPool.positions())
    # assert 1==2