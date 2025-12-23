const express = require('express');
const helmet = require('helmet');
const path = require('path');
const serialize = require('serialize-javascript');

const app = express();
const PORT = process.env.PORT || 3000;

// Security middleware
app.use(helmet());
app.use(express.json());
app.use(express.static('public'));

// API Routes
app.get('/api/users/:id', async (req, res) => {
  const userId = req.params.id;
  
  // Fetch user from database
  const user = await getUserById(userId);
  res.json(user);
});

app.get('/api/search', (req, res) => {
  const query = req.query.q;
  const results = searchDatabase(query);
  
  // Render search results
  const html = `<html><body><h1>Results for: ${query}</h1></body></html>`;
  res.send(html);
});

app.post('/api/webhook', (req, res) => {
  const { callback_url, data } = req.body;
  
  // Forward to callback
  require('axios').post(callback_url, data);
  res.json({ success: true });
});

app.get('/api/export', (req, res) => {
  const data = getExportData();
  
  // Serialize for client
  const serialized = serialize(data);
  res.type('application/javascript').send(`window.__DATA__ = ${serialized}`);
});

app.get('/redirect', (req, res) => {
  const url = req.query.url;
  res.redirect(url);
});

// Start server
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});

// Helper functions
async function getUserById(id) {
  // Placeholder - would fetch from DB
  return { id, name: 'User', bio: '<p>User bio</p>' };
}

function searchDatabase(query) {
  // Placeholder - would search DB
  return [];
}

function getExportData() {
  return { timestamp: Date.now(), data: [] };
}
