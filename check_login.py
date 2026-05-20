"""Verify login_screen.dart Column children close matches open at same indent."""
import sys
sys.stdout.reconfigure(encoding='utf-8')

path = r'C:\Users\Yene\classai\lib\features\auth\screens\login_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

print("=== Column at 152 (login_screen.dart) children open/close ===")
print(f"  Open  line 152: {repr(lines[151][:80])}")
# Find the close by searching from line 152 onwards
for i in range(151, 545):
    s = lines[i].strip()
    if s == '],':
        spaces = len(lines[i]) - len(lines[i].lstrip(' '))
        print(f"  Close line {i+1} ({spaces} spaces): {repr(lines[i].strip())}")
        break

print("\n=== Column at 210 children open/close ===")
print(f"  Open  line 211: {repr(lines[210][:80])}")
for i in range(210, 545):
    s = lines[i].strip()
    if s == '],':
        spaces = len(lines[i]) - len(lines[i].lstrip(' '))
        print(f"  Close line {i+1} ({spaces} spaces): {repr(lines[i].strip())}")
        break

print("\n=== Column at 438 children open/close ===")
for i in range(437, 545):
    s = lines[i].strip()
    if s == '],':
        spaces = len(lines[i]) - len(lines[i].lstrip(' '))
        print(f"  Close line {i+1} ({spaces} spaces): {repr(lines[i].strip())}")
