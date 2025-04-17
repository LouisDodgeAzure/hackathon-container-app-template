# Stage 1: Build/Install dependencies
# Using python:3.10-slim as a base. Adjust version if needed.
FROM python:3.10-slim AS builder
WORKDIR /usr/src/app

# Install build tools if needed for some Python packages (e.g., gcc)
# RUN apt-get update && apt-get install -y --no-install-recommends gcc && rm -rf /var/lib/apt/lists/*

# Create a virtual environment (optional but good practice)
# RUN python -m venv /opt/venv
# ENV PATH="/opt/venv/bin:$PATH"

# Upgrade pip
RUN pip install --upgrade pip

# Copy requirements first for layer caching
COPY requirements.txt ./
# Install dependencies
# Use --no-cache-dir to reduce image size
RUN pip install --no-cache-dir -r requirements.txt

# Stage 2: Production image
FROM python:3.10-slim AS final
WORKDIR /usr/src/app

# Create a non-root user and group
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Copy installed dependencies from builder stage (if using venv)
# COPY --from=builder /opt/venv /opt/venv
# If not using venv, copy installed packages directly (less common)
COPY --from=builder /usr/local/lib/python3.10/site-packages /usr/local/lib/python3.10/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Copy application code
COPY src/ ./src

# Set ownership
RUN chown -R appuser:appgroup /usr/src/app

# Switch to non-root user
USER appuser

# Set environment variable for Flask
ENV FLASK_APP=src/main.py
# ENV FLASK_RUN_HOST=0.0.0.0 # Set in main.py now
# ENV FLASK_ENV=production # Set via Container Apps/Compose env vars

# Expose the port the app runs on (should match target_port in Terraform and PORT env var)
EXPOSE 5000

# Healthcheck (optional but recommended)
# Adjust the path and interval as needed
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl --fail http://localhost:5000/healthz || exit 1

# Define the command to run the application
# Use the PORT environment variable provided by Container Apps / Docker Compose
# Using Flask's built-in server here. For production, consider Gunicorn:
# CMD ["gunicorn", "--bind", "0.0.0.0:5000", "src.main:app"]
CMD [ "python", "-m", "flask", "run" ]