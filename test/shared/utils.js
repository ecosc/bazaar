import { BigNumber } from 'ethers';

export function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

export function expandTo18Decimals(n) {
    return BigNumber.from(n).mul(BigNumber.from(10).pow(18))
}