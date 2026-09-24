import sys
from PIL import Image, ImageDraw

def crop_to_circle(input_path, output_path):
    img = Image.open(input_path).convert("RGBA")
    
    # Calculate the bounding box for the circle
    # The image has a white ring, let's just make it a perfect circle
    # taking the max possible circle from the square image.
    min_dim = min(img.size)
    
    # Create a mask
    mask = Image.new('L', img.size, 0)
    draw = ImageDraw.Draw(mask)
    
    # Calculate offset to center the circle
    x_offset = (img.width - min_dim) // 2
    y_offset = (img.height - min_dim) // 2
    
    draw.ellipse((x_offset, y_offset, x_offset + min_dim, y_offset + min_dim), fill=255)
    
    # Apply mask
    result = Image.new('RGBA', img.size, (0, 0, 0, 0))
    result.paste(img, (0, 0), mask=mask)
    
    # Crop to just the circle part to remove extra transparent space
    result = result.crop((x_offset, y_offset, x_offset + min_dim, y_offset + min_dim))
    
    # Resize to standard icon size (e.g., 1024x1024)
    result = result.resize((1024, 1024), Image.Resampling.LANCZOS)
    
    result.save(output_path, "PNG")
    print(f"Saved to {output_path}")

input_img = "/home/oem/.gemini/antigravity/brain/4782263a-46b8-4ad5-95e1-d4cd1134bdc3/.user_uploaded/media_1790267623315.jpg"
crop_to_circle(input_img, "assets/icon/app_icon.png")
