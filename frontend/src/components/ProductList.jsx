import { imageUrl } from '../api';

export default function ProductList({ products, loading, error, onAddToCart }) {
  if (loading) return <p className="status-text">Loading catalog...</p>;
  if (error) return <p className="status-text error">Couldn't load products: {error}</p>;
  if (products.length === 0) return <p className="status-text">No products yet — run scripts/seed/seed.js.</p>;

  return (
    <div className="product-grid">
      {products.map((p) => (
        <div className="product-card" key={p.productId}>
          <img src={imageUrl(p.imageKey)} alt={p.name} loading="lazy" />
          <div className="product-body">
            <p className="product-category">{p.category}</p>
            <p className="product-name">{p.name}</p>
            <p className="product-description">{p.description}</p>
            <div className="product-footer">
              <span className="product-price">£{Number(p.price).toFixed(2)}</span>
              <button onClick={() => onAddToCart(p)}>Add to cart</button>
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}
