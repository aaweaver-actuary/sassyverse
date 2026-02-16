#!/usr/bin/env python3
"""Upload and run a SAS script over SSH, capturing stdout/stderr and a SAS log."""

import argparse
import getpass
import os
import posixpath
import sys

import paramiko


def read_password(path: str) -> str:
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read().strip()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Upload a SAS script to a remote host and execute it."
    )
    parser.add_argument("--host", required=True, help="SSH host, e.g., lnxvsashq001")
    parser.add_argument("--user", required=True, help="SSH username")
    parser.add_argument(
        "--password-file",
        required=True,
        default=".pw",
        help="Path to a file containing the SSH password",
    )
    parser.add_argument(
        "--local-script",
        default="testing.sas",
        help="Local SAS script to upload (default: testing.sas)",
    )
    parser.add_argument(
        "--remote-dir",
        default="/home/aweaver",
        help="Remote directory to upload the script into",
    )
    parser.add_argument(
        "--sas-cmd",
        default="/sas/install/SASHome9.5/SASFoundation/9.4/bin/sas_u8",
        help="SAS executable on the remote host",
    )
    parser.add_argument(
        "--log-name",
        default="run_tests.log",
        help="SAS log filename to write on the remote host",
    )
    parser.add_argument(
        "--download-dir",
        default=".",
        help="Local directory for downloaded log (default: current dir)",
    )
    return parser.parse_args()


def ensure_remote_dir(sftp: paramiko.SFTPClient, remote_dir: str) -> None:
    try:
        sftp.listdir(remote_dir)
    except IOError:
        sftp.mkdir(remote_dir)


def run_remote_sas(
    ssh: paramiko.SSHClient,
    sas_cmd: str,
    remote_script: str,
    remote_log: str,
) -> int:
    cmd = (
        f"{sas_cmd} -sysin {remote_script} "
        f"-log {remote_log} -print {remote_log}.lst"
    )
    stdin, stdout, stderr = ssh.exec_command(cmd)
    stdin.close()
    stdout_data = stdout.read().decode("utf-8", errors="replace")
    stderr_data = stderr.read().decode("utf-8", errors="replace")

    if stdout_data:
        print("=== STDOUT ===")
        print(stdout_data)
    if stderr_data:
        print("=== STDERR ===")
        print(stderr_data)

    return stdout.channel.recv_exit_status()


def main() -> int:
    args = parse_args()
    password = read_password(args.password_file)

    local_script = os.path.abspath(args.local_script)
    if not os.path.exists(local_script):
        print(f"Local script not found: {local_script}", file=sys.stderr)
        return 2

    remote_dir = args.remote_dir.rstrip("/")
    remote_script = posixpath.join(remote_dir, os.path.basename(local_script))
    remote_log = posixpath.join(remote_dir, args.log_name)

    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(args.host, username=args.user, password=password)

    try:
        sftp = ssh.open_sftp()
        try:
            ensure_remote_dir(sftp, remote_dir)
            sftp.put(local_script, remote_script)
        finally:
            sftp.close()

        exit_code = run_remote_sas(ssh, args.sas_cmd, remote_script, remote_log)

        download_dir = os.path.abspath(args.download_dir)
        os.makedirs(download_dir, exist_ok=True)
        local_log = os.path.join(download_dir, args.log_name)

        sftp = ssh.open_sftp()
        try:
            sftp.get(remote_log, local_log)
        finally:
            sftp.close()

        print(f"Downloaded log to: {local_log}")
        return exit_code
    finally:
        ssh.close()


if __name__ == "__main__":
    sys.exit(main())
