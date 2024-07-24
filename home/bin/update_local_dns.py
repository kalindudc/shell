#!/usr/bin/env python3

import requests
import os
import time
import base64
from datetime import datetime, timezone, timedelta

# Get the current UTC time
utc_time = datetime.now(timezone.utc)

# Define the local timezone offset (example: UTC-4 for Eastern Daylight Time)
local_timezone_offset = timedelta(hours=-4)
local_timezone = timezone(local_timezone_offset)

# Convert UTC time to local timezone
local_time = utc_time.astimezone(local_timezone)

# Print the local time with timezone information
print("Current time:", local_time.strftime("%Y-%m-%d %H:%M:%S %Z%z"))

# Omada Controller details
omada_base_url = "https://192.168.0.110:443"

omada_id_env = os.getenv("OMADA_ID")
client_id_env = os.getenv("OMADA_CLIENT_ID")
client_secret_env = os.getenv("OMADA_CLIENT_SECRET")
if not all([omada_id_env, client_id_env, client_secret_env]):
  raise EnvironmentError('One or more environment variables are missing.')

omada_id = base64.b64decode(omada_id_env).decode('utf-8').strip()
client_id = base64.b64decode(client_id_env).decode('utf-8').strip()
client_secret = base64.b64decode(client_secret_env).decode('utf-8').strip()

# Pi-hole local DNS file path
pihole_local_dns_file = "/etc/pihole/custom.list"

# Global variables
access_token = None
token_expiry = None

# Function to get a new access token
def get_access_token():
  global access_token, token_expiry
  url = f"{omada_base_url}/openapi/authorize/token?grant_type=client_credentials"
  headers = {
    "Content-Type": "application/json"
  }
  data = {
    "omadacId": omada_id,
    "client_id": client_id,
    "client_secret": client_secret
  }

  response = requests.post(url, json=data, headers=headers, verify=False)
  response_data = response.json()

  if response_data.get("errorCode") == 0:
    access_token = response_data["result"]["accessToken"]
    expires_in = response_data["result"]["expiresIn"]
    token_expiry = time.time() + expires_in
    print("Access token acquired successfully.")
  else:
    print("Failed to acquire access token.")
    access_token = None

# Function to check if the token is expired
def is_token_expired():
  return time.time() > token_expiry if token_expiry else True

# Function to get device information from Omada Controller
def get_omada_devices():
  if is_token_expired():
    get_access_token()

  if not access_token:
    raise Exception("No valid access token available.")

  headers = {
    "Authorization": f"AccessToken={access_token}"
  }

  current_page = 1
  page_size = 100
  total_devices = -1
  devices_count = 0

  device_info = {}

  done = False
  while not done:
    devices_url = f"{omada_base_url}/openapi/v1/{omada_id}/sites/Default/clients?page={current_page}&pageSize={page_size}"
    response = requests.get(devices_url, headers=headers, verify=False)

    response_data = response.json()
    if response_data.get("errorCode") != 0:
      print("Failed to acqured devices.")
      return

    result = response_data["result"]
    if total_devices < 0:
      total_devices = result["totalRows"]

    devices_count = min(devices_count + page_size, total_devices)
    devices = result['data']

    for device in devices:
      hostname = device.get('name')
      ip_address = device.get('ip')
      if hostname and ip_address:
        device_info[hostname.lower().replace("_", "-")] = ip_address

    if devices_count >= total_devices:
      break

  return device_info

# Function to update Pi-hole local DNS
def update_pihole_local_dns(device_info):
  with open(pihole_local_dns_file, 'w') as file:
    for name, ip_address in device_info.items():
      file.write(f"{ip_address} {name}.lan\n")

# Function to restart Pi-hole DNS service
def restart_pihole_dns():
  os.system("/usr/local/bin/pihole restartdns")

# Main function
def main():
  get_access_token()  # Ensure token is acquired initially
  device_info = get_omada_devices()

  if len(device_info) == 0:
    print ("Could not acquire devices.")
    return

  print("Acquired all devices")

  update_pihole_local_dns(device_info)

  print ("Successfully updated local DNS.")

  restart_pihole_dns()

  print ("Successfully restarted pihole dns.")


if __name__ == "__main__":
  main()
