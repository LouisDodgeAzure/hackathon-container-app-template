# Stage 1: Build dependencies
FROM node:18-alpine AS builder
WORKDIR /usr/src/app

# Copy package files and install dependencies
# Copy package-lock.json if it exists for deterministic installs
COPY package*.json ./
RUN npm ci --only=production --ignore-scripts

# Stage 2: Production image
FROM node:18-alpine AS final
WORKDIR /usr/src/app

# Create a non-root user and group
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Copy built dependencies from the builder stage
COPY --from=builder /usr/src/app/node_modules ./node_modules
# Copy application code
COPY src/ ./src
COPY package.json ./

# Set ownership to the non-root user
# Ensure node_modules is also owned by appuser if needed, though often read-only access is sufficient
RUN chown -R appuser:appgroup /usr/src/app

# Switch to the non-root user
USER appuser

# Expose the port the app runs on (should match target_port in Terraform and PORT env var)
EXPOSE 8080

# Healthcheck (optional but recommended)
# Adjust the path and interval as needed
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost:8080/healthz || exit 1

# Define the command to run the application
# Use the PORT environment variable provided by Container Apps / Docker Compose
CMD [ "node", "src/index.js" ]