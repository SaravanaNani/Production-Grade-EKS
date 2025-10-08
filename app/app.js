const express = require('express');
const app = express();

app.get('/', (req, res) => {
  console.log(`[${new Date().toISOString()}] GET / request received`);
  res.send('🚀 Sample Node App for Promtail Logging Demo!');
});

setInterval(() => {
  console.log(`[${new Date().toISOString()}] App heartbeat log`);
}, 5000);

app.listen(3000, () => {
  console.log('Server running on port 3000');
});
