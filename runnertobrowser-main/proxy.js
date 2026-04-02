const http = require('http');
const httpProxy = require('http-proxy');

console.log("starting proxy")

const proxy =httpProxy.createProxyServer({
    target: 'http://127.0.0.1:9222', // Chrome
    ws: true,
    changeOrigin: true
});

proxy.on('error', (err,req,res) => {
    console.error("proxy error:", err.message);
    if (res && !res.headersSent) {
        res.writeHead(500, { 'Content-Type': 'text/plain' });
    }
    res.end('Proxy error');
});

const server = http.createServer((req, res) => {
    console.log("HTTP request:", req.url);
    proxy.web(req, res);
});

server.on('upgrade', (req, socket, head) => {
    console.log("ws upgrade");
    proxy.ws(req, socket, head);
});

const PORT = 3000;

server.listen(PORT, () => {
    console.log(`Proxy run on ${PORT}`);
});

//