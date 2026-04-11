#!/usr/bin/env bash

MOUNT="$HOME/Tablet"

echo "[*] Cleaning up old mount..."
fusermount3 -u -z "$MOUNT" 2>/dev/null || sudo umount -l "$MOUNT" 2>/dev/null

echo "[*] Resetting mount directory..."
rm -rf "$MOUNT"
mkdir -p "$MOUNT"
chmod 755 "$MOUNT"

echo "[*] Mounting device..."
go-mtpfs -android -allow-other "$MOUNT"

if [ $? -ne 0 ]; then
    echo "[!] Mount failed"
    exit 1
fi

echo "[*] Mounted at $MOUNT"
echo "[*] Press ENTER to unmount..."
read

echo "[*] Unmounting..."
fusermount3 -u "$MOUNT" || sudo umount -l "$MOUNT"

echo "[*] Done"
