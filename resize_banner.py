from PIL import Image
img = Image.open('/home/oem/.gemini/antigravity/brain/4d944544-b6d0-4f68-a847-01d3833b76eb/sajnire_feature_graphic_1784821219510.png')
# Assuming it's 1024x1024, crop the center 1024x500
width, height = img.size
left = 0
top = (height - 500) / 2
right = width
bottom = (height + 500) / 2
img = img.crop((left, top, right, bottom))
img = img.resize((1024, 500), Image.LANCZOS)
img.save('sajnire_feature_graphic_1024x500.png')
