# Simple Python Flask App - Service 2
import os
from flask import Flask, request, jsonify
import signal
import sys

app = Flask(__name__)

# Get config from environment variables
port = int(os.environ.get('PORT', 5000)) # Use PORT env var from Container Apps/Compose
service_name = os.environ.get('SERVICE_NAME', 'Service 2')
environment = os.environ.get('ENVIRONMENT', 'local')

@app.route('/')
def home():
    app.logger.info(f"Request received on / from {request.remote_addr}")
    return jsonify({
        "message": f"Hello from {service_name} in {environment} environment!",
        "host": request.host
    })

@app.route('/healthz')
def healthz():
    # Basic health check endpoint
    return "OK", 200

def shutdown_handler(signal_received, frame):
    app.logger.info(f"Signal {signal_received} received. Shutting down gracefully...")
    # Add any cleanup logic here
    sys.exit(0)

if __name__ == '__main__':
    # Register signal handlers for graceful shutdown
    signal.signal(signal.SIGINT, shutdown_handler)
    signal.signal(signal.SIGTERM, shutdown_handler)

    # Run the Flask app
    # Use 0.0.0.0 to be accessible within the container network
    app.run(host='0.0.0.0', port=port, debug=(environment == 'local')) # Enable debug only locally
    app.logger.info(f"{service_name} listening on port {port}")
    app.logger.info(f"Environment: {environment}")