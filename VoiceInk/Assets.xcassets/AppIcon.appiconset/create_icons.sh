#\!/bin/bash
for size in 16 32 64 128 256 512 1024; do
  # Use sips to create a solid color image
  sips -z ${size} ${size} --setProperty format png -c rgb 230 126 34 --padColor rgb 46 62 80 256-mac.png -o temp_${size}.png >/dev/null 2>&1
  
  if [ -f "temp_${size}.png" ]; then
    mv "temp_${size}.png" "${size}-mac.png"
    echo "Created orange ${size}x${size} icon"
  else
    echo "Using existing ${size}x${size} icon"
  fi
done
