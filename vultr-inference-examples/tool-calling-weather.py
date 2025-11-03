#!/usr/bin/env python3
"""
Tool Calling Example with Vultr Serverless Inference
----------------------------------------------------

This script demonstrates how to use Vultr Serverless Inference's
OpenAI-compatible API to perform tool calling with the kimi-k2-instruct model.

It defines a get_weather() function that fetches real-time weather data
from the free Open-Meteo API using city coordinates from Nominatim (OpenStreetMap).

Requirements:
  pip install requests python-dotenv
  export VULTR_INFERENCE_API_KEY=your_vultr_key
"""

import os
import json
import requests
from dotenv import load_dotenv

load_dotenv()

API_URL = "https://api.vultrinference.com/v1/chat/completions"
VULTR_KEY = os.getenv("VULTR_INFERENCE_API_KEY")

if not VULTR_KEY:
    raise EnvironmentError("Missing environment variable: VULTR_INFERENCE_API_KEY")

HEADERS = {
    "Authorization": f"Bearer {VULTR_KEY}",
    "Content-Type": "application/json",
    "Accept": "application/json",
}

def get_coordinates(city: str):
    """Get latitude and longitude for a city using Nominatim (OpenStreetMap)."""
    try:
        url = f"https://nominatim.openstreetmap.org/search"
        params = {"city": city, "format": "json", "limit": 1}
        resp = requests.get(url, params=params, headers={"User-Agent": "VultrInferenceDemo/1.0"}, timeout=10)
        data = resp.json()

        if not data:
            return None, None

        lat = float(data[0]["lat"])
        lon = float(data[0]["lon"])
        return lat, lon
    except Exception as e:
        print(f"⚠️ Geocoding error: {e}")
        return None, None

def get_weather(city: str):
    """Fetch real-time weather for a given city using Open-Meteo."""
    lat, lon = get_coordinates(city)
    if not lat or not lon:
        return {"error": f"Could not find coordinates for {city}"}

    try:
        url = f"https://api.open-meteo.com/v1/forecast"
        params = {"latitude": lat, "longitude": lon, "current_weather": True}
        resp = requests.get(url, params=params, timeout=10)
        data = resp.json().get("current_weather", {})

        if not data:
            return {"error": "No weather data available"}

        return {
            "city": city,
            "temperature": f"{data.get('temperature', 'N/A')}°C",
            "windspeed": f"{data.get('windspeed', 'N/A')} km/h",
            "winddirection": f"{data.get('winddirection', 'N/A')}°",
            "time": data.get("time", "N/A"),
        }
    except Exception as e:
        return {"error": str(e)}

def send_initial_request(city: str):
    payload = {
        "model": "kimi-k2-instruct",
        "messages": [
            {"role": "user", "content": f"What's the weather like in {city}?"}
        ],
        "tools": [
            {
                "type": "function",
                "function": {
                    "name": "get_weather",
                    "description": "Get current weather for a given city",
                    "parameters": {
                        "type": "object",
                        "properties": {"city": {"type": "string"}},
                        "required": ["city"],
                    },
                },
            }
        ],
        "tool_choice": "auto",
    }

    print("\nSending initial request to model...")
    response = requests.post(API_URL, headers=HEADERS, json=payload)
    return response.json()

def process_tool_call(response_data):
    tool_calls = (
        response_data.get("choices", [{}])[0]
        .get("message", {})
        .get("tool_calls", [])
    )

    if not tool_calls:
        print("No tool call detected.\n")
        print(json.dumps(response_data, indent=2))
        return None

    tool_call = tool_calls[0]
    fn_name = tool_call["function"]["name"]
    args = json.loads(tool_call["function"]["arguments"])
    tool_call_id = tool_call["id"]

    print(f"Model requested function: {fn_name}({args})")

    if fn_name == "get_weather":
        result = get_weather(**args)
    else:
        result = {"error": f"Unknown function '{fn_name}'"}

    print("Tool result:", result)
    return tool_call_id, result

def send_tool_result(city: str, response_data, tool_call_id, result):
    followup_payload = {
        "model": "kimi-k2-instruct",
        "messages": [
            {"role": "user", "content": f"What's the weather like in {city}?"},
            response_data["choices"][0]["message"],
            {
                "role": "tool",
                "tool_call_id": tool_call_id,
                "content": json.dumps(result),
            },
        ],
    }

    print("\nSending tool result back to model...")
    followup_response = requests.post(API_URL, headers=HEADERS, json=followup_payload)
    return followup_response.json()

def main():
    print("Vultr Serverless Inference: Tool Calling Demo\n")
    city = input("Enter a city name: ").strip()

    initial_data = send_initial_request(city)

    tool_data = process_tool_call(initial_data)
    if not tool_data:
        return
    tool_call_id, result = tool_data

    final_data = send_tool_result(city, initial_data, tool_call_id, result)

    message = (
        final_data.get("choices", [{}])[0]
        .get("message", {})
        .get("content", "No response received.")
    )

    print("\nModel's Final Response:")
    print(message)


if __name__ == "__main__":
    main()
