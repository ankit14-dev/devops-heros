const express = require("express");
const os = require("os");

const app = express();
const PORT = process.env.PORT || 3000;

app.get("/", (req, res) => {
  res.send(`<h1>Hello World from Node.js (Express) in Docker!</h1>
<p>Container hostname: ${os.hostname()}</p>`);
});

app.listen(PORT, () => console.log(`Node.js app listening on port ${PORT}`));
