#!/usr/bin/env python3
import json
import os
import subprocess

def run_gh(cmd):
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error running gh: {result.stderr}")
        return None
    return result.stdout

def sync():
    os.makedirs("context/upstream", exist_ok=True)
    
    print("Fetching issue #140...")
    issue_140 = run_gh("gh issue view 140 --repo openai/parameter-golf --json body,title,comments")
    if issue_140:
        data = json.loads(issue_140)
        with open("context/upstream/issue_140.md", "w") as f:
            f.write(f"# {data.get('title', '')}\n\n")
            f.write(data.get('body', '') + "\n\n")
            f.write("## Comments\n")
            for c in data.get('comments', []):
                f.write(f"**{c.get('author', {}).get('login', 'Unknown')}**:\n{c.get('body', '')}\n\n")

    print("Fetching PR index...")
    prs = run_gh("gh pr list --repo openai/parameter-golf --state all --limit 50 --json number,title,author,state,createdAt")
    if prs:
        with open("context/upstream/pr_index.json", "w") as f:
            f.write(prs)

    print("Fetching Issues index...")
    issues = run_gh("gh issue list --repo openai/parameter-golf --state all --limit 50 --json number,title,author,state,createdAt")
    if issues:
        with open("context/upstream/issue_index.json", "w") as f:
            f.write(issues)
            
    print("Generating frontier digest...")
    # Just a stub digest
    with open("context/upstream/frontier_digest.md", "w") as f:
        f.write("# Upstream Frontier Digest\n\nAutomatically generated summary of the latest SOTA from upstream.\nCheck issue_140.md and pr_index.json for details.\n")

if __name__ == "__main__":
    sync()
