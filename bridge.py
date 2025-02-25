import os
import asyncio
import sys
from gmqtt import Client as MQTTClient
from google.cloud import pubsub_v1

# Environment variables
MQTT_BROKER = os.getenv("MQTT_BROKER")
MQTT_PORT = int(os.getenv("MQTT_PORT", 1883))
MQTT_TOPIC = os.getenv("MQTT_TOPIC", "plant-floor/data/#")
MQTT_USERNAME = os.getenv("MQTT_USERNAME")
MQTT_PASSWORD = os.getenv("MQTT_PASSWORD")
PUBSUB_TOPIC = os.getenv("PUBSUB_TOPIC")

# Initialize Google Cloud Pub/Sub publisher
publisher = pubsub_v1.PublisherClient()

# MQTT client setup
client = MQTTClient(client_id="mqtt-bridge")

# Callback for when the client connects
def on_connect(client, flags, rc, properties):
    print(f"Connected to MQTT broker with result code {rc}", flush=True)
    client.subscribe(MQTT_TOPIC)
    print(f"Subscribed to topic: {MQTT_TOPIC}", flush=True)

# Callback for when a message is received
def on_message(client, topic, payload, qos, properties):
    payload_str = payload.decode("utf-8")
    print(f"Received MQTT message on {topic}: {payload_str}", flush=True)
    try:
        publisher.publish(PUBSUB_TOPIC, payload)
        print(f"Published to Pub/Sub: {payload_str}", flush=True)
    except Exception as e:
        print(f"Error publishing to Pub/Sub: {e}", flush=True)

# Callback for disconnection
def on_disconnect(client, packet, exc=None):
    print("Disconnected from MQTT broker", flush=True)

# Set up callbacks
client.on_connect = on_connect
client.on_message = on_message
client.on_disconnect = on_disconnect

# Set authentication if provided
if MQTT_USERNAME and MQTT_PASSWORD:
    client.set_auth_credentials(MQTT_USERNAME, MQTT_PASSWORD)

# Main function to run the client
async def main():
    while True:
        try:
            await client.connect(MQTT_BROKER, MQTT_PORT, keepalive=60)
            print(f"Connecting to {MQTT_BROKER}:{MQTT_PORT}", flush=True)
            await asyncio.Future()  # Wait indefinitely
        except Exception as e:
            print(f"Connection failed: {e}", flush=True)
            await asyncio.sleep(5)  # Retry after 5 seconds

# Run the event loop
if __name__ == "__main__":
    loop = asyncio.get_event_loop()
    try:
        loop.run_until_complete(main())
    except KeyboardInterrupt:
        loop.run_until_complete(client.disconnect())
        loop.close()
        print("Bridge stopped", flush=True)
        