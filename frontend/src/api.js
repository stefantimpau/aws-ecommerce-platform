import { getIdToken } from './auth';

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL;

async function request(path, { method = 'GET', body, auth = false } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (auth) {
    const token = getIdToken();
    if (!token) throw new Error('Not authenticated');
    headers.Authorization = token;
  }

  const res = await fetch(`${API_BASE_URL}${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });

  if (!res.ok) {
    let detail;
    try {
      detail = (await res.json()).error;
    } catch {
      detail = res.statusText;
    }
    throw new Error(`${method} ${path} failed (${res.status}): ${detail}`);
  }

  if (res.status === 204) return null;
  return res.json();
}

// Public — GET /products requires no auth (terraform/modules/apigateway).
export function getProducts() {
  return request('/products');
}

// Protected — the order-service publishes an SNS order-events message on
// success (services/order-service/src/index.js), which is what feeds the
// email notification and the shipping SQS queue.
export function createOrder(order) {
  return request('/orders', { method: 'POST', body: order, auth: true });
}

export function getOrders(userId) {
  return request(`/orders/${encodeURIComponent(userId)}`, { auth: true });
}

export function imageUrl(imageKey) {
  const cloudfrontDomain = import.meta.env.VITE_CLOUDFRONT_DOMAIN;
  return `https://${cloudfrontDomain}/${imageKey}`;
}
