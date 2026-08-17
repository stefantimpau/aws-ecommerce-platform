import { redirectToLogin, logout } from '../auth';

export default function Header({ user, cartCount, onCartClick }) {
  return (
    <header className="header">
      <div className="header-inner">
        <span className="brand">aws-ecommerce-platform</span>

        <div className="header-actions">
          <button className="link-button" onClick={onCartClick}>
            Cart {cartCount > 0 && <span className="badge">{cartCount}</span>}
          </button>

          {user ? (
            <>
              <span className="user-email">{user.email}</span>
              <button className="link-button" onClick={logout}>
                Sign out
              </button>
            </>
          ) : (
            <button className="link-button" onClick={redirectToLogin}>
              Sign in
            </button>
          )}
        </div>
      </div>
    </header>
  );
}
