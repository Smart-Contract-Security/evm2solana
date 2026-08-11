import json
import shutil
from pathlib import Path

SAMPLE_FILE = Path("logs/build_dataset/sample.json")
SOURCE_DIR = Path("empirical/dataset")
TARGET_DIR = Path("dataset")


if __name__ == "__main__":
    with open(SAMPLE_FILE, encoding="utf-8") as f:
        sample = json.load(f)

    sample_list = sample["sample_list"]

    for item in sample_list:
        address = item["address"]
        tier = item["tier"]

        src = SOURCE_DIR / address
        target = TARGET_DIR / tier / address

        shutil.copytree(src, target, dirs_exist_ok=True)
