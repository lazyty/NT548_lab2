const express = require('express');
const { body, validationResult } = require('express-validator');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3003;

app.use(express.json());

// Mock product database
let products = [
  { id: 1, name: 'Laptop', price: 999.99, stock: 50, category: 'Electronics' },
  { id: 2, name: 'Mouse', price: 29.99, stock: 200, category: 'Electronics' },
  { id: 3, name: 'Keyboard', price: 79.99, stock: 150, category: 'Electronics' }
];

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'product-service' });
});

// Get all products
app.get('/', (req, res) => {
  const { category, minPrice, maxPrice } = req.query;
  let filtered = products;

  if (category) {
    filtered = filtered.filter(p => p.category === category);
  }
  if (minPrice) {
    filtered = filtered.filter(p => p.price >= parseFloat(minPrice));
  }
  if (maxPrice) {
    filtered = filtered.filter(p => p.price <= parseFloat(maxPrice));
  }

  res.json(filtered);
});

// Get product by ID
app.get('/:id', (req, res) => {
  const product = products.find(p => p.id === parseInt(req.params.id));
  if (!product) {
    return res.status(404).json({ message: 'Product not found' });
  }
  res.json(product);
});

// Create product
app.post('/', [
  body('name').notEmpty(),
  body('price').isFloat({ min: 0 }),
  body('stock').isInt({ min: 0 })
], (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ errors: errors.array() });
  }

  const newProduct = {
    id: products.length + 1,
    name: req.body.name,
    price: req.body.price,
    stock: req.body.stock,
    category: req.body.category || 'General'
  };
  products.push(newProduct);
  res.status(201).json(newProduct);
});

// Update product
app.put('/:id', (req, res) => {
  const productIndex = products.findIndex(p => p.id === parseInt(req.params.id));
  if (productIndex === -1) {
    return res.status(404).json({ message: 'Product not found' });
  }

  products[productIndex] = { ...products[productIndex], ...req.body, id: products[productIndex].id };
  res.json(products[productIndex]);
});

// Delete product
app.delete('/:id', (req, res) => {
  const productIndex = products.findIndex(p => p.id === parseInt(req.params.id));
  if (productIndex === -1) {
    return res.status(404).json({ message: 'Product not found' });
  }

  products.splice(productIndex, 1);
  res.status(204).send();
});

app.listen(PORT, () => {
  console.log(`Product Service running on port ${PORT}`);
});

module.exports = app;
