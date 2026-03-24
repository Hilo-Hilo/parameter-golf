#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
import sys
import time

def run_cmd(cmd):
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Command failed: {cmd}\n{result.stderr}", file=sys.stderr)
        return None
    return result.stdout.strip()

def get_pods():
    # Example using runpodctl
    out = run_cmd("runpodctl get pods -o json")
    if not out:
        return []
    try:
        return json.loads(out)
    except json.JSONDecodeError:
        return []

def create_pod(name, gpu_type, gpu_count):
    # This is a placeholder for actual runpodctl create pod command
    cmd = f"runpodctl create pod --name {name} --gpuType {gpu_type} --gpuCount {gpu_count} -o json"
    out = run_cmd(cmd)
    return json.loads(out) if out else None

def stop_pod(pod_id):
    run_cmd(f"runpodctl stop pod {pod_id}")

def terminate_pod(pod_id):
    run_cmd(f"runpodctl remove pod {pod_id}")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["list", "create", "stop", "terminate"])
    parser.add_argument("--name", type=str)
    parser.add_argument("--gpu-type", type=str)
    parser.add_argument("--gpu-count", type=int)
    parser.add_argument("--pod-id", type=str)
    
    args = parser.parse_args()
    
    if args.action == "list":
        pods = get_pods()
        print(json.dumps(pods, indent=2))
    elif args.action == "create":
        res = create_pod(args.name, args.gpu_type, args.gpu_count)
        if res: print(json.dumps(res, indent=2))
    elif args.action == "stop":
        stop_pod(args.pod_id)
    elif args.action == "terminate":
        terminate_pod(args.pod_id)

if __name__ == "__main__":
    main()
