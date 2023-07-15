get_name_platform() {
  if uname -a | grep -i "GNU/Linux" >/dev/null
  then
    awk -F= '$1=="ID" { print $2 ;}' /etc/os-release
  elif uname -a | grep -i "darwin" >/dev/null
  then
    echo "darwin"
#  elif [[ "$OSTYPE" == "cygwin" ]]; then
#          # POSIX compatibility layer and Linux environment emulation for Windows
#  elif [[ "$OSTYPE" == "msys" ]]; then
#          # Lightweight shell and GNU utilities compiled for Windows (part of MinGW)
#  elif [[ "$OSTYPE" == "win32" ]]; then
#          # I'm not sure this can happen.
#  elif [[ "$OSTYPE" == "freebsd"* ]]; then
#          # ...
#  else
#          # Unknown.
  fi
}
