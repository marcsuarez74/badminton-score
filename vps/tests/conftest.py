import sys
from pathlib import Path

# renderer.py vit dans vps/, les tests dans vps/tests/
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
