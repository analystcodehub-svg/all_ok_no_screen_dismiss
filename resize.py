from PIL import Image
img = Image.open('/home/oem/.gemini/antigravity/brain/4d944544-b6d0-4f68-a847-01d3833b76eb/sajnire_app_icon_1784821144308.png')
img = img.resize((512, 512), Image.LANCZOS)
img.save('sajnire_app_icon_512.png')
