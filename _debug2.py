"""Show exact bytes for lines 150-215 (Column at 152 area) and 300-340 to debug."""
import sys
sys.stdout.reconfigure(encoding='utf-8')

path = r'C:\Users\Yene\classai\lib\features\auth\screens\login_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

print("=== Column 152 section (150-215) ===")
for i in range(149, 215):
    ln = lines[i]
    spaces = len(ln) - len(ln.lstrip(' '))
    print(f"  {i+1:4d} ({spaces:2d}S): {repr(ln.rstrip())[:90]}")

print("\n=== Lines 300-340 (Sign In button close + secondary links) ===")
for i in range(299, 340):
    ln = lines[i]
    spaces = len(ln) - len(ln.lstrip(' '))
    print(f"  {i+1:4d} ({spaces:2d}S): {repr(ln.rstrip())[:90]}")
