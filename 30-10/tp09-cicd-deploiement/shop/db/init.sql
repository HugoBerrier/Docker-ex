CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    price NUMERIC(10, 2) NOT NULL,
    stock INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    product_id INTEGER NOT NULL REFERENCES products (id),
    quantity INTEGER NOT NULL,
    status TEXT NOT NULL
);

INSERT INTO products (id, name, price, stock) VALUES
    (1, 'Clavier mécanique', 89.90, 12),
    (2, 'Écran 27"', 249.00, 4),
    (3, 'Souris sans fil', 29.50, 40);

SELECT setval('products_id_seq', (SELECT MAX(id) FROM products));
