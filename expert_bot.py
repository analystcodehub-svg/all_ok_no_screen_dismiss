import argparse
import asyncio
import sqlite3
import hashlib
import time
import datetime
import threading
from typing import Optional

import firebase_admin
from firebase_admin import credentials, firestore, db

from aioconsole import ainput
from aiortc import RTCPeerConnection, RTCSessionDescription, AudioStreamTrack

# Optional: av is required by aiortc for audio/video frames
try:
    from av import AudioFrame
except ImportError:
    print("Please install 'av' package: pip install av")
    exit(1)

# Global variables
active_caller_id = None
pending_call_data = None

# ==========================================
# 1. LOCAL SQLITE STORAGE
# ==========================================
def init_db():
    conn = sqlite3.connect('expert_chats.db', check_same_thread=False)
    cursor = conn.cursor()
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS messages (
            id TEXT PRIMARY KEY,
            sender_id TEXT,
            receiver_id TEXT,
            message_text TEXT,
            timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    conn.commit()
    return conn

def save_message_locally(conn, msg_id, sender_id, receiver_id, text, timestamp=None):
    if not timestamp:
        timestamp = datetime.datetime.now().isoformat()
    cursor = conn.cursor()
    # Insert or ignore to prevent duplicates if any
    cursor.execute('''
        INSERT OR IGNORE INTO messages (id, sender_id, receiver_id, message_text, timestamp)
        VALUES (?, ?, ?, ?, ?)
    ''', (msg_id, sender_id, receiver_id, text, timestamp))
    conn.commit()

# ==========================================
# 2. WEBRTC MEDIA TRACK (SILENCE/PLACEHOLDER)
# ==========================================
class SilenceAudioTrack(AudioStreamTrack):
    """
    A placeholder audio track that sends silent frames.
    Useful for headless WebRTC testing without a real microphone.
    """
    kind = "audio"
    def __init__(self):
        super().__init__()

    async def recv(self):
        pts, time_base = await self.next_timestamp()
        # 960 samples for 20ms of audio at 48kHz
        frame = AudioFrame(format='s16', layout='mono', samples=960)
        # Fill with zero bytes (silence)
        frame.planes[0].update(b'\x00' * 1920) 
        frame.pts = pts
        frame.sample_rate = 48000
        frame.time_base = time_base
        return frame

def calculate_age(uid: str) -> int:
    """
    Dynamic age formula based on string hash.
    (BOT_UID.hashCode.abs() % 6) + 20
    """
    # Use MD5 to get a consistent deterministic integer from the UID
    h = int(hashlib.md5(uid.encode()).hexdigest(), 16)
    return (abs(h) % 6) + 20

# Global variables for async loop coordination
loop = None
sqlite_conn = None
pcs = set()

# ==========================================
# 3. MANUAL LIVE CHAT VIA RTDB TRANSIT
# ==========================================
def handle_transit_message(event, bot_uid):
    """
    Callback triggered by Firebase RTDB when new messages arrive.
    Note: This runs in a background thread provided by firebase_admin.
    """
    if loop:
        loop.call_soon_threadsafe(print, f"[DEBUG] RTDB Event on {event.path}: {event.data}")
        
    if not event.data:
        return
    
    path = event.path
    if path == '/':
        # Initial read or bulk update (multiple messages)
        messages = event.data
        if isinstance(messages, dict):
            for msg_id, msg_data in messages.items():
                process_single_message(msg_id, msg_data, bot_uid)
    else:
        # Single message added (e.g. /msg_id)
        msg_id = path.lstrip('/')
        process_single_message(msg_id, event.data, bot_uid)

def process_single_message(msg_id, msg_data, bot_uid):
    if not isinstance(msg_data, dict):
        return
    
    sender_id = msg_data.get('senderId', msg_data.get('sender_id', 'unknown'))
    text = msg_data.get('text', '')
    
    # Update active caller so operator can reply directly without typing ID
    global active_caller_id
    active_caller_id = sender_id
    
    # Save locally to SQLite
    save_message_locally(sqlite_conn, msg_id, sender_id, bot_uid, text)
    
    # Print to terminal safely from the background thread
    if loop:
        def print_msg():
            print(f"\n\n[INCOMING FROM {sender_id}]: {text}\n> ", end="", flush=True)
        loop.call_soon_threadsafe(print_msg)
    
    # Push READ ACK (status 3) to Flutter app so it shows double blue ticks!
    try:
        db.reference(f'transit/acks/{sender_id}/{msg_id}').set({
            'status': 3,
            'timestamp': int(time.time() * 1000)
        })
    except Exception as e:
        if loop:
            loop.call_soon_threadsafe(lambda: print(f"Failed to send ACK: {e}"))
            
    # IMMEDIATELY DELETE from RTDB to keep cloud cost at zero
    try:
        db.reference(f'transit/messages/{bot_uid}/{msg_id}').delete()
    except Exception as e:
        if loop:
            loop.call_soon_threadsafe(lambda: print(f"Failed to delete RTDB message {msg_id}: {e}"))

# ==========================================
# 4. WEBRTC P2P SIGNALING
# ==========================================
async def handle_webrtc_offer(pc, offer_dict, caller_uid, bot_uid, room_id):
    
    offer = RTCSessionDescription(sdp=offer_dict['sdp'], type=offer_dict['type'])
    await pc.setRemoteDescription(offer)
    
    # Add the placeholder audio track
    pc.addTrack(SilenceAudioTrack())
    
    # Generate and set local answer
    answer = await pc.createAnswer()
    await pc.setLocalDescription(answer)
    
    # Write the answer back to RTDB for the Flutter client
    answer_dict = {
        'type': pc.localDescription.type,
        'sdp': pc.localDescription.sdp
    }
    
    def send_answer():
        # Update the specific room ID and set status to connected
        db.reference(f'calls/{room_id}').update({
            'answer': answer_dict,
            'status': 'connected'
        })
        
    await loop.run_in_executor(None, send_answer)
    # The terminal print is now handled by the animation function

def on_call_event(event, bot_uid):
    """
    Callback for incoming WebRTC signaling in RTDB.
    """
    if not event.data:
        return
        
    path = event.path
    data = event.data
    
    def process_call(room_id, call_data):
        if call_data.get('receiverId') != bot_uid:
            return
        if call_data.get('status') != 'calling':
            return
        if 'offer' not in call_data:
            return
            
        offer_dict = call_data['offer']
        caller_uid = call_data.get('callerId', 'unknown')
        
        # We process WebRTC on the asyncio loop
        pc = RTCPeerConnection()
        pcs.add(pc)
        
        @pc.on("iceconnectionstatechange")
        async def on_iceconnectionstatechange():
            print(f"\n[WebRTC ICE State]: {pc.iceConnectionState}\n> ", end="", flush=True)
            if pc.iceConnectionState in ["failed", "closed"]:
                pcs.discard(pc)
                
        global pending_call_data
        pending_call_data = {
            'pc': pc,
            'offer_dict': offer_dict,
            'caller_uid': caller_uid,
            'bot_uid': bot_uid,
            'room_id': room_id
        }
        
        # Show prompt to press Enter
        if loop:
            loop.call_soon_threadsafe(lambda: print(f"\n\a\033[93m=========================================\n 📞 INCOMING CALL FROM: {caller_uid}\n ⏳ Press ENTER to accept the call...\n=========================================\033[0m\n> ", end="", flush=True))

    if path == '/':
        for room_id, call_data in data.items():
            if isinstance(call_data, dict):
                process_call(room_id, call_data)
    else:
        # e.g., path = '/-OwYcN_-mAWpOjazgeRo'
        room_id = path.lstrip('/')
        # It could also be deeper like '/-OwYcN_-mAWpOjazgeRo/status'
        if '/' not in room_id and isinstance(data, dict):
            process_call(room_id, data)

def on_active_calls_event(event, bot_uid):
    """
    Callback for MatchmakingService locking the bot in active_calls.
    When a user wants to connect via Random Matchmaking, they lock us and wait for 'ringing'.
    """
    if not event.data:
        return
    
    # If the event data is a dict and has status 'locked', we update it to 'ringing'
    if isinstance(event.data, dict) and event.data.get('status') == 'locked':
        caller_uid = event.data.get('callerUid', 'unknown')
        if loop:
            loop.call_soon_threadsafe(lambda: print(f"\n[Random Matchmaking]: Locked by {caller_uid}. Sending 'ringing' signal..."))
        # Tell the flutter app we are alive and ringing
        db.reference(f'active_calls/{bot_uid}').update({
            'status': 'ringing'
        })

# ==========================================
# 5. ASYNC CHAT LOOP (OPERATOR INPUT)
# ==========================================
async def chat_loop(bot_uid):
    global active_caller_id, pending_call_data
    print(f"\n[{bot_uid}] Ready for chat.")
    print("When you receive a message, you can just type your reply directly!")
    print("To switch user manually, use:  caller_id:message")
    print(f"Type 'quit' to exit.\n")
    
    while True:
        try:
            # Dynamic prompt based on active caller
            prompt = f"[{active_caller_id}]> " if active_caller_id else "> "
            line = await ainput(prompt)
            
            if pending_call_data and not line.strip():
                print("\033[92m✅ Call Accepted! Audio stream live.\033[0m")
                asyncio.run_coroutine_threadsafe(
                    handle_webrtc_offer(**pending_call_data), 
                    loop
                )
                pending_call_data = None
                continue

            if not line:
                continue
                
            if line.strip().lower() == 'quit':
                break
            
            if ':' in line:
                # User is manually switching or specifying caller
                caller_id, msg = line.split(':', 1)
                active_caller_id = caller_id.strip()
                msg = msg.strip()
            else:
                # User is relying on active caller
                if not active_caller_id:
                    print("No active chat! Please specify caller_id:message")
                    continue
                caller_id = active_caller_id
                msg = line.strip()
            
            if not caller_id or not msg:
                continue
            
            msg_id = f"msg_{int(time.time() * 1000)}"
            timestamp = int(time.time() * 1000)
            
            # Save locally
            save_message_locally(sqlite_conn, msg_id, bot_uid, caller_id, msg)
            
            # Generate deterministic roomId exactly like Flutter does
            users = [bot_uid, caller_id]
            users.sort()
            room_id = f"{users[0]}_{users[1]}"
            
            # Send to transit for Flutter client to receive
            out_payload = {
                'msgId': msg_id,
                'roomId': room_id,
                'senderId': bot_uid,
                'text': msg,
                'timestamp': timestamp,
                'status': 1
            }
            
            def push_msg():
                db.reference(f'transit/messages/{caller_id}/{msg_id}').set(out_payload)
                
            await loop.run_in_executor(None, push_msg)
            print(f"[SENT TO {caller_id}]: {msg}")
            
        except EOFError:
            break
        except Exception as e:
            print(f"Error in chat loop: {e}")

# ==========================================
# 6. MAIN ORCHESTRATOR
# ==========================================
async def main():
    global loop, sqlite_conn
    loop = asyncio.get_running_loop()
    
    # CLI Argument Parsing
    parser = argparse.ArgumentParser(description="Headless WebRTC Female Expert Bot")
    parser.add_argument("--uid", required=True, help="Mandatory: Firebase Auth UID for the bot")
    parser.add_argument("--name", help="Optional: Display Name")
    parser.add_argument("--lang", help="Optional: Language (e.g. Hindi, English)")
    parser.add_argument("--age", type=int, help="Optional: Age")
    parser.add_argument("--cert", default="serviceAccountKey.json", help="Path to Firebase Service Account JSON")
    parser.add_argument("--db-url", default="https://zegochat-c44b0.asia-southeast1.firebasedatabase.app", help="Firebase RTDB URL")
    
    args = parser.parse_args()
    bot_uid = args.uid
    
    print("[1/5] Initializing Local SQLite Database...")
    sqlite_conn = init_db()
    
    print("[2/5] Initializing Firebase Admin SDK...")
    try:
        cred = credentials.Certificate(args.cert)
        firebase_admin.initialize_app(cred, {
            'databaseURL': args.db_url
        })
    except ValueError:
         pass # App already initialized
         
    firestore_db = firestore.client()
    
    print(f"[3/5] Smart Data Fetching for Firestore {bot_uid}...")
    doc_ref = firestore_db.collection('experts').document(bot_uid)
    doc = await loop.run_in_executor(None, doc_ref.get)
    
    # Fallback/Merge logic
    if doc.exists:
        data = doc.to_dict()
        lang = args.lang if args.lang else data.get('languages', 'Hindi')
        age = args.age if args.age else data.get('age', calculate_age(bot_uid))
        name = args.name if args.name else data.get('nickname', f"Expert_{bot_uid[:4]}")
    else:
        lang = args.lang if args.lang else 'Hindi'
        age = args.age if args.age else calculate_age(bot_uid)
        name = args.name if args.name else f"Expert_{bot_uid[:4]}"
        
    print(f"      -> Profile Ready: Name={name}, Lang={lang}, Age={age}")
    
    # Upsert Profile
    profile_data = {
        'nickname': name,
        'isOnline': True,
        'pricePerMin': 5,
        'rating': 5.0,
        'languages': lang,
        'age': age,
        'fcmToken': 'terminal_dummy_token'
    }
    await loop.run_in_executor(None, lambda: doc_ref.set(profile_data, merge=True))
    
    print("[4/5] Establishing RTDB Queue Presence & Disconnect Protection...")
    status_ref = db.reference(f'status/{bot_uid}')
    queue_ref = db.reference(f'queues/{lang}/{bot_uid}')
    
    # Secure cleanup if PC crashes (on_disconnect is only for Client SDKs, not Admin SDK)
    # We rely on the try...finally block below to clean up presence on exit.
    
    presence_payload = {
        'isOnline': True,
        'nickname': name
    }
    status_ref.set(presence_payload)
    queue_ref.set(presence_payload)
    
    print("[5/5] Activating Listeners...")
    # Transit Chat Listener
    transit_ref = db.reference(f'transit/messages/{bot_uid}')
    transit_ref.listen(lambda event: handle_transit_message(event, bot_uid))
    
    # WebRTC Listener (listen to all calls and filter in callback)
    calls_ref = db.reference('calls')
    calls_ref.listen(lambda event: on_call_event(event, bot_uid))
    
    # Active Calls Lock Listener (for random matchmaking ringing response)
    active_calls_ref = db.reference(f'active_calls/{bot_uid}')
    active_calls_ref.listen(lambda event: on_active_calls_event(event, bot_uid))
    
    # Enter Async Terminal Interaction
    try:
        await chat_loop(bot_uid)
    finally:
        print("\nCleaning up connections...")
        # Clean up presence manually on graceful exit
        status_ref.delete()
        queue_ref.delete()
        for pc in pcs:
            await pc.close()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nBot stopped by user.")
