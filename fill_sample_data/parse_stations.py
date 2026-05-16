import json
import psycopg2
from psycopg2.extras import execute_batch

# ----------------------------
# PostgreSQL configuration
# ----------------------------
DB_CONFIG = {
    "host": "localhost",
    "port": 5433,
    "dbname": "kolexdb",
    "user": "admin",
    "password": "admin123"
}

# ----------------------------
# Path to OSM JSON file
# ----------------------------
JSON_FILE = "stations.geojson"

# ----------------------------
# Read JSON
# ----------------------------
with open(JSON_FILE, "r", encoding="utf-8") as f:
    data = json.load(f)

features = data.get("features", [])

stations_to_insert = []

for feature in features:
    properties = feature.get("properties", {})
    geometry = feature.get("geometry", {})

    station_name = properties.get("name")

    # Skip if no station name
    if not station_name:
        continue

    stations_to_insert.append(
        (
            station_name,
        )
    )

# Remove duplicates
stations_to_insert = list(set(stations_to_insert))

print(f"Loaded {len(stations_to_insert)} stations")

# ----------------------------
# Connect to PostgreSQL
# ----------------------------
connection = psycopg2.connect(**DB_CONFIG)

cursor = connection.cursor()

# ----------------------------
# Insert stations
# ----------------------------
insert_query = """
INSERT INTO backend.station (
    station_name
)
VALUES (%s)
ON CONFLICT (station_name) DO NOTHING;
"""

execute_batch(cursor, insert_query, stations_to_insert)

connection.commit()

print("Stations inserted successfully")

# ----------------------------
# Cleanup
# ----------------------------
cursor.close()
connection.close()
