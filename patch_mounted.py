import sys

def patch_file(filepath, replacement_map):
    with open(filepath, 'r') as f:
        content = f.read()
    
    for old, new in replacement_map.items():
        if old in content:
            content = content.replace(old, new)
        else:
            print(f"Warning: Not found in {filepath}")
            
    with open(filepath, 'w') as f:
        f.write(content)

filepath = "lib/screens/active_call_page.dart"

old_mounted = """        if (mounted) {
          setState(() {
            _roomId = generatedRoomId;
            if (_callService.localStream != null) {
              _localRenderer.srcObject = _callService.localStream;
            }
          });
        }
      } catch (e) {"""

new_mounted = """        if (mounted) {
          setState(() {
            _roomId = generatedRoomId;
            if (_callService.localStream != null) {
              _localRenderer.srcObject = _callService.localStream;
            }
          });
        } else {
          _callService.endCall(generatedRoomId);
        }
      } catch (e) {"""

patch_file(filepath, {old_mounted: new_mounted})
print("Patched mounted!")
