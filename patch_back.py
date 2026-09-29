import sys

def patch_file(filepath, replacement_map):
    with open(filepath, 'r') as f:
        content = f.read()
    
    for old, new in replacement_map.items():
        if old in content:
            content = content.replace(old, new)
        else:
            print(f"Warning: {old[:50]}... not found in {filepath}")
            
    with open(filepath, 'w') as f:
        f.write(content)

# Patch ActiveCallPage
active_call_file = "lib/screens/active_call_page.dart"
old_active = """  Widget build(BuildContext context) {
    return Scaffold("""
new_active = """  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _triggerHangup();
        return false;
      },
      child: Scaffold("""

old_active_startcall = """        try {
          final generatedRoomId = await _callService.startCall(
            expertId: widget.receiverId,
            callerId: widget.callerId,
            onRemoteStream: (stream) {"""
new_active_startcall = """        try {
          final generatedRoomId = await _callService.startCall(
            expertId: widget.receiverId,
            callerId: widget.callerId,
            onRemoteStream: (stream) {"""
# Actually, I'll fix the mounted issue via regex or just replace.
# Let's find the exact block for mounted inside startCall
old_active_mounted = """          if (mounted) {
            setState(() {
              _roomId = generatedRoomId;
              if (_callService.localStream != null) {
                _localRenderer.srcObject = _callService.localStream;
              }
            });
          }
        } catch (e) {"""
new_active_mounted = """          if (mounted) {
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

patch_file(active_call_file, {
    old_active: new_active,
    old_active_mounted: new_active_mounted
})

# Patch IncomingCallScreen
incoming_file = "lib/screens/incoming_call_screen.dart"
old_incoming = """  Widget build(BuildContext context) {
    return Scaffold("""
new_incoming = """  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _declineCall();
        return false;
      },
      child: Scaffold("""

patch_file(incoming_file, {
    old_incoming: new_incoming
})

print("Patched!")
