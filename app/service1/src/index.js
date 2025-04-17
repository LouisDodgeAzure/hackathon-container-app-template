// Simple Node.js Express App - Service 1
const express = require('express');
const app = express();
const port = process.env.PORT || 8080; // Use PORT env var from Container Apps/Compose

const serviceName = process.env.SERVICE_NAME || 'Service 1';
const environment = process.env.ENVIRONMENT || 'local';

app.get('/', (req, res) => {
  console.log(`[${new Date().toISOString()}] Request received on /`);
  res.send(`Hello from ${serviceName} in ${environment} environment! Host: ${req.hostname}`);
});

app.get('/healthz', (req, res) => {
  // Basic health check endpoint
  res.status(200).send('OK');
});

app.listen(port, '0.0.0.0', () => {
  console.log(`${serviceName} listening on port ${port}`);
  console.log(`Environment: ${environment}`);
});

// Graceful shutdown handling (optional but good practice)
process.on('SIGTERM', () => {
  console.log('SIGTERM signal received: closing HTTP server');
  // Perform cleanup if needed
  process.exit(0);
});

process.on('SIGINT', () => {
  console.log('SIGINT signal received: closing HTTP server');
  process.exit(0);
});