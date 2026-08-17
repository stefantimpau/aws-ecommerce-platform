import { redirectToLogin } from '../auth';

export default function Cart({ items, user, onRemove, onCheckout, checkingOut, checkoutError, lastOrder }) {
  const total = items.reduce((sum, i) => sum + i.price * i.quantity, 0);

  if (lastOrder) {
    return (
      <div className="cart-panel">
        <h2>Order placed</h2>
        <p className="status-text">
          Order <code>{lastOrder.orderId}</code> confirmed. A notification was published to the order-events
          SNS topic — check the inbox subscribed to it.
        </p>
      </div>
    );
  }

  return (
    <div className="cart-panel">
      <h2>Cart</h2>
      {items.length === 0 ? (
        <p className="status-text">Your cart is empty.</p>
      ) : (
        <>
          <ul className="cart-list">
            {items.map((item) => (
              <li key={item.productId}>
                <span>
                  {item.name} × {item.quantity}
                </span>
                <span>£{(item.price * item.quantity).toFixed(2)}</span>
                <button className="link-button" onClick={() => onRemove(item.productId)}>
                  Remove
                </button>
              </li>
            ))}
          </ul>
          <p className="cart-total">Total: £{total.toFixed(2)}</p>

          {checkoutError && <p className="status-text error">{checkoutError}</p>}

          {user ? (
            <button disabled={checkingOut} onClick={onCheckout}>
              {checkingOut ? 'Placing order...' : 'Checkout'}
            </button>
          ) : (
            <button onClick={redirectToLogin}>Sign in to checkout</button>
          )}
        </>
      )}
    </div>
  );
}
