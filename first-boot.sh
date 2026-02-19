#!/bin/bash

bool_true() {
  case "${1,,}" in
    1|true|yes) return 0 ;;
    *) return 1 ;;
  esac
}

apply_settings() {
  adb wait-for-device
  # Waiting for the boot sequence to be completed.
  COMPLETED=$(adb shell getprop sys.boot_completed | tr -d '\r')
  while [ "$COMPLETED" != "1" ]; do
    COMPLETED=$(adb shell getprop sys.boot_completed | tr -d '\r')
    sleep 5
  done
  adb root
  adb shell settings put global window_animation_scale 0
  adb shell settings put global transition_animation_scale 0
  adb shell settings put global animator_duration_scale 0
  adb shell settings put global stay_on_while_plugged_in 0
  adb shell settings put system screen_off_timeout 15000
  adb shell settings put system accelerometer_rotation 0
  adb shell settings put global private_dns_mode hostname
  adb shell settings put global private_dns_specifier ${DNS:-one.one.one.one}
  adb shell settings put global airplane_mode_on 1
  adb shell am broadcast -a android.intent.action.AIRPLANE_MODE --ez state true
  adb shell svc data disable
  adb shell svc wifi enable
}

prepare_system() {
  adb wait-for-device
  adb root
  adb shell avbctl disable-verification
  adb disable-verity
  adb reboot
  adb wait-for-device
  adb root
  adb remount
}

install_libhoudini() {
  echo "Installing Libhoudini..."
  prepare_system
  wget -q "https://github.com/rote66/vendor_intel_proprietary_houdini/archive/debc3dc91cf12b5c5b8a1c546a5b0b7bf7f838a8.zip" -O libhoudini.zip
  unzip libhoudini.zip -d houdini_temp > /dev/null
  HOUDINI_DIR=$(ls -d houdini_temp/vendor_intel_proprietary_houdini-*)
  adb push "$HOUDINI_DIR/prebuilts/." /system/ > /dev/null
  echo "Libhoudini copied. Cleaning up..."
  rm -rf libhoudini.zip houdini_temp
  cat <<'EOF' > houdini.rc
on early-init
    mount binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc

on property:ro.enable.native.bridge.exec=1
    copy /system/etc/binfmt_misc/arm_exe /proc/sys/fs/binfmt_misc/register
    copy /system/etc/binfmt_misc/arm_dyn /proc/sys/fs/binfmt_misc/register

on property:ro.enable.native.bridge.exec64=1
    copy /system/etc/binfmt_misc/arm64_exe /proc/sys/fs/binfmt_misc/register
    copy /system/etc/binfmt_misc/arm64_dyn /proc/sys/fs/binfmt_misc/register

on property:sys.boot_completed=1
    exec -- /system/bin/sh -c "echo ':arm_exe:M::\\\\x7f\\\\x45\\\\x4c\\\\x46\\\\x01\\\\x01\\\\x01\\\\x00\\\\x00\\\\x00\\\\x00\\\\x00\\\\x00\\\\x00\\\\x00\\\\x00\\\\x02\\\\x00\\\\x28::/system/bin/houdini:P' >> /proc/sys/fs/binfmt_misc/register"
    exec -- /system/bin/sh -c "echo ':arm_dyn:M::\\\\x7f\\\\x45\\\\x4c\\\\x46\\\\x01\\\\x01\\\\x01\\\\x00\\\\x00\\\\x00\\\\x00\\\\x00\\\\x00\\\\x00\\\\x00\\\\x00\\\\x03\\\\x00\\\\x28::/system/bin/houdini:P' >> /proc/sys/fs/binfmt_misc/register"
    exec -- /system/bin/sh -c "echo ':arm64_exe:M::\\\\x7f\\\\x45\\\\x4c\\\\x46\\\\x02\\\\x01\\\\x01\\\\x00\\\\x00\\\\x00\\\\x00\\\\x00\\\\x00\\\\x00\\\\x00\\\\x00\\\\x02\\\\x00\\\\xb7::/system/bin/houdini64:P' >> /proc/sys/fs/binfmt_misc/register"
    exec -- /system/bin/sh -c "echo ':arm64_dyn:M::\\\\x7f\\\\x45\\\\x4c\\\\x46\\\\x02\\\\x01\\\\x01\\\\x00\\\\x00\\\\x00\\\\x00\\\\x00\\\\x00\\\\x00\\\\x00\\\\x00\\\\x03\\\\x00\\\\xb7::/system/bin/houdini64:P' >> /proc/sys/fs/binfmt_misc/register"
EOF

  adb push houdini.rc /system/etc/init/houdini.rc
  echo "Setting permissions..."
  adb shell chmod 644 /system/etc/init/houdini.rc
  adb shell chmod +x /system/bin/houdini
  adb shell chmod +x /system/bin/houdini64
  adb shell chmod -R 644 /system/lib/arm/
  [ -d "$HOUDINI_DIR/prebuilts/lib64" ] && adb shell chmod -R 644 /system/lib64/arm64/
  rm -rf libhoudini.zip houdini_temp houdini.rc
  echo "Libhoudini install script finished."

}


install_gapps() {
  prepare_system
  echo "Installing GAPPS ..."
  wget -q 'https://downloads.sourceforge.net/project/litegapps/litegapps/x86_64/34/core/2024-10-29/LiteGapps-core-x86_64-14.0-20241029-official.zip?ts=gAAAAABplqw3v7aVJ5yp7ESECmqyyG0Y7mpsEs1-kLGFwaUNNvbY7vfHYNF_vAXSPqmMxx2vPKbQDPOjl9Sbex1xIaa65FvPtg%3D%3D&use_mirror=master&r=https%3A%2F%2Fsourceforge.net%2Fprojects%2Flitegapps%2Ffiles%2Flitegapps%2Fx86_64%2F34%2Fcore%2F2024-10-29%2FLiteGapps-core-x86_64-14.0-20241029-official.zip%2Fdownload' -O gapps-14.zip
  unzip gapps-14.zip -d gapps-14 && rm gapps-14.zip
  mkdir -p gapps-14/appunpack
  tar -xvf gapps-14/files/files.tar.xz -C gapps-14/appunpack
  
  adb push gapps-14/appunpack/x86_64/34/system/. /system/
  rm -r gapps-14
  touch /data/.gapps-done
}

install_root() {
  adb wait-for-device
  echo "Root Script Starting..."
  # Root the AVD by patching the ramdisk.
  git clone https://gitlab.com/newbit/rootAVD.git
  pushd rootAVD
  sed -i 's/read -t 10 choice/choice=1/' rootAVD.sh
  ./rootAVD.sh system-images/android-34/default/x86_64/ramdisk.img
  cp /opt/android-sdk/system-images/android-34/default/x86_64/ramdisk.img /data/android.avd/ramdisk.img
  popd
  echo "Root Done"
  sleep 10
  rm -r rootAVD
  touch /data/.root-done
}

copy_extras() {
  adb wait-for-device
  # Push any Magisk modules for manual installation later
  for f in $(ls /extras/*); do
    adb push $f /sdcard/Download/
  done
}

# Detect the container's IP and forward ADB to localhost.
LOCAL_IP=$(ip addr list eth0 | grep "inet " | cut -d' ' -f6 | cut -d/ -f1)
socat tcp-listen:"5555",bind="$LOCAL_IP",fork tcp:127.0.0.1:"5555" &

gapps_needed=false
root_needed=false
houdini_needed=false
if bool_true "$GAPPS_SETUP" && [ ! -f /data/.gapps-done ]; then gapps_needed=true; fi
if bool_true "$ROOT_SETUP" && [ ! -f /data/.root-done ]; then root_needed=true; fi
if bool_true "$HOUDINI_SETUP" && [ ! -f /data/.houdini-done ]; then houdini_needed=true; fi

# Skip initialization if first boot already completed.
if [ -f /data/.first-boot-done ]; then
  [ "$gapps_needed" = true ] && install_gapps && [ "$root_needed" = false ] && adb reboot
  [ "$houdini_needed" = true ] && install_libhoudini
  [ "$root_needed" = true ] && install_root
  apply_settings
  copy_extras
  exit 0
fi

echo "Init AVD ..."
echo "no" | avdmanager create avd -n android -c 64G -k "system-images;android-34;default;x86_64"

[ "$gapps_needed" = true ] && install_gapps && [ "$root_needed" = false ] && adb reboot
[ "$houdini_needed" = true ] && install_libhoudini
[ "$root_needed" = true ] && install_root
apply_settings
copy_extras

touch /data/.first-boot-done
echo "Success !!"
