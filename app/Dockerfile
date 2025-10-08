# Use lightweight Node.js image
FROM node:18-alpine

# Working directory inside container
WORKDIR /usr/src/app

# Copy app files
COPY . .

# Install minimal dependencies
RUN npm install express

# Expose port
EXPOSE 3000

# Start app
CMD ["node", "app.js"]
