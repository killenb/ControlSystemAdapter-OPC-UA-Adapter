#!/bin/bash
SETUP_COMMAND="$1"
CMAKE_PROJECT_DIRECTORY="$2"
SUBPROJECT_BUILD_DIRERCTORY="$3"

function usage() {
    echo "setup script usage: setup_<depName> [install|uninstall] CMAKE_PROJECT_DIRECTORY SUBPROJECT_BUILD_DIRERCTORY"
    echo ""
}

function log() {
    echo $@
}

## Check Options
if [ $# -lt 3 ];then
  exit 1
fi

case $SETUP_COMMAND in
install)
  log "Installing headers"
  cp -rLf "$SUBPROJECT_BUILD_DIRERCTORY"/../include/ChimeraTK "$CMAKE_PROJECT_DIRECTORY"/include/
  cp -rLf "$SUBPROJECT_BUILD_DIRERCTORY"/../examples/cosade/IndependentControlCore.h "$CMAKE_PROJECT_DIRECTORY"/include/ChimeraTK/ControlSystemAdapter
  log "Installing libraries"
  mkdir -p "$CMAKE_PROJECT_DIRECTORY/lib"
  cp "$SUBPROJECT_BUILD_DIRERCTORY"/libChimeraTK* "$CMAKE_PROJECT_DIRECTORY/lib"
  ;;
uninstall)
  rm -r "$CMAKE_PROJECT_DIRECTORY"/include/ChimeraTK
  rm -r "$CMAKE_PROJECT_DIRECTORY"/lib/libChimeraTK*
;;
*) 
  echo "Invalid script command \"$1\""
  usage
  exit 1
;;
esac

exit 0
