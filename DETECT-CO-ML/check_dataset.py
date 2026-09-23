import geopandas as gpd

file = "data/PH043400000_FH_5yr.shp"

print("Loading dataset...")
gdf = gpd.read_file(file)

print("\n=== DATASET INFO ===")
print("Rows:", len(gdf))
print("Columns:", list(gdf.columns))
print("CRS:", gdf.crs)

print("\n=== FIRST 5 ROWS ===")
print(gdf.head())

print("\n=== GEOMETRY TYPES ===")
print(gdf.geometry.geom_type.value_counts())

print("\n=== DATA TYPES ===")
print(gdf.dtypes)
