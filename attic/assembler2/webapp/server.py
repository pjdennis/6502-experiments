from http.server import HTTPServer, BaseHTTPRequestHandler

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.end_headers()
        self.wfile.write(b"""<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Hello World</title>
  <style>
    body { font-family: sans-serif; display: flex; justify-content: center;
           align-items: center; height: 100vh; margin: 0; background: #1a1a2e; color: #e94560; }
    h1 { font-size: 3rem; }
  </style>
</head>
<body><h1>Hello, World!</h1></body>
</html>""")

HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
