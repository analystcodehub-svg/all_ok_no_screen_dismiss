import re
import glob

# For all .dart files in lib/screens/
for filepath in glob.glob("lib/screens/*.dart"):
    with open(filepath, 'r') as f:
        content = f.read()

    # Look for AssetImage('path') or AssetImage(variable)
    # Be careful not to replace already ResizeImage wrapped AssetImages
    # Let's match AssetImage(.*?) but not if it's already inside ResizeImage
    # Or just replace backgroundImage: AssetImage(...) -> backgroundImage: ResizeImage(AssetImage(...), width: 300)
    
    new_content = re.sub(r'backgroundImage:\s*AssetImage\(([^)]+)\)', r'backgroundImage: ResizeImage(AssetImage(\1), width: 200)', content)
    
    if new_content != content:
        with open(filepath, 'w') as f:
            f.write(new_content)
