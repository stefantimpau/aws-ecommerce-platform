import { useEffect, useState } from 'react';
import Header from './components/Header';
import ProductList from './components/ProductList';
import Cart from './components/Cart';
import { getProducts, createOrder } from './api';
import { handleAuthCallback, getCurrentUser, isAuthenticated } from './auth';

export default function App() {
  const [authReady, setAuthReady] = useState(false);
  const [user, setUser] = useState(null);

  const [products, setProducts] = useState([]);
  const [loadingProducts, setLoadingProducts] = useState(true);
  const [productsError, setProductsError] = useState(null);

  const [cartItems, setCartItems] = useState([]);
  const [cartOpen, setCartOpen] = useState(false);
  const [checkingOut, setCheckingOut] = useState(false);
  const [checkoutError, setCheckoutError] = useState(null);
  const [lastOrder, setLastOrder] = useState(null);

  // Resolve the Cognito Hosted UI redirect (?code=...) before rendering
  // anything that depends on auth state.
  useEffect(() => {
    handleAuthCallback().finally(() => {
      setUser(isAuthenticated() ? getCurrentUser() : null);
      setAuthReady(true);
    });
  }, []);

  useEffect(() => {
    getProducts()
      .then(setProducts)
      .catch((err) => setProductsError(err.message))
      .finally(() => setLoadingProducts(false));
  }, []);

  function addToCart(product) {
    setCartItems((prev) => {
      const existing = prev.find((i) => i.productId === product.productId);
      if (existing) {
        return prev.map((i) =>
          i.productId === product.productId ? { ...i, quantity: i.quantity + 1 } : i
        );
      }
      return [...prev, { ...product, quantity: 1 }];
    });
    setCartOpen(true);
  }

  function removeFromCart(productId) {
    setCartItems((prev) => prev.filter((i) => i.productId !== productId));
  }

  async function checkout() {
    if (!user) return;
    setCheckingOut(true);
    setCheckoutError(null);
    try {
      const order = await createOrder({
        userId: user.sub,
        items: cartItems.map((i) => ({
          productId: i.productId,
          name: i.name,
          // order-service reads item.unitPrice, both for the order total
          // and the order_items.unit_price NOT NULL column (services/
          // order-service/src/index.js) — sending `price` here silently
          // becomes undefined -> NULL on the backend and fails the
          // NOT NULL constraint, which is what a 500 "failed to create
          // order" with no other detail traces back to.
          unitPrice: i.price,
          quantity: i.quantity,
        })),
      });
      setLastOrder(order);
      setCartItems([]);
    } catch (err) {
      setCheckoutError(err.message);
    } finally {
      setCheckingOut(false);
    }
  }

  if (!authReady) return null; // avoid a flash of signed-out UI mid token exchange

  return (
    <div className="app">
      <Header
        user={user}
        cartCount={cartItems.reduce((n, i) => n + i.quantity, 0)}
        onCartClick={() => setCartOpen((v) => !v)}
      />

      <main className="main">
        <div className="catalog-column">
          <h1>Catalog</h1>
          <ProductList
            products={products}
            loading={loadingProducts}
            error={productsError}
            onAddToCart={addToCart}
          />
        </div>

        {cartOpen && (
          <div className="cart-column">
            <Cart
              items={cartItems}
              user={user}
              onRemove={removeFromCart}
              onCheckout={checkout}
              checkingOut={checkingOut}
              checkoutError={checkoutError}
              lastOrder={lastOrder}
            />
          </div>
        )}
      </main>
    </div>
  );
}
