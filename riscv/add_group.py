#!/usr/bin/env python3
"""
Helper script to add a new synthesis group
Makes it easier to keep Racket and Python code in sync
"""

import re
import sys

def add_group_to_racket(file_path, group_name, instructions):
    """Add group to both locations in interactive-synthesis.rkt"""

    with open(file_path, 'r') as f:
        lines = f.readlines()

    # Create the new group entry
    inst_list = " ".join(instructions)
    new_entry = f"                          ({group_name} . ({inst_list}))"

    # Process line by line to find the pattern
    updated_lines = []
    count = 0

    i = 0
    while i < len(lines):
        line = lines[i]

        # Look for lines that end a group hash definition
        # Pattern: ends with "))" and previous line contains "mul-synthesis" or similar
        if line.strip().endswith("))))") and i > 0:
            # Check if this is part of a groups hash definition
            # Look backwards to find "(define groups #hash"
            is_groups_hash = False
            for j in range(max(0, i-10), i):
                if "(define groups #hash" in lines[j]:
                    is_groups_hash = True
                    break

            if is_groups_hash:
                # Insert new group before the closing )))
                # Replace "))" with new group + "))"
                modified_line = line.replace("))))", new_entry + "\n                          ))))")
                updated_lines.append(modified_line)
                count += 1
                i += 1
                continue

        updated_lines.append(line)
        i += 1

    if count != 2:
        print(f"Warning: Expected to update 2 locations, but updated {count}")
        print("You may need to manually check interactive-synthesis.rkt")

    with open(file_path, 'w') as f:
        f.writelines(updated_lines)

    print(f"✓ Updated {file_path} with {group_name} ({count} locations)")

def add_group_to_python(file_path, group_name, instructions):
    """Add group to auto_synthesis.py"""

    with open(file_path, 'r') as f:
        content = f.read()

    # Find the instruction_groups dict
    pattern = r'(self\.instruction_groups = \{[^}]+)\}'

    # Create new entry
    inst_list = '", "'.join(instructions)
    new_entry = f'            "{group_name}": ["{inst_list}"]'

    def add_to_dict(match):
        dict_content = match.group(1)
        return dict_content + ',\n' + new_entry + '\n        }'

    updated_content = re.sub(pattern, add_to_dict, content, flags=re.DOTALL)

    # Also update the argparse choices if present
    choices_pattern = r"(choices=\[\'[^]]+)\]"

    def add_to_choices(match):
        choices = match.group(1)
        return choices + f", '{group_name}']"

    updated_content = re.sub(choices_pattern, add_to_choices, updated_content)

    with open(file_path, 'w') as f:
        f.write(updated_content)

    print(f"✓ Updated {file_path} with {group_name}")

def show_current_groups():
    """Display currently defined groups"""
    print("\nCurrently defined synthesis groups:")
    print("=" * 60)

    groups = {
        "slt-synthesis": ["sub", "srli", "xor", "sltu", "and", "xori", "or", "addi", "andi"],
        "and-synthesis": ["not", "or", "sub", "add"],
        "or-synthesis": ["not", "and", "sub", "add"],
        "xor-synthesis": ["and", "or", "sub", "add", "not"],
        "mul-synthesis": ["add", "slli", "sub", "sll", "srl", "sra", "and", "or", "xor", "andi"]
    }

    for name, insts in groups.items():
        print(f"{name:20} : {', '.join(insts)}")
    print("=" * 60)

def interactive_add():
    """Interactive mode to add a new group"""
    print("\n" + "=" * 60)
    print("ADD NEW SYNTHESIS GROUP")
    print("=" * 60)

    show_current_groups()

    print("\nEnter new group details:")
    group_name = input("Group name (e.g., 'div-synthesis'): ").strip()

    if not group_name.endswith('-synthesis'):
        group_name += '-synthesis'
        print(f"→ Using name: {group_name}")

    print("\nEnter allowed instructions (space or comma separated):")
    print("Example: add sub sll srl and or")
    inst_input = input("Instructions: ").strip()

    # Parse instructions
    instructions = re.split(r'[,\s]+', inst_input)
    instructions = [i.strip() for i in instructions if i.strip()]

    print(f"\n→ Group: {group_name}")
    print(f"→ Instructions: {', '.join(instructions)}")

    confirm = input("\nAdd this group? [y/N]: ").strip().lower()

    if confirm == 'y':
        add_group_to_racket('interactive-synthesis.rkt', group_name, instructions)
        add_group_to_python('auto_synthesis.py', group_name, instructions)
        print("\n✓ Group added successfully!")
        print(f"\nUsage:")
        print(f"  python3 auto_synthesis.py target.s --group {group_name}")
    else:
        print("Cancelled.")

def main():
    if len(sys.argv) > 1 and sys.argv[1] == '--show':
        show_current_groups()
        return

    if len(sys.argv) >= 3:
        # Command-line mode
        group_name = sys.argv[1]
        instructions = sys.argv[2:]

        print(f"Adding group: {group_name}")
        print(f"Instructions: {', '.join(instructions)}")

        add_group_to_racket('interactive-synthesis.rkt', group_name, instructions)
        add_group_to_python('auto_synthesis.py', group_name, instructions)

        print("\n✓ Done!")
    else:
        # Interactive mode
        interactive_add()

if __name__ == '__main__':
    main()