const express = require('express');
const { Pool } = require('pg');

const app = express();
const pool = new Pool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  ssl: { rejectUnauthorized: false },
  port: 5432,
});

pool.query('CREATE TABLE IF NOT EXISTS visits (id SERIAL PRIMARY KEY, seen_at TIMESTAMP DEFAULT NOW())');

// the readiness probe hits this — it checks the DB, not just the process
app.get('/healthz', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.status(200).send('ok');
  } catch (err) {
    res.status(500).send('db unreachable');
  }
});

app.get('/', async (req, res) => {
  await pool.query('INSERT INTO visits DEFAULT VALUES');
  const r = await pool.query('SELECT COUNT(*) FROM visits');
  res.send(`Hello from EKS. Visits: ${r.rows[0].count}`);
});

app.listen(3000, () => console.log('listening on 3000'));