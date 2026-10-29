ALTER TABLE products ADD COLUMN IF NOT EXISTS sku TEXT;
UPDATE products SET sku = 'SKU-' || id WHERE sku IS NULL;
