"""Find structural errors in login_screen.dart."""
import sys
sys.stdout.reconfigure(encoding='utf-8')

path = r'C:\Users\Yene\classai\lib\features\auth\screens\login_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Print full declaration of each named Container/Button inside Column
start_line = 149  # Column starts

# Find important structural lines
print("=== All 'Container(' or 'SizedBox(' or 'FilledButton(' or 'Row(' occurrences after line 150 ===")
for i, ln in enumerate(lines[149:], start=150):
    if any(w in ln for w in ['Container(', 'SizedBox(', 'FilledButton(', 'Row(', 'Column(']) and 'child:' not in ln and 'import' not in ln and '/' not in ln.strip():
        spaces = len(ln) - len(ln.lstrip(' '))
        print(f"  {i:4d} ({spaces:2d}S): {repr(ln.strip()[:80])}")

print("\n=== All 'if (' occurrences in build (lines 150-340) ===")
for i, ln in enumerate(lines[149:335], start=150):
    if 'if (' in ln or 'if (' in ln:
        print(f"  {i:4d}: {repr(ln.strip()[:80])}")

print("\n=== validate/validator lines ===")
for i, ln in enumerate(lines[149:350], start=150):
    if 'validator' in ln or 'validate' in ln:
        print(f"  {i:4d}: {repr(ln.strip()[:80])}")
