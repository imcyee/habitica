import nconf from 'nconf';

import { getStripeApi } from './api';
import { // eslint-disable-line import/no-cycle
  model as Group,
  basicFields as basicGroupFields,
} from '../../../models/group';
import { getOneTimePaymentInfo } from './oneTimePayments'; // eslint-disable-line import/no-cycle
import { checkSubData } from './subscriptions'; // eslint-disable-line import/no-cycle

async function buySubscription (sub, coupon, email, user, token, groupId, stripeApi) {//TODO
  const customerObject = {
    email,
    metadata: { uuid: user._id },
    card: token,
    plan: sub.key,
  };

  if (groupId) {
    customerObject.quantity = sub.quantity;
    const groupFields = basicGroupFields.concat(' purchased');
    const group = await Group.getGroup({
      user, groupId, populateLeader: false, groupFields,
    });
    const membersCount = await group.getMemberCount();
    customerObject.quantity = membersCount + sub.quantity - 1;
  }

  const response = await stripeApi.customers.create(customerObject);

  let subscriptionId;
  if (groupId) subscriptionId = response.subscriptions.data[0].id;

  return { subResponse: response, subId: subscriptionId };
}

const BASE_URL = nconf.get('BASE_URL');

export async function createCheckoutSession (options, stripeInc) {
  const {
    user,
    gift,
    gemsBlock: gemsBlockKey,
    sub,
    groupId,
    headers,
    coupon,
  } = options;

  // @TODO: We need to mock this, but curently we don't have correct
  // Dependency Injection. And the Stripe Api doesn't seem to be a singleton?
  let stripeApi = getStripeApi();
  if (stripeInc) stripeApi = stripeInc;

  let type = 'gems';
  if (gift) {
    type = gift.type === 'gems' ? 'gift-gems' : 'gift-sub';
  } else if (sub) {
    type = 'subscription';
  }

  const metadata = {
    type,
    userId: user._id,
    gift: gift ? JSON.stringify(gift) : undefined,
    sub: sub ? JSON.stringify(sub) : undefined,
  };

  let lineItems;

  if (type === 'subscription') {
    await checkSubData(sub, coupon);

    lineItems = [{
      price: sub.key,
      quantity: 1,
      //TODO description, images directly from plan setup
    }];
  } else {
    const {
      amount,
      gemsBlock,
    } = await getOneTimePaymentInfo(gemsBlockKey, gift, user, stripeApi);

    metadata.gemsBlock = gemsBlock ? gemsBlock.key : undefined;

    lineItems = [{
      price_data: {
        product_data: {
          name: JSON.stringify(metadata, null, 4), //TODO copy for name (gift, gems, subs)
          //TODO images, description, ...? see api docs
        },
        unit_amount: amount,
        currency: 'usd',
      },
      quantity: 1,
    }];
  }

  const session = await stripeApi.checkout.sessions.create({
    payment_method_types: ['card'],
    metadata,
    line_items: lineItems,
    mode: type === 'subscription' ? 'subscription' : 'payment',
    success_url: `http://localhost:8080/redirect/stripe-success-checkout`, //TODO use BASE_URL
    cancel_url: `http://localhost:8080/redirect/stripe-error-checkout`, //TODO use BASE_URL
  });

  return session;
}
