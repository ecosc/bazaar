import { deployContract } from 'ethereum-waffle'

import { expandTo18Decimals } from './utils'

import ERC20 from '../../build/contracts/ERC20.json';
import Profile from '../../build/contracts/Profile.json';
import Bazaar from '../../build/contracts/Bazaar.json';

const overrides = {
    gasLimit: 9999999
}

export const TOKEN_INITIAL_LIQUIDITY = expandTo18Decimals(1000);

export async function erc20Fixture([wallet], provider) {
    const token = await deployContract(wallet, ERC20, [TOKEN_INITIAL_LIQUIDITY], overrides)

    return { token };
}

export async function profileFixture([wallet], provider) {
    const { token: ecoToken } = await erc20Fixture([wallet], provider);
   
    const profile = await deployContract(wallet, Profile, [ecoToken.address], overrides)

    return { profile, ecoToken };
}

export async function bazaarFixture([wallet], provider) {
    const { profile, ecoToken } = await profileFixture([wallet], provider);

    const bazaar = await deployContract(wallet, Bazaar, [profile.address], overrides)

    return { bazaar, profile, ecoToken };
}

export async function fixtures([wallet], provider) {
    const { bazaar, profile, ecoToken } = await bazaarFixture([wallet], provider);
    const { token } = await erc20Fixture([wallet], provider);

    return { bazaar, profile, token, ecoToken };
}
