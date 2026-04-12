#!/usr/bin/env python3
"""
Converts phone conversation .dialogue files to .json conversation trees.

Usage:
    python tools/conv_dialogue_to_json.py                          # all files in data/phone_conversations/
    python tools/conv_dialogue_to_json.py data/phone_conversations/text_poison.dialogue  # single file

Format:
    # sender: Character Name
    # style_tag: npc_default

    ~ node_name
    Sender: Message text
    Sender: Message with custom style {style_tag}
    Sender: Conditional message [if GameState.has_tag("some_tag")]
    do GameState.set_tag("tag_to_set_when_node_reached")
    - Reply option [tag_name] => next_node
    - Terminal reply [tag_name]
    - Conditional option [tag_name] [if GameState.has_tag("required_tag")] => next
    - Negated condition [if not GameState.has_tag("blocked_tag")]
    Sender: Content after options = auto-generated next node
    - More options [tag]

    ~ another_node
    ...

Conditions:
    [if GameState.has_tag("tag")]       -> option/message only shown if tag is set
    [if not GameState.has_tag("tag")]   -> option/message only shown if tag is NOT set

Implicit flow:
    Options without => jumps that are followed by more content at the same
    level automatically flow into that content (auto-named node_2, node_3...).
    This matches Dialogue Manager behavior.
"""

import sys
import os
import re
import json

# Regex for condition brackets: [if GameState.has_tag("x")] or [if not GameState.has_tag("x")]
_CONDITION_RE = re.compile(r'\[if\s+(not\s+)?GameState\.has_tag\("([^"]+)"\)\]\s*$')

# Regex for do GameState.set_tag("x")
_SET_TAG_RE = re.compile(r'^do\s+GameState\.set_tag\("([^"]+)"\)')


def parse_dialogue_file(filepath):
    with open(filepath, "r", encoding="utf-8") as f:
        lines = f.readlines()

    sender_name = "Unknown"
    style_tag = "npc_default"
    basename = os.path.splitext(os.path.basename(filepath))[0]
    conversation_id = (basename[5:] if basename.startswith("text_") else basename) + "_conversation"

    in_tags_block = False
    sections = []
    current_title = None
    current_lines = []

    for raw_line in lines:
        line = raw_line.rstrip("\n").strip()

        # Metadata comments
        m = re.match(r"^#\s*sender:\s*(.+)$", line, re.IGNORECASE)
        if m:
            sender_name = m.group(1).strip()
            continue
        m = re.match(r"^#\s*style_tag:\s*(.+)$", line, re.IGNORECASE)
        if m:
            style_tag = m.group(1).strip()
            continue
        m = re.match(r"^#\s*conversation_id:\s*(.+)$", line, re.IGNORECASE)
        if m:
            conversation_id = m.group(1).strip()
            continue

        if line.startswith("#") or line == "":
            continue

        if line == "~ tags":
            in_tags_block = True
            continue

        if line.startswith("~ "):
            in_tags_block = False
            if current_title is not None:
                sections.append((current_title, current_lines))
            current_title = line[2:].strip()
            current_lines = []
            continue

        if in_tags_block:
            continue

        if line in ("=> END", "=> END!"):
            continue

        if current_title is not None:
            current_lines.append(line)

    if current_title is not None:
        sections.append((current_title, current_lines))

    nodes = {}
    for title, section_lines in sections:
        segments = _section_to_segments(section_lines)
        _segments_to_nodes(nodes, title, segments)

    return {
        "conversation_id": conversation_id,
        "sender_name": sender_name,
        "style_tag": style_tag,
        "nodes": nodes,
    }


def _section_to_segments(lines):
    """Split section into segments. A new segment starts when messages appear after options."""
    segments = []
    cur_msgs = []
    cur_opts = []
    cur_set_tags = []

    for line in lines:
        if line.startswith("- "):
            cur_opts.append(_parse_option(line))
        elif _SET_TAG_RE.match(line):
            tag = _SET_TAG_RE.match(line).group(1)
            cur_set_tags.append(tag)
        else:
            msg = _parse_message(line)
            if msg:
                if cur_opts:
                    segments.append({"messages": cur_msgs, "options": cur_opts, "set_tags": cur_set_tags})
                    cur_msgs = []
                    cur_opts = []
                    cur_set_tags = []
                cur_msgs.append(msg)

    if cur_msgs or cur_opts or cur_set_tags:
        segments.append({"messages": cur_msgs, "options": cur_opts, "set_tags": cur_set_tags})

    return segments


def _parse_message(line):
    """Parse 'Sender: text {style} [if condition]' into message dict."""
    m = re.match(r"^(\w[\w\s.]*?):\s+(.+)$", line)
    if not m:
        return None

    text = m.group(2).strip()
    style = None
    condition = None

    # Extract [if condition] at end (before style, since it's outermost)
    cm = _CONDITION_RE.search(text)
    if cm:
        negated = cm.group(1) is not None
        cond_tag = cm.group(2)
        condition = ("!" + cond_tag) if negated else cond_tag
        text = text[: cm.start()].strip()

    # Extract {style_tag} at end
    sm = re.search(r"\{(\w+)\}\s*$", text)
    if sm:
        style = sm.group(1)
        text = text[: sm.start()].strip()

    msg = {"text": text}
    if style:
        msg["style_tag"] = style
    if condition:
        msg["condition"] = condition
    return msg


def _parse_option(line):
    """Parse '- text [tag] [if condition] => next' into option dict."""
    text = line[2:].strip()
    tag = ""
    next_node = None
    condition = None

    # Extract => jump at end
    jm = re.search(r"=>\s*(\S+)\s*$", text)
    if jm:
        val = jm.group(1)
        if val not in ("END", "END!"):
            next_node = val
        text = text[: jm.start()].strip()

    # Extract [if condition] at end
    cm = _CONDITION_RE.search(text)
    if cm:
        negated = cm.group(1) is not None
        cond_tag = cm.group(2)
        condition = ("!" + cond_tag) if negated else cond_tag
        text = text[: cm.start()].strip()

    # Extract [tag] at end (after removing condition — this one is a plain tag, not "if ...")
    tm = re.search(r"\[([^\]]+)\]\s*$", text)
    if tm:
        tag = tm.group(1)
        text = text[: tm.start()].strip()

    opt = {"text": text}
    if tag:
        opt["tag"] = tag
    if next_node:
        opt["next"] = next_node
    if condition:
        opt["condition"] = condition
    return opt


def _segments_to_nodes(nodes, title, segments):
    """Convert segments to nodes. Options without => flow to the next segment."""
    for i, seg in enumerate(segments):
        name = title if i == 0 else f"{title}_{i + 1}"
        next_name = f"{title}_{i + 2}" if i + 1 < len(segments) else None

        if next_name:
            for opt in seg["options"]:
                if "next" not in opt:
                    opt["next"] = next_name

        node = {}
        if seg["messages"]:
            node["messages"] = seg["messages"]
        node["options"] = seg["options"] if seg["options"] else []
        if seg.get("set_tags"):
            node["set_tags"] = seg["set_tags"]
        nodes[name] = node


def convert_file(filepath):
    tree = parse_dialogue_file(filepath)
    out = os.path.splitext(filepath)[0] + ".json"
    with open(out, "w", encoding="utf-8") as f:
        json.dump(tree, f, indent="\t", ensure_ascii=False)
    print(f"  {os.path.basename(filepath)} -> {os.path.basename(out)}")
    return out


def main():
    target = sys.argv[1] if len(sys.argv) > 1 else "data/phone_conversations/"

    if os.path.isfile(target):
        convert_file(target)
    elif os.path.isdir(target):
        files = sorted(f for f in os.listdir(target) if f.endswith(".dialogue"))
        if not files:
            print(f"No .dialogue files in {target}")
            return
        for f in files:
            convert_file(os.path.join(target, f))
        print(f"\nConverted {len(files)} file(s)")
    else:
        print(f"Not found: {target}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
