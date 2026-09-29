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

filepath = "lib/services/call_service.dart"

old_1 = """      // 5. Create call document in RTDB
      final DatabaseReference roomRef = _database.ref('calls').push();
      final String roomId = roomRef.key!;

      // 6. Handle local ICE candidates and upload them"""
new_1 = """      // 5. Create call document in RTDB
      final DatabaseReference roomRef = _database.ref('calls').push();
      final String roomId = roomRef.key!;
      
      // Ensure the room is deleted if the caller disconnects abruptly
      await roomRef.onDisconnect().remove();

      // 6. Handle local ICE candidates and upload them"""

old_2 = """        // Update room status to ended and remove node
        try {
          await roomRef.update({'status': 'ended'});
          await roomRef.remove();
        } catch (e) {"""
new_2 = """        // Update room status to ended and remove node
        try {
          await roomRef.update({'status': 'ended'});
          await roomRef.onDisconnect().cancel();
          await roomRef.remove();
        } catch (e) {"""

old_3 = """      } else {
        try {
          await roomRef.update({'status': 'ended'});
          await roomRef.remove();
        } catch (e) {"""
new_3 = """      } else {
        try {
          await roomRef.update({'status': 'ended'});
          await roomRef.onDisconnect().cancel();
          await roomRef.remove();
        } catch (e) {"""

patch_file(filepath, {
    old_1: new_1,
    old_2: new_2,
    old_3: new_3,
})

print("Patched call service!")
