#!/bin/bash

# Load Nginx image
docker load -i nginx.tar

# Create custom test page directory
mkdir -p /tmp/nginx-test

# Generate a stylish test page
cat > /tmp/nginx-test/index.html << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Welcome to Nginx Test Page</title>
    <style>
        body { 
            font-family: Arial, sans-serif; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            color: white;
        }
        .container {
            text-align: center;
            background: rgba(255,255,255,0.1);
            padding: 40px;
            border-radius: 15px;
            box-shadow: 0 8px 32px 0 rgba(31, 38, 135, 0.37);
        }
        h1 { font-size: 3rem; margin-bottom: 20px; }
        p { font-size: 1.2rem; }
    </style>
</head>
<body>
    <div class="container">
        <h1>✨ Nginx Test Page ✨</h1>
        <p>Container Successfully Deployed!</p>
        <p>$(date)</p>
    </div>
</body>
</html>
EOF

# Run Nginx container with custom test page
docker run -d \
    --name nginx-test \
    -p 80:80 \
    -v /tmp/nginx-test:/usr/share/nginx/html \
    nginx

echo "Nginx container started. Access at http://localhost"
