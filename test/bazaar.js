import chai, { expect } from 'chai'
import { solidity, MockProvider, createFixtureLoader } from 'ethereum-waffle'
import { BigNumber, constants, Contract } from 'ethers'
import { fixtures, TOKEN_INITIAL_LIQUIDITY } from './shared/fixtures';
import { expandTo18Decimals } from './shared/utils';

chai.use(solidity);

const INITIAL_GUARANTEE_PERCENT = BigNumber.from(10000);
const INITIAL_CLOSE_FEE = BigNumber.from(100);
const INITIAL_CANCELLATION_FEE = BigNumber.from(100);
const INITIAL_SELL_FEE = BigNumber.from(250);
const INITIAL_BUY_FEE = BigNumber.from(250);
const INITIAL_MAX_DELIVERY_TIME = BigNumber.from(8 * 60 * 60);
const ORDER_STATES = {
    Placed: 0,
    Sold: 1,
    Finished: 2,
    Closed: 3,
    Withdrew: 4,
    CancelledBySeller: 5,
    CancelledByBuyer: 6
};

const { AddressZero } = constants;


describe('Bazaar', () => {
    const provider = new MockProvider(
        {
            ganacheOptions: {
                hardfork: 'istanbul',
                mnemonic: 'horn horn horn horn horn horn horn horn horn horn horn horn',
                gasLimit: 9999999
            }
        })
    const [wallet, other, mother] = provider.getWallets();
    const loadFixture = createFixtureLoader([wallet], provider);

    let bazaar;
    let token;
    let profile;
    beforeEach(async () => {
        const fixture = await loadFixture(fixtures);

        bazaar = fixture.bazaar;
        profile = fixture.profile;
        token = fixture.token;
    })

    it("initial values be valid", async () => {
        expect(await bazaar.owner()).to.eq(wallet.address);
        expect(await bazaar.guaranteePercent()).to.eq(INITIAL_GUARANTEE_PERCENT);
        expect(await bazaar.cancellationFee()).to.eq(INITIAL_CANCELLATION_FEE);
        expect(await bazaar.closeFee()).to.eq(INITIAL_CLOSE_FEE);
        expect(await bazaar.sellFee()).to.eq(INITIAL_SELL_FEE);
        expect(await bazaar.buyFee()).to.eq(INITIAL_BUY_FEE);
        expect(await bazaar.feeTo()).to.eq(wallet.address);
    });

    it("only owner actions", async () => {
        await expect(bazaar.connect(other).setSellFee(BigNumber.from(1000))).to.be.revertedWith('Ownable: caller is not the owner');
        await expect(bazaar.connect(other).setBuyFee(BigNumber.from(1000))).to.be.revertedWith('Ownable: caller is not the owner');
        await expect(bazaar.connect(other).setCloseFee(BigNumber.from(1000))).to.be.revertedWith('Ownable: caller is not the owner');
        await expect(bazaar.connect(other).setCancellationFee(BigNumber.from(1000))).to.be.revertedWith('Ownable: caller is not the owner');
        await expect(bazaar.connect(other).setGuaranteePercent(BigNumber.from(1000))).to.be.revertedWith('Ownable: caller is not the owner');
    });

    it("parameters set and get", async () => {
        await bazaar.setGuaranteePercent(BigNumber.from(13000));
        expect(await bazaar.guaranteePercent()).to.eq(13000);

        await bazaar.setCloseFee(BigNumber.from(11000));
        expect(await bazaar.closeFee()).to.eq(11000);

        await bazaar.setCancellationFee(BigNumber.from(11000));
        expect(await bazaar.cancellationFee()).to.eq(11000);

        await bazaar.setSellFee(BigNumber.from(9000));
        expect(await bazaar.sellFee()).to.eq(9000);

        await bazaar.setBuyFee(BigNumber.from(7000));
        expect(await bazaar.buyFee()).to.eq(7000);
    });

    async function placeOrder(sourceAsset, sourceAmount, targetAsset, targetAmount, deadline) {
        const targetApproveAmount = targetAmount.mul(INITIAL_GUARANTEE_PERCENT).div(100000);

        await profile.createAccount("Mamad", "http://mamad.org");

        // approve token so bazaar can transfer
        await token.approve(bazaar.address, targetApproveAmount);

        await expect(bazaar.placeOrder(sourceAsset, sourceAmount, targetAsset, targetAmount, deadline, { gasLimit: 9999999 })).
            to.emit(bazaar, 'OrderPlaced');
    }

    async function buyOrder(buyer, buyPrice, orderID) {
        // transfer required amount of token to buyer account
        await token.transfer(buyer.address, buyPrice);
        // approve token so bazaar can transfer
        await token.connect(buyer).approve(bazaar.address, buyPrice);

        // only profile owners can buy
        await profile.connect(buyer).createAccount("Samad", "http://samad.org");

        await expect(bazaar.connect(buyer).buy(orderID)).to.emit(bazaar, 'OrderSold').withArgs(BigNumber.from(0), buyer.address);
    }

    it("place order", async () => {
        const orderPrice = expandTo18Decimals(1);
        const targetApproveAmount = orderPrice.mul(INITIAL_GUARANTEE_PERCENT).div(100000);

        await expect(bazaar.placeOrder(0, BigNumber.from(100), token.address, orderPrice, 100, { gasLimit: 9999999 })).
            to.be.revertedWith('BAZAAR: NOT_REGISTERED');

        await placeOrder(0, 100, token.address, orderPrice, 100);

        const createdOrder = await bazaar.orders(0);

        expect([
            createdOrder.seller,
            createdOrder.buyer,
            createdOrder.state,
            createdOrder.sourceAsset,
            createdOrder.targetAsset,
            createdOrder.sourceAmount,
            createdOrder.targetAmount,
        ]).to.eql([
            wallet.address,
            AddressZero,
            ORDER_STATES.Placed,
            BigNumber.from(0),
            token.address,
            BigNumber.from(100),
            orderPrice,
        ]);

        // check balance of contract for target token
        expect(await token.balanceOf(bazaar.address)).to.eq(targetApproveAmount);

        // const tx = await bazaar.placeOrder(0, BigNumber.from(100), token.address, orderPrice, 100, {gasLimit: 9999999});
        // const receipt = await tx.wait();
        // expect(receipt.gasUsed).to.eq(208084);
    });

    it("close order", async () => {
        const orderPrice = expandTo18Decimals(1);
        const closeFee = orderPrice.mul(INITIAL_CLOSE_FEE).div(100000);

        await bazaar.setFeeTo(other.address);

        await placeOrder(0, 100, token.address, orderPrice, 100);

        await expect(bazaar.close(0)).to.emit(bazaar, 'OrderClosed').withArgs(BigNumber.from(0), wallet.address);

        const closedOrder = await bazaar.orders(0);

        expect(closedOrder.state).to.eq(ORDER_STATES.Closed);

        expect(await token.balanceOf(other.address)).to.eq(closeFee);
        expect(await token.balanceOf(wallet.address)).to.eq(TOKEN_INITIAL_LIQUIDITY.sub(closeFee));
        expect(await token.balanceOf(bazaar.address)).to.eq(BigNumber.from(0));
    });

    it("buy an order", async () => {
        const orderPrice = expandTo18Decimals(1);
        const buyFee = orderPrice.mul(INITIAL_BUY_FEE).div(100000);
        const guaranteeAmount = orderPrice.mul(INITIAL_GUARANTEE_PERCENT).div(100000);
        const buyPrice = orderPrice.add(buyFee);

        await placeOrder(0, 100, token.address, orderPrice, 100);

        // transfer required amount of token to buyer account
        await token.transfer(other.address, buyPrice);
        await token.connect(other).approve(bazaar.address, buyPrice);

        await profile.connect(other).createAccount("Sammad", "http://sammad.org");

        await expect(bazaar.connect(other).buy(0)).to.emit(bazaar, 'OrderSold').withArgs(BigNumber.from(0), other.address);

        const order = await bazaar.orders(0);

        expect(order.state).to.eq(ORDER_STATES.Sold);
        expect(order.buyer).to.eq(other.address);

        expect(await token.balanceOf(wallet.address)).to.eq(TOKEN_INITIAL_LIQUIDITY.sub(buyPrice).sub(guaranteeAmount));
        expect(await token.balanceOf(other.address)).to.eq(BigNumber.from(0));
        expect(await token.balanceOf(bazaar.address)).to.eq(buyPrice.add(guaranteeAmount));
    });

    it("approve delivery", async () => {
        const orderPrice = expandTo18Decimals(1);
        const buyFee = orderPrice.mul(INITIAL_BUY_FEE).div(100000);
        const sellFee = orderPrice.mul(INITIAL_SELL_FEE).div(100000);
        const totalBuyPrice = orderPrice.add(buyFee);

        await profile.connect(other).createAccount("Sammad", "http://sammad.org");

        // transfer required amount of token to buyer account
        await token.transfer(other.address, totalBuyPrice);
        await token.connect(other).approve(bazaar.address, totalBuyPrice);

        await placeOrder(0, 100, token.address, orderPrice, 50);

        await expect(bazaar.connect(other).buy(0)).to.emit(bazaar, 'OrderSold').withArgs(BigNumber.from(0), other.address);
        await expect(bazaar.approveDelivery(0)).to.be.revertedWith('BAZAAR: ONLY_BUYER');
        // await expect(bazaar.connect(other).approveDelivery(0)).to.be.revertedWith('BAZAAR: ORDER_DEADLINE_NOT_EXCEEDED');

        // increase block timestamp
        await provider.send("evm_increaseTime", [3600]);
        await provider.send("evm_mine");

        await bazaar.setFeeTo(mother.address);
        await expect(bazaar.connect(other).approveDelivery(0)).to.emit(bazaar, 'DeliveryApproved', BigNumber.from(0));

        const order = await bazaar.orders(0);

        expect(order.state).to.eq(ORDER_STATES.Finished);

        expect(await token.balanceOf(wallet.address)).to.eq(TOKEN_INITIAL_LIQUIDITY.sub(sellFee).sub(buyFee));
        expect(await token.balanceOf(mother.address)).to.eq(buyFee.add(sellFee));
        expect(await token.balanceOf(bazaar.address)).to.eq(BigNumber.from(0));
    });

    it("cancel for seller", async () => {
        const orderPrice = expandTo18Decimals(1);
        const cancellationFee = orderPrice.mul(INITIAL_CANCELLATION_FEE).div(100000);
        const buyFee = orderPrice.mul(INITIAL_BUY_FEE).div(100000);
        const buyPrice = orderPrice.add(buyFee);

        await bazaar.setFeeTo(other.address);

        await placeOrder(0, 100, token.address, orderPrice, 100);
        await buyOrder(mother, buyPrice, 0);

        await expect(bazaar.cancelForSeller(0)).to.be.revertedWith('BAZAAR: ORDER_MAX_DELIVERY_NOT_EXCEEDED');

        // increase block timestamp
        await provider.send("evm_increaseTime", [INITIAL_MAX_DELIVERY_TIME.add(101).toNumber()]);
        await provider.send("evm_mine");

        await expect(bazaar.cancelForSeller(0)).to.emit(bazaar, 'OrderCancelledBuySeller').withArgs(BigNumber.from(0), wallet.address);

        const cancelledOrder = await bazaar.orders(0);

        expect(cancelledOrder.state).to.eq(ORDER_STATES.CancelledBySeller);

        // check feeTo balance
        expect(await token.balanceOf(other.address)).to.eq(cancellationFee.mul(2));
        // check seller balance
        expect(await token.balanceOf(wallet.address)).to.eq(TOKEN_INITIAL_LIQUIDITY.sub(buyPrice).sub(cancellationFee));
        // check buyer balance
        expect(await token.balanceOf(mother.address)).to.eq(buyPrice.sub(cancellationFee));
        expect(await token.balanceOf(bazaar.address)).to.eq(BigNumber.from(0));
    });

    it("cancel for buyer", async () => {
        const orderPrice = expandTo18Decimals(1);
        const cancellationFee = orderPrice.mul(INITIAL_CANCELLATION_FEE).div(100000);
        const buyFee = orderPrice.mul(INITIAL_BUY_FEE).div(100000);
        const buyPrice = orderPrice.add(buyFee);

        await bazaar.setFeeTo(other.address);

        await placeOrder(0, 100, token.address, orderPrice, 100);
        await buyOrder(mother, buyPrice, 0);

        await expect(bazaar.cancelForBuyer(0)).to.be.revertedWith('BAZAAR: ONLY_BUYER');
        await expect(bazaar.connect(mother).cancelForBuyer(0)).to.be.revertedWith('BAZAAR: ORDER_MAX_DELIVERY_NOT_EXCEEDED');

        // increase block timestamp
        await provider.send("evm_increaseTime", [INITIAL_MAX_DELIVERY_TIME.add(101).toNumber()]);
        await provider.send("evm_mine");

        await expect(bazaar.connect(mother).cancelForBuyer(0)).to.emit(bazaar, 'OrderCancelledBuyBuyer').withArgs(BigNumber.from(0), mother.address);

        const cancelledOrder = await bazaar.orders(0);

        expect(cancelledOrder.state).to.eq(ORDER_STATES.CancelledByBuyer);

        // check feeTo balance
        expect(await token.balanceOf(other.address)).to.eq(cancellationFee.mul(2));
        // check seller balance
        expect(await token.balanceOf(wallet.address)).to.eq(TOKEN_INITIAL_LIQUIDITY.sub(buyPrice).sub(cancellationFee));
        // check buyer balance
        expect(await token.balanceOf(mother.address)).to.eq(buyPrice.sub(cancellationFee));
        expect(await token.balanceOf(bazaar.address)).to.eq(BigNumber.from(0));
    });
});

